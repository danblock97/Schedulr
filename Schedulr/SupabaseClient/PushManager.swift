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
        
        // Check for pending navigation event ID (from notification tap when app was in background)
        if let eventIdString = UserDefaults.standard.string(forKey: "PendingNavigationEventId"),
           let eventId = UUID(uuidString: eventIdString) {
            // Clear it first to prevent duplicate navigation
            UserDefaults.standard.removeObject(forKey: "PendingNavigationEventId")
            // Post navigation notification with delay to ensure views are ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToEvent"),
                    object: nil,
                    userInfo: ["eventId": eventId]
                )
            }
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
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let badgeCount = notifications.count
            DispatchQueue.main.async {
                // Always update badge count to match delivered notifications
                // This overrides any badge value sent in notification payload
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
                UserDefaults.standard.set(badgeCount, forKey: "SchedulrBadgeCount")
                #if DEBUG
                print("[PushManager] Synced badge count to \(badgeCount) based on \(notifications.count) delivered notifications")
                if notifications.count > 0 {
                    print("[PushManager] Notification titles: \(notifications.map { $0.request.content.title })")
                } else {
                    print("[PushManager] No delivered notifications - badge cleared")
                }
                #endif
            }
        }
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
        // Extract event_id from notification payload and post notification for navigation
        let userInfo = response.notification.request.content.userInfo
        if let eventIdString = userInfo["event_id"] as? String,
           let eventId = UUID(uuidString: eventIdString) {
            // Store event ID in UserDefaults as a fallback in case notification is missed
            UserDefaults.standard.set(eventIdString, forKey: "PendingNavigationEventId")
            
            // Post notification with a longer delay to ensure app is ready, especially on cold start
            // This handles the case where the app launches from a notification tap
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToEvent"),
                    object: nil,
                    userInfo: ["eventId": eventId]
                )
            }
        }
        
        // Explicitly remove the tapped notification from delivered notifications
        // This ensures it's removed and badge count updates correctly
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        
        // Sync badge count after removing notification
        // Use a delay to ensure iOS has processed the removal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.syncBadgeCountWithPendingNotifications()
        }

        completionHandler()
    }
    
    // Update badge count when notification is received
    // This should be called from willPresent to track badge count locally
    private func updateBadgeCount() {
        // Get current delivered notifications to calculate accurate badge count
        // This includes the notification that just arrived
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let badgeCount = notifications.count
            DispatchQueue.main.async {
                // Set badge count to match number of delivered notifications
                // This overrides any badge value sent in the notification payload
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
                UserDefaults.standard.set(badgeCount, forKey: "SchedulrBadgeCount")
                #if DEBUG
                print("[PushManager] Updated badge count to \(badgeCount) based on \(notifications.count) delivered notifications")
                if notifications.count > 0 {
                    print("[PushManager] Notification titles: \(notifications.map { $0.request.content.title })")
                }
                #endif
            }
        }
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


