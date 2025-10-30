import Foundation
import Supabase

struct NewEventInput {
    let groupId: UUID
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let attendeeUserIds: [UUID]
    let guestNames: [String]
    let originalEventId: String?
}

final class CalendarEventService {
    static let shared = CalendarEventService()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    // Create event owned by current user, then add attendees
    func createEvent(input: NewEventInput, currentUserId: UUID) async throws -> UUID {
        struct InsertRow: Encodable {
            let user_id: UUID
            let group_id: UUID
            let title: String
            let start_date: Date
            let end_date: Date
            let is_all_day: Bool
            let location: String?
            let is_public: Bool
            let calendar_name: String?
            let calendar_color: ColorComponents?
            let notes: String?
            let original_event_id: String?
        }

        let row = InsertRow(
            user_id: currentUserId,
            group_id: input.groupId,
            title: input.title,
            start_date: input.start,
            end_date: input.end,
            is_all_day: input.isAllDay,
            location: input.location,
            is_public: true,
            calendar_name: "Schedulr",
            calendar_color: nil,
            notes: input.notes,
            original_event_id: input.originalEventId
        )

        struct Returned: Decodable { let id: UUID }
        let created: [Returned] = try await client
            .from("calendar_events")
            .insert(row)
            .select("id")
            .execute()
            .value

        guard let eventId = created.first?.id else {
            throw NSError(domain: "CalendarEventService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create event"])
        }

        // Notify attendees via push (async, don't fail if it errors)
        Task {
            try? await notifyAttendees(eventId: eventId)
        }

        // Build attendee rows
        struct AttRow: Encodable { let event_id: UUID; let user_id: UUID?; let display_name: String; let status: String }
        var attendees: [AttRow] = []
        attendees.append(contentsOf: input.attendeeUserIds.map { AttRow(event_id: eventId, user_id: $0, display_name: "", status: "invited") })
        attendees.append(contentsOf: input.guestNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { name in
            AttRow(event_id: eventId, user_id: nil, display_name: name.trimmingCharacters(in: .whitespacesAndNewlines), status: "invited")
        })
        if !attendees.isEmpty {
            _ = try await client.from("event_attendees").insert(attendees).execute()
        }

        return eventId
    }

    // Load attendees
    func loadAttendees(eventId: UUID) async throws -> [(userId: UUID?, displayName: String, status: String)] {
        struct Row: Decodable { let user_id: UUID?; let display_name: String?; let status: String }
        let rows: [Row] = try await client
            .from("event_attendees")
            .select("user_id, display_name, status")
            .eq("event_id", value: eventId)
            .execute()
            .value
        return rows.map { ($0.user_id, $0.display_name ?? ($0.user_id?.uuidString ?? "Guest"), $0.status) }
    }

    // Update event and replace attendees set
    func updateEvent(eventId: UUID, input: NewEventInput, currentUserId: UUID) async throws {
        struct UpdateRow: Encodable {
            let title: String
            let start_date: Date
            let end_date: Date
            let is_all_day: Bool
            let location: String?
            let notes: String?
            let original_event_id: String?
        }
        let row = UpdateRow(title: input.title, start_date: input.start, end_date: input.end, is_all_day: input.isAllDay, location: input.location, notes: input.notes, original_event_id: input.originalEventId)
        _ = try await client.from("calendar_events").update(row).eq("id", value: eventId).execute()

        // Replace attendees: delete then insert
        _ = try await client.from("event_attendees").delete().eq("event_id", value: eventId).execute()
        struct AttRow: Encodable { let event_id: UUID; let user_id: UUID?; let display_name: String; let status: String }
        var attendees: [AttRow] = []
        attendees.append(contentsOf: input.attendeeUserIds.map { AttRow(event_id: eventId, user_id: $0, display_name: "", status: "invited") })
        attendees.append(contentsOf: input.guestNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { name in
            AttRow(event_id: eventId, user_id: nil, display_name: name.trimmingCharacters(in: .whitespacesAndNewlines), status: "invited")
        })
        if !attendees.isEmpty {
            _ = try await client.from("event_attendees").insert(attendees).execute()
        }
    }

    // Update current user's attendee status for an event
    func updateMyStatus(eventId: UUID, status: String, currentUserId: UUID) async throws {
        // If a row exists for me, update; otherwise insert
        struct UpsertRow: Encodable { let event_id: UUID; let user_id: UUID?; let display_name: String; let status: String }
        let row = UpsertRow(event_id: eventId, user_id: currentUserId, display_name: "", status: status)
        _ = try await client
            .from("event_attendees")
            .upsert(row, onConflict: "event_id,user_id")
            .execute()
    }

    // Invoke Edge Function to send push notifications to attendees
    private func notifyAttendees(eventId: UUID) async throws {
        struct Payload: Encodable { let event_id: UUID }
        let payload = Payload(event_id: eventId)
        _ = try await client.functions
            .invoke("notify-event", options: FunctionInvokeOptions(body: payload))
    }
}


