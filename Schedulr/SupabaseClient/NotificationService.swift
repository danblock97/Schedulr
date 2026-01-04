import Foundation
import Supabase

/// Centralized service for triggering push notifications
/// All notification methods are fire-and-forget - they don't throw errors to avoid
/// disrupting the main user flow if notifications fail to send
final class NotificationService {
    static let shared = NotificationService()
    private init() {}
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    // MARK: - Event Notifications
    
    /// Notify attendees when an event is updated
    /// - Parameters:
    ///   - eventId: The ID of the updated event
    ///   - updaterUserId: The user who made the update (will be excluded from notifications)
    func notifyEventUpdate(eventId: UUID, updaterUserId: UUID) {
        Task {
            await sendNotification(
                type: "event_update",
                payload: [
                    "event_id": eventId.uuidString,
                    "updater_user_id": updaterUserId.uuidString
                ]
            )
        }
    }
    
    /// Notify attendees when an event is cancelled/deleted
    /// - Parameters:
    ///   - eventId: The ID of the cancelled event
    ///   - creatorUserId: The event creator (will be excluded from notifications)
    ///   - attendeeUserIds: List of attendee user IDs to notify (must be fetched before deletion)
    func notifyEventCancellation(eventId: UUID, creatorUserId: UUID, attendeeUserIds: [UUID]) {
        Task {
            // For cancellations, we need to notify before the event is deleted
            // The edge function will try to fetch event details, but they might be gone
            await sendNotification(
                type: "event_cancellation",
                payload: [
                    "event_id": eventId.uuidString,
                    "creator_user_id": creatorUserId.uuidString
                ]
            )
        }
    }
    
    /// Notify event creator when someone responds to their event
    /// - Parameters:
    ///   - eventId: The event that received the RSVP
    ///   - responderUserId: The user who responded
    ///   - status: The RSVP status (going, maybe, declined)
    func notifyRSVPResponse(eventId: UUID, responderUserId: UUID, status: String) {
        Task {
            await sendNotification(
                type: "rsvp_response",
                payload: [
                    "event_id": eventId.uuidString,
                    "responder_user_id": responderUserId.uuidString,
                    "rsvp_status": status
                ]
            )
        }
    }

    /// Notify event creator when an attendee requests a rain check
    /// - Parameters:
    ///   - eventId: The event that was requested for rain check
    ///   - requesterId: The attendee who requested the rain check
    ///   - creatorId: The event creator who should be notified
    func notifyRainCheckRequested(eventId: UUID, requesterId: UUID, creatorId: UUID) {
        Task {
            await sendNotification(
                type: "rain_check_requested",
                payload: [
                    "event_id": eventId.uuidString,
                    "requester_user_id": requesterId.uuidString,
                    "creator_user_id": creatorId.uuidString
                ]
            )
        }
    }

    /// Notify all attendees when a rain check is approved
    /// - Parameters:
    ///   - eventId: The event that was rain-checked
    ///   - attendeeUserIds: List of attendee user IDs to notify
    func notifyRainCheckApproved(eventId: UUID, attendeeUserIds: [UUID]) {
        Task {
            await sendNotification(
                type: "rain_check_approved",
                payload: [
                    "event_id": eventId.uuidString,
                    "attendee_user_ids": attendeeUserIds.map { $0.uuidString }.joined(separator: ",")
                ]
            )
        }
    }

    /// Notify requester when their rain check request is denied
    /// - Parameters:
    ///   - eventId: The event that was not rain-checked
    ///   - requesterId: The attendee who requested the rain check
    func notifyRainCheckDenied(eventId: UUID, requesterId: UUID) {
        Task {
            await sendNotification(
                type: "rain_check_denied",
                payload: [
                    "event_id": eventId.uuidString,
                    "requester_user_id": requesterId.uuidString
                ]
            )
        }
    }

    /// Notify attendees when a rain-checked event has been rescheduled
    /// - Parameters:
    ///   - newEventId: The ID of the newly created rescheduled event
    ///   - oldEventId: The ID of the original rain-checked event
    ///   - attendeeUserIds: List of attendee user IDs to notify
    func notifyEventRescheduled(newEventId: UUID, oldEventId: UUID, attendeeUserIds: [UUID]) {
        Task {
            await sendNotification(
                type: "event_rescheduled",
                payload: [
                    "new_event_id": newEventId.uuidString,
                    "old_event_id": oldEventId.uuidString,
                    "attendee_user_ids": attendeeUserIds.map { $0.uuidString }.joined(separator: ",")
                ]
            )
        }
    }

    // MARK: - Group Notifications
    
    /// Notify group members when a new member joins
    /// - Parameters:
    ///   - groupId: The group that was joined
    ///   - memberUserId: The new member's user ID
    func notifyNewGroupMember(groupId: UUID, memberUserId: UUID) {
        Task {
            await sendNotification(
                type: "new_group_member",
                payload: [
                    "group_id": groupId.uuidString,
                    "member_user_id": memberUserId.uuidString
                ]
            )
        }
    }
    
    /// Notify group members when someone leaves the group
    /// - Parameters:
    ///   - groupId: The group that was left
    ///   - memberUserId: The user who left
    ///   - actorUserId: The user who initiated the leave (might be same as memberUserId)
    func notifyGroupMemberLeft(groupId: UUID, memberUserId: UUID, actorUserId: UUID? = nil) {
        Task {
            var payload: [String: String] = [
                "group_id": groupId.uuidString,
                "member_user_id": memberUserId.uuidString
            ]
            if let actorId = actorUserId {
                payload["actor_user_id"] = actorId.uuidString
            }
            await sendNotification(type: "group_member_left", payload: payload)
        }
    }
    
