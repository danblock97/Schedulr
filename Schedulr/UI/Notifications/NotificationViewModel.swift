//
//  NotificationViewModel.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation
import UserNotifications
import UIKit

struct InAppNotificationItem: Codable, Identifiable, Equatable {
    let id: String
    let remoteIdentifier: String?
    let title: String
    let body: String
    let date: Date
    let notificationType: String
    let eventId: String?
    let groupId: String?
    let userInfo: [String: String]
}

extension Notification.Name {
    static let inAppNotificationsDidChange = Notification.Name("SchedulrInAppNotificationsDidChange")
}

enum InAppNotificationStore {
    private static let storageKey = "SchedulrInAppNotificationsV1"
    private static let badgeKey = "SchedulrBadgeCount"
    private static let maxStoredItems = 200
    private static let likelyDuplicateWindow: TimeInterval = 30

    static func load() -> [InAppNotificationItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InAppNotificationItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.date > $1.date }
    }

    static func capture(notification: UNNotification) {
        merge(notifications: [notification])
    }

    static func capture(
        userInfo: [AnyHashable: Any],
        title: String?,
        body: String?,
        date: Date = Date(),
        remoteIdentifier: String? = nil
    ) {
        let resolvedTitle = title ?? ""
        let resolvedBody = body ?? ""
        let hasVisibleContent = !resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !resolvedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasVisibleContent else {
            return
        }

        let content = ParsedNotificationContent(
            remoteIdentifier: remoteIdentifier,
            title: resolvedTitle,
            body: resolvedBody,
            date: date,
            userInfo: userInfo
        )
        merge(contents: [content])
    }

    static func refreshFromDeliveredNotifications(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            merge(notifications: notifications)
            completion?()
        }
    }

    static func markAllAsRead() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        persist([], notifyChange: true)
    }

    static func markAsRead(_ notification: InAppNotificationItem) {
        if let remoteIdentifier = notification.remoteIdentifier, !remoteIdentifier.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [remoteIdentifier])
        }

        let remaining = load().filter { $0.id != notification.id }
        persist(remaining, notifyChange: true)
    }

    static func syncBadgeCount() {
        applyBadgeCount(load().count)
    }

    private struct ParsedNotificationContent {
        let remoteIdentifier: String?
        let title: String
        let body: String
        let date: Date
        let userInfo: [AnyHashable: Any]
    }

    private static func merge(notifications: [UNNotification]) {
        let parsed = notifications.map { notification in
            ParsedNotificationContent(
                remoteIdentifier: notification.request.identifier,
                title: notification.request.content.title,
                body: notification.request.content.body,
                date: notification.date,
                userInfo: notification.request.content.userInfo
            )
        }
        merge(contents: parsed)
    }

    private static func merge(contents: [ParsedNotificationContent]) {
        guard !contents.isEmpty else {
            applyBadgeCount(load().count)
            return
        }

        var existing = load()
        var changed = false

        for content in contents {
            let normalizedUserInfo = normalizeUserInfo(content.userInfo)
            let incoming = InAppNotificationItem(
                id: UUID().uuidString,
                remoteIdentifier: content.remoteIdentifier,
                title: content.title,
                body: content.body,
                date: content.date,
                notificationType: normalizedUserInfo["notification_type"] ?? "general",
                eventId: normalizedUserInfo["event_id"] ?? normalizedUserInfo["new_event_id"] ?? normalizedUserInfo["old_event_id"],
                groupId: normalizedUserInfo["group_id"],
                userInfo: normalizedUserInfo
            )

            if let remoteIdentifier = incoming.remoteIdentifier, !remoteIdentifier.isEmpty,
               existing.contains(where: { $0.remoteIdentifier == remoteIdentifier }) {
                continue
            }

            if let duplicateIndex = existing.firstIndex(where: { isLikelyDuplicate($0, incoming) }) {
                let current = existing[duplicateIndex]
                let mergedRemoteIdentifier = current.remoteIdentifier ?? incoming.remoteIdentifier
                let mergedEventId = current.eventId ?? incoming.eventId
                let mergedGroupId = current.groupId ?? incoming.groupId
                let mergedUserInfo = current.userInfo.merging(incoming.userInfo) { old, new in
                    old.isEmpty ? new : old
                }
                let merged = InAppNotificationItem(
                    id: current.id,
                    remoteIdentifier: mergedRemoteIdentifier,
                    title: current.title,
                    body: current.body,
                    date: max(current.date, incoming.date),
                    notificationType: current.notificationType,
                    eventId: mergedEventId,
                    groupId: mergedGroupId,
                    userInfo: mergedUserInfo
                )
                if merged != current {
                    existing[duplicateIndex] = merged
                    changed = true
                }
                continue
            }

            existing.append(incoming)
            changed = true
        }

        if changed {
            persist(existing, notifyChange: true)
        } else {
            applyBadgeCount(existing.count)
        }
    }

    private static func isLikelyDuplicate(_ lhs: InAppNotificationItem, _ rhs: InAppNotificationItem) -> Bool {
        if let lhsRemote = lhs.remoteIdentifier, !lhsRemote.isEmpty,
           let rhsRemote = rhs.remoteIdentifier, !rhsRemote.isEmpty {
            return lhsRemote == rhsRemote
        }
        return duplicateKey(for: lhs) == duplicateKey(for: rhs) &&
        abs(lhs.date.timeIntervalSince(rhs.date)) < likelyDuplicateWindow
    }

    private static func duplicateKey(for item: InAppNotificationItem) -> String {
        let actorIdentifier =
            item.userInfo["responder_user_id"] ??
            item.userInfo["requester_user_id"] ??
            item.userInfo["member_user_id"] ??
            item.userInfo["actor_user_id"] ??
            item.userInfo["target_user_id"] ??
            ""
        return [
            item.notificationType,
            item.eventId ?? "",
            item.groupId ?? "",
            actorIdentifier,
            item.title,
            item.body
        ].joined(separator: "|")
    }

    private static func persist(_ items: [InAppNotificationItem], notifyChange: Bool) {
        let normalized = Array(items.sorted { $0.date > $1.date }.prefix(maxStoredItems))
        if let encoded = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }

        applyBadgeCount(normalized.count)

        if notifyChange {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .inAppNotificationsDidChange, object: nil)
            }
        }
    }

    private static func normalizeUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in userInfo {
            guard let keyString = key as? String,
                  let valueString = stringify(value) else {
                continue
            }
            normalized[keyString] = valueString
        }
        return normalized
    }

    private static func stringify(_ value: Any) -> String? {
        if let value = value as? String { return value }
        if let value = value as? UUID { return value.uuidString }
        if let value = value as? NSNumber { return value.stringValue }
        if let value = value as? Date {
            return ISO8601DateFormatter().string(from: value)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }

    private static func applyBadgeCount(_ count: Int) {
        DispatchQueue.main.async {
            if #available(iOS 17.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            UserDefaults.standard.set(count, forKey: badgeKey)
        }
    }
}

