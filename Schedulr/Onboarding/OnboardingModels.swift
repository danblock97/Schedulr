import Foundation

struct DBUser: Codable, Identifiable, Equatable {
    let id: UUID
    var display_name: String?
    var avatar_url: String?
    var created_at: Date?
    var updated_at: Date?
    var subscription_tier: String?
    var subscription_status: String?
    var revenuecat_customer_id: String?
    var subscription_updated_at: Date?
    var downgrade_grace_period_ends: Date?
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

// MARK: - Recurrence Models

enum RecurrenceFrequency: String, Codable, CaseIterable, Equatable {
    case daily
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var pluralUnit: String {
        switch self {
        case .daily: return "days"
        case .weekly: return "weeks"
        case .monthly: return "months"
        case .yearly: return "years"
        }
    }
}

enum RecurrenceEndType: String, Codable, CaseIterable, Equatable {
    case never
    case afterCount
    case onDate

    var displayName: String {
        switch self {
        case .never: return "Never"
        case .afterCount: return "After"
        case .onDate: return "On Date"
        }
    }
}

struct RecurrenceRule: Codable, Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int
    var daysOfWeek: [Int]?
    var dayOfMonth: Int?
    var weekOfMonth: Int?
    var monthOfYear: Int?
    var count: Int?
    var endDate: Date?

    // Support both camelCase and snake_case for backward compatibility
    private enum CodingKeys: String, CodingKey {
        case frequency
        case interval
        case daysOfWeek
        case daysOfWeekSnake = "days_of_week"
        case dayOfMonth
        case dayOfMonthSnake = "day_of_month"
        case weekOfMonth
        case weekOfMonthSnake = "week_of_month"
        case monthOfYear
        case monthOfYearSnake = "month_of_year"
        case count
        case endDate
        case endDateSnake = "end_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(RecurrenceFrequency.self, forKey: .frequency)
        interval = try container.decode(Int.self, forKey: .interval)
        // Try camelCase first, then snake_case
        daysOfWeek = try container.decodeIfPresent([Int].self, forKey: .daysOfWeek)
            ?? container.decodeIfPresent([Int].self, forKey: .daysOfWeekSnake)
        dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
            ?? container.decodeIfPresent(Int.self, forKey: .dayOfMonthSnake)
        weekOfMonth = try container.decodeIfPresent(Int.self, forKey: .weekOfMonth)
            ?? container.decodeIfPresent(Int.self, forKey: .weekOfMonthSnake)
        monthOfYear = try container.decodeIfPresent(Int.self, forKey: .monthOfYear)
            ?? container.decodeIfPresent(Int.self, forKey: .monthOfYearSnake)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
            ?? container.decodeIfPresent(Date.self, forKey: .endDateSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encodeIfPresent(daysOfWeek, forKey: .daysOfWeek)
        try container.encodeIfPresent(dayOfMonth, forKey: .dayOfMonth)
        try container.encodeIfPresent(weekOfMonth, forKey: .weekOfMonth)
        try container.encodeIfPresent(monthOfYear, forKey: .monthOfYear)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(endDate, forKey: .endDate)
    }

    init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        daysOfWeek: [Int]? = nil,
        dayOfMonth: Int? = nil,
        weekOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        count: Int? = nil,
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.weekOfMonth = weekOfMonth
        self.monthOfYear = monthOfYear
        self.count = count
        self.endDate = endDate
    }

    // MARK: - Convenience Initializers

    static func daily(interval: Int = 1, count: Int? = nil, endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(frequency: .daily, interval: interval, count: count, endDate: endDate)
    }

    static func weekly(interval: Int = 1, daysOfWeek: [Int], count: Int? = nil, endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(frequency: .weekly, interval: interval, daysOfWeek: daysOfWeek, count: count, endDate: endDate)
    }

    static func monthly(interval: Int = 1, dayOfMonth: Int, count: Int? = nil, endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(frequency: .monthly, interval: interval, dayOfMonth: dayOfMonth, count: count, endDate: endDate)
    }

