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
    let categoryId: UUID?
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
            let category_id: UUID?
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
            original_event_id: input.originalEventId,
            category_id: input.categoryId
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

    // Load attendees (include user profile name if available)
    func loadAttendees(eventId: UUID) async throws -> [(userId: UUID?, displayName: String, status: String)] {
        struct Row: Decodable {
            let user_id: UUID?
            let display_name: String?
            let status: String
            let users: UserInfo?
            struct UserInfo: Decodable { let display_name: String? }
        }
        let rows: [Row] = try await client
            .from("event_attendees")
            .select("user_id, display_name, status, users(display_name)")
            .eq("event_id", value: eventId)
            .execute()
            .value

        return rows.map { r in
            let explicit = r.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameFromUser = r.users?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (explicit?.isEmpty == false ? explicit : nil)
                ?? (nameFromUser?.isEmpty == false ? nameFromUser : nil)
                ?? (r.user_id != nil ? "Member" : "Guest")
            return (r.user_id, resolved ?? "Guest", r.status)
        }
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
            let category_id: UUID?
        }
        let row = UpdateRow(title: input.title, start_date: input.start, end_date: input.end, is_all_day: input.isAllDay, location: input.location, notes: input.notes, original_event_id: input.originalEventId, category_id: input.categoryId)
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
        let statusLower = status.lowercased()

        struct IdRow: Decodable { let id: UUID }
        struct UpdateStatusOnly: Encodable { let status: String }
        struct UpdateStatusAndUser: Encodable { let status: String; let user_id: UUID }

        // Fetch user's display name (needed for both validation and guest row claiming)
        struct UserRow: Decodable { let display_name: String? }
        let me: [UserRow] = try await client
            .from("users")
            .select("display_name")
            .eq("id", value: currentUserId)
            .limit(1)
            .execute()
            .value
        
        let myName = me.first?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Check if user is an attendee (defense in depth - UI should prevent this, but verify server-side)
        struct AttendeeCheck: Decodable { let id: UUID }
        let existingAttendee: [AttendeeCheck] = try await client
            .from("event_attendees")
            .select("id")
            .eq("event_id", value: eventId)
            .eq("user_id", value: currentUserId)
            .limit(1)
            .execute()
            .value
        
        // Also check for guest row with matching name
        let hasGuestRow: Bool
        if !myName.isEmpty {
            let guestRows: [AttendeeCheck] = try await client
                .from("event_attendees")
                .select("id")
                .eq("event_id", value: eventId)
                .is("user_id", value: nil)
                .ilike("display_name", value: myName)
                .limit(1)
                .execute()
                .value
            hasGuestRow = !guestRows.isEmpty
        } else {
            hasGuestRow = false
        }
        
        // If user is not an attendee (neither as user_id nor as guest), return early
        if existingAttendee.isEmpty && !hasGuestRow {
            return
        }

        // 1) Try updating an existing attendee row for this user
        let updatedForUser: [IdRow] = try await client
            .from("event_attendees")
            .update(UpdateStatusOnly(status: statusLower))
            .eq("event_id", value: eventId)
            .eq("user_id", value: currentUserId)
            .select("id")
            .execute()
            .value

        // If we updated at least one row, we are done
        if !updatedForUser.isEmpty { return }

        // 2) Otherwise, try to claim a guest row by matching the user's display name
        if !myName.isEmpty {
            let updatedGuest: [IdRow] = try await client
                .from("event_attendees")
                .update(UpdateStatusAndUser(status: statusLower, user_id: currentUserId))
                .eq("event_id", value: eventId)
                .is("user_id", value: nil)
                .ilike("display_name", value: myName)
                .select("id")
                .execute()
                .value

            if !updatedGuest.isEmpty { return }
        }

        // 3) If nothing was updated, do nothing (avoid insert/delete due to RLS). The UI will stay on the optimistic value.
    }

    // Delete an event (allowed by RLS only for the event owner)
    // Also deletes from EventKit if original_event_id is provided
    func deleteEvent(eventId: UUID, currentUserId: UUID, originalEventId: String?) async throws {
        // Delete from EventKit first if we have the identifier
        if let ekId = originalEventId {
            try? await EventKitEventManager.shared.deleteEvent(identifier: ekId)
        }
        
        // RLS on calendar_events ensures only the owner can delete
        _ = try await client
            .from("calendar_events")
            .delete()
            .eq("id", value: eventId)
            .execute()
    }

    // Invoke Edge Function to send push notifications to attendees
    private func notifyAttendees(eventId: UUID) async throws {
        struct Payload: Encodable { let event_id: UUID }
        let payload = Payload(event_id: eventId)
        _ = try await client.functions
            .invoke("notify-event", options: FunctionInvokeOptions(body: payload))
    }
    
    // MARK: - Category Management
    
    // Fetch categories available to the user (user's own + group categories from groups they're members of)
    func fetchCategories(userId: UUID, groupId: UUID?) async throws -> [EventCategory] {
        // RLS policy allows viewing: user's own categories + group categories from groups they're members of
        // Query user's own categories first
        var userCategories: [EventCategory] = try await client
            .from("event_categories")
            .select("*")
            .eq("user_id", value: userId)
            .order("name", ascending: true)
            .execute()
            .value
        
        // If groupId is provided, also fetch group categories (RLS will filter appropriately)
        if let groupId = groupId {
            let groupCategories: [EventCategory] = try await client
                .from("event_categories")
                .select("*")
                .eq("group_id", value: groupId)
                .order("name", ascending: true)
                .execute()
                .value
            
            // Combine and deduplicate by ID
            var combined = userCategories
            let userCategoryIds = Set(userCategories.map { $0.id })
            combined.append(contentsOf: groupCategories.filter { !userCategoryIds.contains($0.id) })
            return combined.sorted { $0.name < $1.name }
        }
        
        return userCategories
    }
    
    // Create a new category
    func createCategory(input: EventCategoryInsert, currentUserId: UUID) async throws -> EventCategory {
        let insertData = EventCategoryInsert(
            user_id: currentUserId,
            group_id: input.group_id,
            name: input.name,
            color: input.color
        )
        
        let category: [EventCategory] = try await client
            .from("event_categories")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        guard let created = category.first else {
            throw NSError(domain: "CalendarEventService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create category"])
        }
        
        return created
    }
    
    // Update an existing category (only user's own categories)
    func updateCategory(categoryId: UUID, update: EventCategoryUpdate, currentUserId: UUID) async throws -> EventCategory {
        let updated: [EventCategory] = try await client
            .from("event_categories")
            .update(update)
            .eq("id", value: categoryId)
            .eq("user_id", value: currentUserId)
            .select()
            .execute()
            .value
        
        guard let category = updated.first else {
            throw NSError(domain: "CalendarEventService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Category not found or update failed"])
        }
        
        return category
    }
    
    // Delete a category (only user's own categories)
    func deleteCategory(categoryId: UUID, currentUserId: UUID) async throws {
        _ = try await client
            .from("event_categories")
            .delete()
            .eq("id", value: categoryId)
            .eq("user_id", value: currentUserId)
            .execute()
    }
    
    // Fetch a single category by ID (for fallback when user doesn't have the category)
    func fetchCategoryById(categoryId: UUID) async throws -> EventCategory? {
        let categories: [EventCategory] = try await client
            .from("event_categories")
            .select("*")
            .eq("id", value: categoryId)
            .execute()
            .value
        
        return categories.first
    }
}


