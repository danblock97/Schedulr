//
//  NotificationViewModel.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationViewModel: ObservableObject {
    @Published var notifications: [UNNotification] = []
    @Published var badgeCount: Int = 0
    @Published var isLoading: Bool = false
    
    init() {
        loadNotifications()
        updateBadgeCount()
        
        // Listen for app becoming active to refresh notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func loadNotifications() {
        isLoading = true
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            Task { @MainActor in
                self?.notifications = notifications.sorted { notification1, notification2 in
                    // Sort by date, most recent first
                    notification1.date > notification2.date
                }
                self?.applyBadgeCount(notifications.count)
                self?.isLoading = false
            }
        }
    }
    
    func updateBadgeCount() {
        UNUserNotificationCenter.current().getDeliveredNotifications { [weak self] notifications in
            Task { @MainActor in
                self?.applyBadgeCount(notifications.count)
            }
        }
    }
    
    func markAllAsRead() {
        // Remove all delivered notifications
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        // Update local state
        notifications = []
        applyBadgeCount(0)
        
        #if DEBUG
        print("[NotificationViewModel] Marked all notifications as read and cleared badge")
        #endif
    }
    
    func markAsRead(_ notification: UNNotification) {
        // Remove specific notification
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
        
        // Update local state
        notifications.removeAll { $0.request.identifier == notification.request.identifier }
        
        // Update badge count
        updateBadgeCount()
        
        // Sync badge count
        syncBadgeCount()
    }
    
    private func syncBadgeCount() {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let badgeCount = notifications.count
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
                UserDefaults.standard.set(badgeCount, forKey: "SchedulrBadgeCount")
            }
        }
    }

    private func applyBadgeCount(_ count: Int) {
        badgeCount = count
        UIApplication.shared.applicationIconBadgeNumber = count
        UserDefaults.standard.set(count, forKey: "SchedulrBadgeCount")
    }
    
    func refresh() {
        loadNotifications()
        updateBadgeCount()
    }
}

