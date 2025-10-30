import Foundation

struct DBUser: Codable, Identifiable, Equatable {
    let id: UUID
    var display_name: String?
    var avatar_url: String?
    var created_at: Date?
    var updated_at: Date?
}

struct DBUserUpdate: Encodable {
    var display_name: String?
    var avatar_url: String?
}

struct DBGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var invite_slug: String
    var created_by: UUID
    var created_at: Date?
}

struct DBGroupInsert: Encodable {
    var name: String
    var created_by: UUID
}

struct DBGroupMember: Codable, Equatable {
    var group_id: UUID
    var user_id: UUID
    var role: String?
    var joined_at: Date?
}

// MARK: - Calendar Events

struct ColorComponents: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct DBCalendarEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let user_id: UUID
    let group_id: UUID
    let title: String
    let start_date: Date
    let end_date: Date
    let is_all_day: Bool
    let location: String?
    let is_public: Bool
    let original_event_id: String?
    let calendar_name: String?
    let calendar_color: ColorComponents?
    let created_at: Date?
    let updated_at: Date?
    let synced_at: Date?
}

struct DBCalendarEventInsert: Encodable {
    var user_id: UUID
    var group_id: UUID
    var title: String
    var start_date: Date
    var end_date: Date
    var is_all_day: Bool
    var location: String?
    var is_public: Bool
    var original_event_id: String?
    var calendar_name: String?
    var calendar_color: ColorComponents?
}

struct CalendarEventWithUser: Codable, Identifiable, Equatable {
    let id: UUID
    let user_id: UUID
    let group_id: UUID
    let title: String
    let start_date: Date
    let end_date: Date
    let is_all_day: Bool
    let location: String?
    let is_public: Bool
    let original_event_id: String?
    let calendar_name: String?
    let calendar_color: ColorComponents?
    let created_at: Date?
    let updated_at: Date?
    let synced_at: Date?
    let user: DBUser?

    struct UserInfo: Codable, Equatable {
        let id: UUID
        let display_name: String?
        let avatar_url: String?
    }
}
