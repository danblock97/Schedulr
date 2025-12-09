import Foundation
import Supabase

// MARK: - Notification Preferences Model

struct NotificationPreferences: Codable, Equatable {
    var eventReminderHoursBefore: Int
    var notifyEventUpdates: Bool
    var notifyEventCancellations: Bool
    var notifyRsvpResponses: Bool
    var notifyEventReminders: Bool
    var notifyNewGroupMembers: Bool
    var notifyGroupMemberLeft: Bool
    var notifyGroupOwnershipTransfer: Bool
    var notifyGroupRenamed: Bool
    var notifyGroupDeleted: Bool
    var notifySubscriptionChanges: Bool
    var notifyFeatureLimitWarnings: Bool
    // Engagement nudges
    var notifyEmptyWeekNudges: Bool
    var notifyGroupQuietPings: Bool
    var notifyAIAssistFollowups: Bool
    
    // Default preferences
    static let `default` = NotificationPreferences(
        eventReminderHoursBefore: 24, // 1 day before
        notifyEventUpdates: true,
        notifyEventCancellations: true,
        notifyRsvpResponses: true,
        notifyEventReminders: true,
        notifyNewGroupMembers: true,
        notifyGroupMemberLeft: true,
        notifyGroupOwnershipTransfer: true,
        notifyGroupRenamed: true,
        notifyGroupDeleted: true,
        notifySubscriptionChanges: true,
        notifyFeatureLimitWarnings: true,
        notifyEmptyWeekNudges: true,
        notifyGroupQuietPings: true,
        notifyAIAssistFollowups: true
    )
}

// MARK: - Reminder Timing Options

enum ReminderTiming: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 0 // Stored as 0, but we'll handle fractional hours
    case thirtyMinutes = 1
    case oneHour = 2
    case twoHours = 3
    case sixHours = 6
    case twelveHours = 12
    case oneDay = 24
    case twoDays = 48
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .twoHours: return "2 hours before"
        case .sixHours: return "6 hours before"
        case .twelveHours: return "12 hours before"
        case .oneDay: return "1 day before"
        case .twoDays: return "2 days before"
        }
    }
    
    // Convert to hours for storage (using special values for fractional hours)
    var hoursValue: Int {
        switch self {
        case .fifteenMinutes: return 0 // Special: 0 means 15 minutes
        case .thirtyMinutes: return 1  // Special: 1 means 30 minutes
        case .oneHour: return 2        // Special: 2 means 1 hour
        case .twoHours: return 3       // Special: 3 means 2 hours
        case .sixHours: return 6
        case .twelveHours: return 12
        case .oneDay: return 24
        case .twoDays: return 48
        }
    }
    
    static func from(hoursValue: Int) -> ReminderTiming {
        switch hoursValue {
        case 0: return .fifteenMinutes
        case 1: return .thirtyMinutes
        case 2: return .oneHour
        case 3: return .twoHours
        case 6: return .sixHours
        case 12: return .twelveHours
        case 24: return .oneDay
        case 48: return .twoDays
        default: return .oneDay // Default to 1 day
        }
    }
}

// MARK: - Notification Preferences Manager

final class NotificationPreferencesManager {
    static let shared = NotificationPreferencesManager()
    private init() {}
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    // MARK: - Load Preferences
    
