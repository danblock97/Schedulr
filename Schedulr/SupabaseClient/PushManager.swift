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

    private func upload(token: String) async {
        do {
            guard let client = SupabaseManager.shared.client else {
                print("❌ PushManager: Supabase client not available")
                return
            }
            let uid = try await client.auth.session.user.id
            struct Row: Encodable { let user_id: UUID; let apns_token: String }
            let row = Row(user_id: uid, apns_token: token)
            print("📱 PushManager: Uploading APNs token for user \(uid.uuidString.prefix(8))...")
            _ = try await client.from("user_devices").upsert(row, onConflict: "user_id").execute()
            print("✅ PushManager: APNs token uploaded successfully")
        } catch {
            print("❌ PushManager: Failed to upload APNs token: \(error)")
        }
    }
}


