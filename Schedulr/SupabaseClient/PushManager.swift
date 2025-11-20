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
        // Clear the app icon badge when the app becomes active
        UIApplication.shared.applicationIconBadgeNumber = 0
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
        // Show notification banner even when app is in foreground
        // Note: We still show .badge here so the server can update the badge count,
        // but we'll clear it when the user becomes active or interacts with notifications
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clear the app icon badge when user interacts with notification
        UIApplication.shared.applicationIconBadgeNumber = 0

        // Handle notification tap here if needed
        // For example, navigate to the relevant event

        completionHandler()
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