    static func yearly(interval: Int = 1, monthOfYear: Int, dayOfMonth: Int, count: Int? = nil, endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(frequency: .yearly, interval: interval, dayOfMonth: dayOfMonth, monthOfYear: monthOfYear, count: count, endDate: endDate)
    }
}

// MARK: - Event Categories

struct EventCategory: Codable, Identifiable, Equatable {
    let id: UUID
    let user_id: UUID
    let group_id: UUID?
    let name: String
    let color: ColorComponents
    let emoji: String?
    let cover_image_url: String?
    let created_at: Date?
    let updated_at: Date?
}

struct EventCategoryInsert: Encodable {
    var user_id: UUID
    var group_id: UUID?
    var name: String
    var color: ColorComponents
    var emoji: String?
    var cover_image_url: String?
}

struct EventCategoryUpdate: Encodable {
    var name: String?
    var color: ColorComponents?
    var group_id: UUID?
    var emoji: String?
    var cover_image_url: String?
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
    let notes: String?
    let category_id: UUID?
    let event_type: String
    // Recurrence fields
    let recurrence_rule: RecurrenceRule?
    let recurrence_end_date: Date?
    let parent_event_id: UUID?
    let is_recurrence_exception: Bool
    let original_occurrence_date: Date?

    init(
        id: UUID,
        user_id: UUID,
        group_id: UUID,
        title: String,
        start_date: Date,
        end_date: Date,
        is_all_day: Bool,
        location: String?,
        is_public: Bool,
        original_event_id: String?,
        calendar_name: String?,
        calendar_color: ColorComponents?,
        created_at: Date?,
        updated_at: Date?,
        synced_at: Date?,
        notes: String?,
        category_id: UUID?,
        event_type: String,
        recurrence_rule: RecurrenceRule? = nil,
        recurrence_end_date: Date? = nil,
        parent_event_id: UUID? = nil,
        is_recurrence_exception: Bool = false,
        original_occurrence_date: Date? = nil
    ) {
        self.id = id
        self.user_id = user_id
        self.group_id = group_id
        self.title = title
        self.start_date = start_date
        self.end_date = end_date
        self.is_all_day = is_all_day
        self.location = location
        self.is_public = is_public
        self.original_event_id = original_event_id
        self.calendar_name = calendar_name
        self.calendar_color = calendar_color
        self.created_at = created_at
        self.updated_at = updated_at
        self.synced_at = synced_at
        self.notes = notes
        self.category_id = category_id
        self.event_type = event_type
        self.recurrence_rule = recurrence_rule
        self.recurrence_end_date = recurrence_end_date
        self.parent_event_id = parent_event_id
        self.is_recurrence_exception = is_recurrence_exception
        self.original_occurrence_date = original_occurrence_date
    }

    // Custom decoder to handle missing recurrence fields from older data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        user_id = try container.decode(UUID.self, forKey: .user_id)
        group_id = try container.decode(UUID.self, forKey: .group_id)
        title = try container.decode(String.self, forKey: .title)
        start_date = try container.decode(Date.self, forKey: .start_date)
        end_date = try container.decode(Date.self, forKey: .end_date)
        is_all_day = try container.decode(Bool.self, forKey: .is_all_day)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        is_public = try container.decode(Bool.self, forKey: .is_public)
        original_event_id = try container.decodeIfPresent(String.self, forKey: .original_event_id)
        calendar_name = try container.decodeIfPresent(String.self, forKey: .calendar_name)
        calendar_color = try container.decodeIfPresent(ColorComponents.self, forKey: .calendar_color)
        created_at = try container.decodeIfPresent(Date.self, forKey: .created_at)
        updated_at = try container.decodeIfPresent(Date.self, forKey: .updated_at)
        synced_at = try container.decodeIfPresent(Date.self, forKey: .synced_at)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        category_id = try container.decodeIfPresent(UUID.self, forKey: .category_id)
        event_type = try container.decode(String.self, forKey: .event_type)
        // Recurrence fields with defaults for backward compatibility
        recurrence_rule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence_rule)
        recurrence_end_date = try container.decodeIfPresent(Date.self, forKey: .recurrence_end_date)
        parent_event_id = try container.decodeIfPresent(UUID.self, forKey: .parent_event_id)
        is_recurrence_exception = try container.decodeIfPresent(Bool.self, forKey: .is_recurrence_exception) ?? false
        original_occurrence_date = try container.decodeIfPresent(Date.self, forKey: .original_occurrence_date)
    }

    enum CodingKeys: String, CodingKey {
        case id, user_id, group_id, title, start_date, end_date, is_all_day
        case location, is_public, original_event_id, calendar_name, calendar_color
        case created_at, updated_at, synced_at, notes, category_id, event_type
        case recurrence_rule, recurrence_end_date, parent_event_id
        case is_recurrence_exception, original_occurrence_date
    }
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
    var notes: String?
    var category_id: UUID?
    var event_type: String
    // Recurrence fields
    var recurrence_rule: RecurrenceRule?
    var recurrence_end_date: Date?
    var parent_event_id: UUID?
    var is_recurrence_exception: Bool?
    var original_occurrence_date: Date?
}