    func load(for userId: UUID) async throws -> NotificationPreferences {
        guard let client else {
            throw NSError(
                domain: "NotificationPrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        struct Row: Decodable {
            let user_id: UUID
            let event_reminder_hours_before: Int?
            let notify_event_updates: Bool?
            let notify_event_cancellations: Bool?
            let notify_rsvp_responses: Bool?
            let notify_event_reminders: Bool?
            let notify_new_group_members: Bool?
            let notify_group_member_left: Bool?
            let notify_group_ownership_transfer: Bool?
            let notify_group_renamed: Bool?
            let notify_group_deleted: Bool?
            let notify_subscription_changes: Bool?
            let notify_feature_limit_warnings: Bool?
            let notify_empty_week_nudges: Bool?
            let notify_group_quiet_pings: Bool?
            let notify_ai_assist_followups: Bool?
        }
        
        let rows: [Row] = try await client
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        
        if let row = rows.first {
            return NotificationPreferences(
                eventReminderHoursBefore: row.event_reminder_hours_before ?? 24,
                notifyEventUpdates: row.notify_event_updates ?? true,
                notifyEventCancellations: row.notify_event_cancellations ?? true,
                notifyRsvpResponses: row.notify_rsvp_responses ?? true,
                notifyEventReminders: row.notify_event_reminders ?? true,
                notifyNewGroupMembers: row.notify_new_group_members ?? true,
                notifyGroupMemberLeft: row.notify_group_member_left ?? true,
                notifyGroupOwnershipTransfer: row.notify_group_ownership_transfer ?? true,
                notifyGroupRenamed: row.notify_group_renamed ?? true,
                notifyGroupDeleted: row.notify_group_deleted ?? true,
                notifySubscriptionChanges: row.notify_subscription_changes ?? true,
                notifyFeatureLimitWarnings: row.notify_feature_limit_warnings ?? true,
                notifyEmptyWeekNudges: row.notify_empty_week_nudges ?? true,
                notifyGroupQuietPings: row.notify_group_quiet_pings ?? true,
                notifyAIAssistFollowups: row.notify_ai_assist_followups ?? true
            )
        }
        
        // No settings found, create defaults
        let defaults = NotificationPreferences.default
        try await save(defaults, for: userId)
        return defaults
    }
    
    // MARK: - Save Preferences
    
    func save(_ prefs: NotificationPreferences, for userId: UUID) async throws {
        guard let client else {
            throw NSError(
                domain: "NotificationPrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        struct UpsertRow: Encodable {
            let user_id: UUID
            let event_reminder_hours_before: Int
            let notify_event_updates: Bool
            let notify_event_cancellations: Bool
            let notify_rsvp_responses: Bool
            let notify_event_reminders: Bool
            let notify_new_group_members: Bool
            let notify_group_member_left: Bool
            let notify_group_ownership_transfer: Bool
            let notify_group_renamed: Bool
            let notify_group_deleted: Bool
            let notify_subscription_changes: Bool
            let notify_feature_limit_warnings: Bool
            let notify_empty_week_nudges: Bool
            let notify_group_quiet_pings: Bool
            let notify_ai_assist_followups: Bool
        }
        
        let row = UpsertRow(
            user_id: userId,
            event_reminder_hours_before: prefs.eventReminderHoursBefore,
            notify_event_updates: prefs.notifyEventUpdates,
            notify_event_cancellations: prefs.notifyEventCancellations,
            notify_rsvp_responses: prefs.notifyRsvpResponses,
            notify_event_reminders: prefs.notifyEventReminders,
            notify_new_group_members: prefs.notifyNewGroupMembers,
            notify_group_member_left: prefs.notifyGroupMemberLeft,
            notify_group_ownership_transfer: prefs.notifyGroupOwnershipTransfer,
            notify_group_renamed: prefs.notifyGroupRenamed,
            notify_group_deleted: prefs.notifyGroupDeleted,
            notify_subscription_changes: prefs.notifySubscriptionChanges,
            notify_feature_limit_warnings: prefs.notifyFeatureLimitWarnings,
            notify_empty_week_nudges: prefs.notifyEmptyWeekNudges,
            notify_group_quiet_pings: prefs.notifyGroupQuietPings,
            notify_ai_assist_followups: prefs.notifyAIAssistFollowups
        )
        
        _ = try await client
            .from("user_settings")
            .upsert(row, onConflict: "user_id")
            .execute()
    }
    
    // MARK: - Update Individual Preference
    
    func updateReminderTiming(_ timing: ReminderTiming, for userId: UUID) async throws {
        var prefs = try await load(for: userId)
        prefs.eventReminderHoursBefore = timing.hoursValue
        try await save(prefs, for: userId)
    }
    
    func updatePreference(keyPath: WritableKeyPath<NotificationPreferences, Bool>, value: Bool, for userId: UUID) async throws {
        var prefs = try await load(for: userId)
        prefs[keyPath: keyPath] = value
        try await save(prefs, for: userId)
    }
}

