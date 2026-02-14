import Foundation
import UserNotifications
import UIKit
import Supabase

final class PushManager: NSObject, UNUserNotificationCenterDelegate, UIApplicationDelegate {
    static let shared = PushManager()
    private override init() {}

    func registerForPush() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    // UIApplicationDelegate passthroughs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await upload(token: token) }
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Sync badge count IMMEDIATELY when app becomes active
        // This overrides any badge value sent in notification payload (which might be 1)
        // and ensures badge count matches actual delivered notifications
        // Sync multiple times with increasing delays to catch notifications at different stages
        syncBadgeCountWithPendingNotifications()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.syncBadgeCountWithPendingNotifications()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Sync badge count when app is about to enter foreground
        // This handles the case where app was backgrounded and user is bringing it to foreground
        // Sync immediately to override any badge: 1 values sent in notifications
        syncBadgeCountWithPendingNotifications()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.syncBadgeCountWithPendingNotifications()
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Sync badge count when app enters background
        // This ensures badge is accurate when user backgrounds the app
        syncBadgeCountWithPendingNotifications()
    }
    
    // Handle notifications received in background (app is backgrounded or phone is locked)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let aps = userInfo["aps"] as? [String: Any]
        let alertPayload = aps?["alert"]
        let title: String?
        let body: String?
        if let alert = alertPayload as? [String: Any] {
            title = alert["title"] as? String
            body = alert["body"] as? String
        } else if let alert = alertPayload as? String {
            title = nil
            body = alert
        } else {
            title = nil
            body = nil
        }
        InAppNotificationStore.capture(userInfo: userInfo, title: title, body: body)

        // When notifications arrive while app is backgrounded or phone is locked,
        // Sync badge count immediately to ensure accuracy
        // Use multiple delays to catch the notification at different stages of processing
        syncBadgeCountWithPendingNotifications()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.syncBadgeCountWithPendingNotifications()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncBadgeCountWithPendingNotifications()
        }
        completionHandler(.newData)
    }
    
    // Sync badge count by checking pending notifications
    // This ensures badge count is accurate even if notifications arrived while app was backgrounded
    private func syncBadgeCountWithPendingNotifications() {
        InAppNotificationStore.refreshFromDeliveredNotifications()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Suppress APNs errors in simulator/development (expected when entitlements aren't configured)
        #if DEBUG
        let nsError = error as NSError
        // Only log if it's not the expected "no valid aps-environment" error in simulator
        if nsError.domain == "NSCocoaErrorDomain" && nsError.code == 3000 {
            // Expected error in simulator - suppress
            return
        }
        #endif
        print("APNs registration failed: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        InAppNotificationStore.capture(notification: notification)

        // Update badge count immediately and multiple times with delays
        // This ensures badge count is accurate even if notification payload had badge: 1
        // The notification may not be in delivered notifications immediately, so we sync multiple times
        updateBadgeCount()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateBadgeCount()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateBadgeCount()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateBadgeCount()
        }
        
        // Show notification banner even when app is in foreground
        // Include .list to ensure notification appears in notification center
        // Don't include .badge - we'll set it manually via updateBadgeCount() for accuracy
        completionHandler([.banner, .sound, .list])
    }

    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        InAppNotificationStore.capture(notification: response.notification)

        let userInfo = response.notification.request.content.userInfo
        let notificationType = stringValue(for: "notification_type", in: userInfo) ?? "event_invite"
        
        // Handle navigation based on notification type
        switch notificationType {
        case "event_invite", "event_update", "event_cancellation", "rsvp_response", "event_reminder", "rain_check_requested", "rain_check_approved", "rain_check_denied", "event_rescheduled":
            // Event-related notifications - navigate to event detail
            if let eventId = extractEventId(from: userInfo) {
                UserDefaults.standard.set(eventId.uuidString, forKey: "PendingNavigationEventId")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToEvent"),
                        object: nil,
                        userInfo: ["eventId": eventId]
                    )
                }
            }
            
        case "new_group_member", "group_member_left", "group_ownership_transfer", "group_renamed":
            // Group-related notifications - navigate to group dashboard
            if let groupId = extractUUID(forKeys: ["group_id"], from: userInfo) {
                UserDefaults.standard.set(groupId.uuidString, forKey: "PendingNavigationGroupId")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToGroup"),
                        object: nil,
                        userInfo: ["groupId": groupId]
                    )
                }
            }
            
        case "group_deleted":
            // Group deleted - navigate to profile/groups section
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToProfile"),
                    object: nil,
                    userInfo: nil
                )
            }
            
        case "subscription_change", "feature_limit_warning":
            // Subscription-related notifications - navigate to profile/subscription
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToProfile"),
                    object: nil,
                    userInfo: ["showSubscription": true]
                )
            }
            
        default:
            // Fallback: navigate to event if any event identifier is present
            if let eventId = extractEventId(from: userInfo) {
                UserDefaults.standard.set(eventId.uuidString, forKey: "PendingNavigationEventId")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToEvent"),
                        object: nil,
                        userInfo: ["eventId": eventId]
                    )
                }
            }
        }
        
        // Note: We intentionally do NOT remove the notification when tapped.
        // This allows users to re-read notifications in the in-app notification list
        // even if they tapped quickly without reading. Users can manually mark
        // notifications as read from the in-app notification list.

        completionHandler()
    }
    
    // Update badge count when notification is received
    // This should be called from willPresent to track badge count locally
    private func updateBadgeCount() {
        InAppNotificationStore.refreshFromDeliveredNotifications()
    }

    private func extractEventId(from userInfo: [AnyHashable: Any]) -> UUID? {
        extractUUID(forKeys: ["event_id", "new_event_id", "old_event_id", "eventId", "newEventId", "oldEventId"], from: userInfo)
    }

    private func extractUUID(forKeys keys: [String], from userInfo: [AnyHashable: Any]) -> UUID? {
        for key in keys {
            if let value = value(for: key, in: userInfo),
               let uuid = parseUUID(from: value) {
                return uuid
            }
        }
        return nil
    }

    private func stringValue(for key: String, in userInfo: [AnyHashable: Any]) -> String? {
        guard let value = value(for: key, in: userInfo) else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func value(for key: String, in userInfo: [AnyHashable: Any]) -> Any? {
        if let value = userInfo[key] {
            return value
        }
        if let data = userInfo["data"] as? [AnyHashable: Any],
           let value = data[key] {
            return value
        }
        return nil
    }

    private func parseUUID(from value: Any) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }
        if let value = value as? String {
            return UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = value as? NSString {
            return UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = value as? NSNumber {
            return UUID(uuidString: value.stringValue)
        }
        return nil
    }

    private func upload(token: String) async {
        do {
            guard let client = SupabaseManager.shared.client else {
                return
            }
            let uid = try await client.auth.session.user.id
            struct Row: Encodable { let user_id: UUID; let apns_token: String }
            let row = Row(user_id: uid, apns_token: token)
            _ = try await client.from("user_devices").upsert(row, onConflict: "user_id").execute()
        } catch {
            // Token upload failed - silently fail for now
            // In production, you might want to retry or log to analytics
        }
    }
}