struct CalendarEventWithUser: Codable, Identifiable, Equatable, Hashable {
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
    let notes: String?
    let category_id: UUID?
    let event_type: String
    let user: DBUser?
    let category: EventCategory?
    let hasAttendees: Bool?
    let isCurrentUserAttendee: Bool?
    // Recurrence fields
    let recurrenceRule: RecurrenceRule?
    let recurrenceEndDate: Date?
    let parentEventId: UUID?
    let isRecurrenceException: Bool
    let originalOccurrenceDate: Date?
    // Rain check fields
    let eventStatus: String?
    let rainCheckedAt: Date?
    let rainCheckRequestedBy: UUID?
    let rainCheckReason: String?
    let originalEventIdForReschedule: UUID?

    struct UserInfo: Codable, Equatable {
        let id: UUID
        let display_name: String?
        let avatar_url: String?
    }

    // Hashable conformance - use id since it's unique
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Computed property to get the effective color (category color takes precedence)
    var effectiveColor: ColorComponents? {
        category?.color ?? calendar_color
    }

    // Computed property to check if this is a cross-group event (from a different group than current)
    // This will be set by CalendarSyncManager when fetching events
    var isCrossGroupEvent: Bool {
        // This will be set externally by CalendarSyncManager
        // For now, return false as default - will be set when events are fetched
        false
    }

    // Computed property to check if this event is recurring
    var isRecurring: Bool {
        recurrenceRule != nil || parentEventId != nil
    }

    // Custom coding keys to map snake_case from DB to camelCase
    enum CodingKeys: String, CodingKey {
        case id, user_id, group_id, title, start_date, end_date, is_all_day
        case location, is_public, original_event_id, calendar_name, calendar_color
        case created_at, updated_at, synced_at, notes, category_id, event_type
        case user, category, hasAttendees, isCurrentUserAttendee
        case recurrenceRule = "recurrence_rule"
        case recurrenceEndDate = "recurrence_end_date"
        case parentEventId = "parent_event_id"
        case isRecurrenceException = "is_recurrence_exception"
        case originalOccurrenceDate = "original_occurrence_date"
        case eventStatus = "event_status"
        case rainCheckedAt = "rain_checked_at"
        case rainCheckRequestedBy = "rain_check_requested_by"
        case rainCheckReason = "rain_check_reason"
        case originalEventIdForReschedule = "original_event_id_for_reschedule"
    }