@MainActor
class NotificationViewModel: ObservableObject {
    @Published var notifications: [InAppNotificationItem] = []
    @Published var badgeCount: Int = 0
    @Published var isLoading: Bool = false
    private var observerTokens: [NSObjectProtocol] = []
    
    init() {
        loadNotifications()
        updateBadgeCount()
        
        // Listen for app becoming active to refresh notifications and import
        // whatever iOS is currently holding in Notification Center.
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        observerTokens.append(activeObserver)

        let changedObserver = NotificationCenter.default.addObserver(
            forName: .inAppNotificationsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadNotificationsFromStore()
            }
        }
        observerTokens.append(changedObserver)

        InAppNotificationStore.refreshFromDeliveredNotifications()
    }
    
    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    func loadNotifications() {
        isLoading = true
        loadNotificationsFromStore()
        isLoading = false
        InAppNotificationStore.refreshFromDeliveredNotifications()
    }
    
    func updateBadgeCount() {
        applyBadgeCount(InAppNotificationStore.load().count)
        InAppNotificationStore.syncBadgeCount()
    }
    
    func markAllAsRead() {
        InAppNotificationStore.markAllAsRead()
        
        // Update local state
        notifications = []
        applyBadgeCount(0)
        
        #if DEBUG
        print("[NotificationViewModel] Marked all notifications as read and cleared badge")
        #endif
    }
    
    func markAsRead(_ notification: InAppNotificationItem) {
        InAppNotificationStore.markAsRead(notification)
        
        // Update local state
        notifications.removeAll { $0.id == notification.id }
        
        // Update badge count
        applyBadgeCount(notifications.count)
        InAppNotificationStore.syncBadgeCount()
    }

    private func applyBadgeCount(_ count: Int) {
        badgeCount = count
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
        UserDefaults.standard.set(count, forKey: "SchedulrBadgeCount")
    }

    private func loadNotificationsFromStore() {
        notifications = InAppNotificationStore.load()
        applyBadgeCount(notifications.count)
    }
    
    func refresh() {
        loadNotifications()
        updateBadgeCount()
    }
}
