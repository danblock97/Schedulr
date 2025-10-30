import Foundation
import Supabase

struct CalendarPreferences: Codable, Equatable {
    var hideHolidays: Bool
    var dedupAllDay: Bool
}

final class CalendarPreferencesManager {
    static let shared = CalendarPreferencesManager()
    private init() {}

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    func load(for userId: UUID) async throws -> CalendarPreferences {
        guard let client else { throw NSError(domain: "Prefs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]) }
        struct Row: Decodable { let user_id: UUID; let hide_holidays: Bool; let dedup_all_day: Bool }
        let rows: [Row] = try await client.from("user_settings").select().eq("user_id", value: userId).limit(1).execute().value
        if let r = rows.first { return CalendarPreferences(hideHolidays: r.hide_holidays, dedupAllDay: r.dedup_all_day) }
        // Insert defaults if not found
        let defaults = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
        try await save(defaults, for: userId)
        return defaults
    }

    func save(_ prefs: CalendarPreferences, for userId: UUID) async throws {
        guard let client else { throw NSError(domain: "Prefs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]) }
        struct UpsertRow: Encodable { let user_id: UUID; let hide_holidays: Bool; let dedup_all_day: Bool }
        let row = UpsertRow(user_id: userId, hide_holidays: prefs.hideHolidays, dedup_all_day: prefs.dedupAllDay)
        _ = try await client.from("user_settings").upsert(row, onConflict: "user_id").execute()
    }
}