    // Custom decoder to handle missing recurrence fields from older data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        user_id = try container.decode(UUID.self, forKey: .user_id)
        group_id = try container.decode(UUID.self, forKey: .group_id)
        title = try container.decode(String.self, forKey: .title)
        start_date = try container.decode(Date.self, forKey: .start_date)
        end_date = try container.decode(Date.self, forKey: .end_date)
        is_all_day = try container.decode(Bool.self, forKey: .is_all_day)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        is_public = try container.decode(Bool.self, forKey: .is_public)
        original_event_id = try container.decodeIfPresent(String.self, forKey: .original_event_id)
        calendar_name = try container.decodeIfPresent(String.self, forKey: .calendar_name)
        calendar_color = try container.decodeIfPresent(ColorComponents.self, forKey: .calendar_color)
        created_at = try container.decodeIfPresent(Date.self, forKey: .created_at)
        updated_at = try container.decodeIfPresent(Date.self, forKey: .updated_at)
        synced_at = try container.decodeIfPresent(Date.self, forKey: .synced_at)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        category_id = try container.decodeIfPresent(UUID.self, forKey: .category_id)
        event_type = try container.decode(String.self, forKey: .event_type)
        user = try container.decodeIfPresent(DBUser.self, forKey: .user)
        category = try container.decodeIfPresent(EventCategory.self, forKey: .category)
        hasAttendees = try container.decodeIfPresent(Bool.self, forKey: .hasAttendees)
        isCurrentUserAttendee = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUserAttendee)
        // Recurrence fields with defaults for backward compatibility
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
        recurrenceEndDate = try container.decodeIfPresent(Date.self, forKey: .recurrenceEndDate)
        parentEventId = try container.decodeIfPresent(UUID.self, forKey: .parentEventId)
        isRecurrenceException = try container.decodeIfPresent(Bool.self, forKey: .isRecurrenceException) ?? false
        originalOccurrenceDate = try container.decodeIfPresent(Date.self, forKey: .originalOccurrenceDate)
        // Rain check fields with defaults for backward compatibility
        eventStatus = try container.decodeIfPresent(String.self, forKey: .eventStatus)
        rainCheckedAt = try container.decodeIfPresent(Date.self, forKey: .rainCheckedAt)
        rainCheckRequestedBy = try container.decodeIfPresent(UUID.self, forKey: .rainCheckRequestedBy)
        rainCheckReason = try container.decodeIfPresent(String.self, forKey: .rainCheckReason)
        originalEventIdForReschedule = try container.decodeIfPresent(UUID.self, forKey: .originalEventIdForReschedule)
    }

    init(
        id: UUID,
        user_id: UUID,
        group_id: UUID,
        title: String,
        start_date: Date,
        end_date: Date,
        is_all_day: Bool,
        location: String?,
        is_public: Bool,
        original_event_id: String?,
        calendar_name: String?,
        calendar_color: ColorComponents?,
        created_at: Date?,
        updated_at: Date?,
        synced_at: Date?,
        notes: String?,
        category_id: UUID?,
        event_type: String,
        user: DBUser?,
        category: EventCategory?,
        hasAttendees: Bool?,
        isCurrentUserAttendee: Bool?,
        recurrenceRule: RecurrenceRule? = nil,
        recurrenceEndDate: Date? = nil,
        parentEventId: UUID? = nil,
        isRecurrenceException: Bool = false,
        originalOccurrenceDate: Date? = nil,
        eventStatus: String? = nil,
        rainCheckedAt: Date? = nil,
        rainCheckRequestedBy: UUID? = nil,
        rainCheckReason: String? = nil,
        originalEventIdForReschedule: UUID? = nil
    ) {
        self.id = id
        self.user_id = user_id
        self.group_id = group_id
        self.title = title
        self.start_date = start_date
        self.end_date = end_date
        self.is_all_day = is_all_day
        self.location = location
        self.is_public = is_public
        self.original_event_id = original_event_id
        self.calendar_name = calendar_name
        self.calendar_color = calendar_color
        self.created_at = created_at
        self.updated_at = updated_at
        self.synced_at = synced_at
        self.notes = notes
        self.category_id = category_id
        self.event_type = event_type
        self.user = user
        self.category = category
        self.hasAttendees = hasAttendees
        self.isCurrentUserAttendee = isCurrentUserAttendee
        self.recurrenceRule = recurrenceRule
        self.recurrenceEndDate = recurrenceEndDate
        self.parentEventId = parentEventId
        self.isRecurrenceException = isRecurrenceException
        self.originalOccurrenceDate = originalOccurrenceDate
        self.eventStatus = eventStatus
        self.rainCheckedAt = rainCheckedAt
        self.rainCheckRequestedBy = rainCheckRequestedBy
        self.rainCheckReason = rainCheckReason
        self.originalEventIdForReschedule = originalEventIdForReschedule
    }
}