    /// Notify the new owner when group ownership is transferred
    /// - Parameters:
    ///   - groupId: The group whose ownership was transferred
    ///   - newOwnerUserId: The new owner's user ID
    ///   - actorUserId: The previous owner who transferred ownership
    func notifyGroupOwnershipTransfer(groupId: UUID, newOwnerUserId: UUID, actorUserId: UUID) {
        Task {
            await sendNotification(
                type: "group_ownership_transfer",
                payload: [
                    "group_id": groupId.uuidString,
                    "new_owner_user_id": newOwnerUserId.uuidString,
                    "actor_user_id": actorUserId.uuidString
                ]
            )
        }
    }
    
    /// Notify group members when the group is renamed
    /// - Parameters:
    ///   - groupId: The renamed group
    ///   - newName: The new group name
    ///   - renamedByUserId: The user who renamed the group
    func notifyGroupRenamed(groupId: UUID, newName: String, renamedByUserId: UUID) {
        Task {
            await sendNotification(
                type: "group_renamed",
                payload: [
                    "group_id": groupId.uuidString,
                    "new_group_name": newName,
                    "actor_user_id": renamedByUserId.uuidString
                ]
            )
        }
    }
    
    /// Notify group members when a group is deleted
    /// Note: Must be called BEFORE the group is deleted, with member list pre-fetched
    /// - Parameters:
    ///   - groupName: The name of the deleted group
    ///   - memberUserIds: The user IDs of group members to notify
    ///   - deletedByUserId: The user who deleted the group
    func notifyGroupDeleted(groupName: String, memberUserIds: [UUID], deletedByUserId: UUID) {
        Task {
            guard let client else { return }
            
            // Filter out the deleter (edge function also filters, but do it here to avoid unnecessary call)
            let usersToNotify = memberUserIds.filter { $0 != deletedByUserId }
            guard !usersToNotify.isEmpty else { return }
            
            struct Payload: Encodable {
                let notification_type: String
                let user_ids: [String]
                let group_name: String
                let actor_user_id: String
                let title: String
                let body: String
                let preference_key: String
            }
            
            let payload = Payload(
                notification_type: "group_deleted",
                user_ids: usersToNotify.map { $0.uuidString },
                group_name: groupName,
                actor_user_id: deletedByUserId.uuidString,
                title: "Group Deleted",
                body: "\"\(groupName)\" has been deleted",
                preference_key: "notify_group_deleted"
            )
            
            do {
                _ = try await client.functions
                    .invoke("notify-event", options: FunctionInvokeOptions(body: payload))
                
                #if DEBUG
                print("[NotificationService] Sent group_deleted notification to \(usersToNotify.count) users")
                #endif
            } catch {
                #if DEBUG
                print("[NotificationService] Failed to send group deleted notification: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Subscription Notifications
    
    /// Notify user about subscription status changes
    /// - Parameters:
    ///   - userId: The user whose subscription changed
    ///   - changeType: Type of change (upgraded, downgraded, expired, grace_period_started, grace_period_ending)
    ///   - newTier: The new subscription tier (optional)
    func notifySubscriptionChange(userId: UUID, changeType: String, newTier: String? = nil) {
        Task {
            var payload: [String: String] = [
                "target_user_id": userId.uuidString,
                "change_type": changeType
            ]
            if let tier = newTier {
                payload["new_tier"] = tier
            }
            await sendNotification(type: "subscription_change", payload: payload)
        }
    }
    
    /// Notify user when approaching feature limits
    /// - Parameters:
    ///   - userId: The user approaching the limit
    ///   - limitType: Type of limit (groups, group_members, ai_requests)
    ///   - currentCount: Current usage count
    ///   - maxCount: Maximum allowed count
    func notifyFeatureLimitWarning(userId: UUID, limitType: String, currentCount: Int, maxCount: Int) {
        Task {
            await sendNotification(
                type: "feature_limit_warning",
                payload: [
                    "target_user_id": userId.uuidString,
                    "limit_type": limitType,
                    "current_count": String(currentCount),
                    "max_count": String(maxCount)
                ]
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func sendNotification(type: String, payload: [String: String]) async {
        guard let client else {
            #if DEBUG
            print("[NotificationService] Supabase client unavailable")
            #endif
            return
        }
        
        struct NotificationPayload: Encodable {
            let notification_type: String
            let data: [String: String]
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: DynamicCodingKeys.self)
                try container.encode(notification_type, forKey: DynamicCodingKeys(stringValue: "notification_type")!)
                
                // Flatten data into the root level
                for (key, value) in data {
                    try container.encode(value, forKey: DynamicCodingKeys(stringValue: key)!)
                }
            }
        }
        
        let notificationPayload = NotificationPayload(notification_type: type, data: payload)
        
        do {
            _ = try await client.functions
                .invoke("notify-event", options: FunctionInvokeOptions(body: notificationPayload))
            
            #if DEBUG
            print("[NotificationService] Sent \(type) notification")
            #endif
        } catch {
            #if DEBUG
            print("[NotificationService] Failed to send \(type) notification: \(error)")
            #endif
        }
    }
}

// MARK: - Dynamic Coding Keys

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

