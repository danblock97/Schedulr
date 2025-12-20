import Foundation
import Supabase
import EventKit

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
    let eventType: String
}

final class CalendarEventService {
    static let shared = CalendarEventService()
    private init() {}

    private var client: SupabaseClient { SupabaseManager.shared.client }

    // Create event owned by current user, then add attendees
    func createEvent(input: NewEventInput, currentUserId: UUID) async throws -> UUID {
        // Validate that end date is not before start date
        if input.end < input.start {
            throw NSError(domain: "CalendarEventService", code: -2, userInfo: [NSLocalizedDescriptionKey: "End date cannot be before start date"])
        }
        
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
            let event_type: String
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
            category_id: input.categoryId,
            event_type: input.eventType
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

        // Build attendee rows - ALWAYS include the creator so they get reminders
        struct AttRow: Encodable { let event_id: UUID; let user_id: UUID?; let display_name: String; let status: String }
        var attendeesLists: [AttRow] = []
        
        // Add creator
        attendeesLists.append(AttRow(event_id: eventId, user_id: currentUserId, display_name: "", status: "going"))
        
        // Add other attendees
        let attendeeIdsWithoutCreator = input.attendeeUserIds.filter { $0 != currentUserId }
        attendeesLists.append(contentsOf: attendeeIdsWithoutCreator.map { AttRow(event_id: eventId, user_id: $0, display_name: "", status: "invited") })
        
        // Add guests
        attendeesLists.append(contentsOf: input.guestNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { name in
            AttRow(event_id: eventId, user_id: nil, display_name: name.trimmingCharacters(in: .whitespacesAndNewlines), status: "invited")
        })
        
        if !attendeesLists.isEmpty {
            _ = try await client.from("event_attendees").insert(attendeesLists).execute()
        }

        // Notify attendees via push (async, don't fail if it errors)
        // Pass creator ID to exclude them from notifications
        Task {
            try? await notifyAttendees(eventId: eventId, creatorUserId: currentUserId)
        }

        // Sync group events to Apple Calendar for all invited users (including the creator)
        if input.eventType == "group" {
            // Sync immediately (not in background Task) so it happens after attendees are inserted
            do {
                try await syncGroupEventToAppleCalendar(eventId: eventId, input: input, creatorUserId: currentUserId)
            } catch {
                // Log error but don't throw - allow event creation to succeed even if sync fails
                // The sync will be retried when the user refreshes their calendar
                print("[CalendarEventService] Failed to sync group event \(eventId) to Apple Calendar: \(error.localizedDescription)")
            }
        }

        return eventId
    }

    // Fetch a single event by ID
    func fetchEventById(eventId: UUID) async throws -> CalendarEventWithUser? {
        struct EventRow: Decodable {
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
            let users: UserInfo?
            let event_categories: CategoryInfo?
            
            struct UserInfo: Decodable {
                let id: UUID
                let display_name: String?
                let avatar_url: String?
            }
            
            struct CategoryInfo: Decodable {
                let id: UUID
                let user_id: UUID
                let group_id: UUID?
                let name: String
                let color: ColorComponents
                let created_at: Date?
                let updated_at: Date?
            }
        }
        
        let eventRow: EventRow? = try? await client
            .from("calendar_events")
            .select("*, users(id, display_name, avatar_url), event_categories(*)")
            .eq("id", value: eventId)
            .single()
            .execute()
            .value
        
        guard let row = eventRow else { return nil }
        
        return CalendarEventWithUser(
            id: row.id,
            user_id: row.user_id,
            group_id: row.group_id,
            title: row.title,
            start_date: row.start_date,
            end_date: row.end_date,
            is_all_day: row.is_all_day,
            location: row.location,
            is_public: row.is_public,
            original_event_id: row.original_event_id,
            calendar_name: row.calendar_name,
            calendar_color: row.calendar_color,
            created_at: row.created_at,
            updated_at: row.updated_at,
            synced_at: row.synced_at,
            notes: row.notes,
            category_id: row.category_id,
            event_type: row.event_type,
            user: row.users.map { DBUser(
                id: $0.id,
                display_name: $0.display_name,
                avatar_url: $0.avatar_url,
                created_at: nil,
                updated_at: nil,
                subscription_tier: nil,
                subscription_status: nil,
                revenuecat_customer_id: nil,
                subscription_updated_at: nil,
                downgrade_grace_period_ends: nil
            )},
            category: row.event_categories.map { EventCategory(
                id: $0.id,
                user_id: $0.user_id,
                group_id: $0.group_id,
                name: $0.name,
                color: $0.color,
                created_at: $0.created_at,
                updated_at: $0.updated_at
            )},
            hasAttendees: nil,
            isCurrentUserAttendee: nil
        )
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
        // Validate that end date is not before start date
        if input.end < input.start {
            throw NSError(domain: "CalendarEventService", code: -2, userInfo: [NSLocalizedDescriptionKey: "End date cannot be before start date"])
        }
        
        struct UpdateRow: Encodable {
            let title: String
            let start_date: Date
            let end_date: Date
            let is_all_day: Bool
            let location: String?
            let notes: String?
            let original_event_id: String?
            let category_id: UUID?
            let event_type: String
        }
        let row = UpdateRow(title: input.title, start_date: input.start, end_date: input.end, is_all_day: input.isAllDay, location: input.location, notes: input.notes, original_event_id: input.originalEventId, category_id: input.categoryId, event_type: input.eventType)
        _ = try await client.from("calendar_events").update(row).eq("id", value: eventId).execute()

        // Fetch existing attendees to preserve apple_calendar_event_id
        struct ExistingAttendee: Decodable {
            let user_id: UUID?
            let display_name: String?
            let apple_calendar_event_id: String?
        }
        let existingAttendees: [ExistingAttendee] = try await client
            .from("event_attendees")
            .select("user_id, display_name, apple_calendar_event_id")
            .eq("event_id", value: eventId)
            .execute()
            .value
            
        // Create a map for quick lookup: UserId -> AppleCalendarEventId
        var userIdToAppleId: [UUID: String] = [:]
        // And for guests: DisplayName -> AppleCalendarEventId
        var guestNameToAppleId: [String: String] = [:]
        
        for attendee in existingAttendees {
            if let uid = attendee.user_id, let appleId = attendee.apple_calendar_event_id {
                userIdToAppleId[uid] = appleId
            } else if let name = attendee.display_name, let appleId = attendee.apple_calendar_event_id {
                guestNameToAppleId[name] = appleId
            }
        }

        // Replace attendees: delete then insert
        _ = try await client.from("event_attendees").delete().eq("event_id", value: eventId).execute()
        
        struct AttRow: Encodable { 
            let event_id: UUID
            let user_id: UUID?
            let display_name: String
            let status: String
            let apple_calendar_event_id: String?
        }
        var newAttendees: [AttRow] = []
        
        // Always include creator
        newAttendees.append(AttRow(
            event_id: eventId,
            user_id: currentUserId,
            display_name: "",
            status: "going",
            apple_calendar_event_id: userIdToAppleId[currentUserId]
        ))
        
        // Add others
        let otherUserIds = input.attendeeUserIds.filter { $0 != currentUserId }
        newAttendees.append(contentsOf: otherUserIds.map { userId in
            AttRow(
                event_id: eventId, 
                user_id: userId, 
                display_name: "", 
                status: "invited",
                apple_calendar_event_id: userIdToAppleId[userId]
            )
        })
        
        newAttendees.append(contentsOf: input.guestNames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { name in
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return AttRow(
                event_id: eventId, 
                user_id: nil, 
                display_name: cleanName, 
                status: "invited",
                apple_calendar_event_id: guestNameToAppleId[cleanName]
            )
        })
        
        if !newAttendees.isEmpty {
            _ = try await client.from("event_attendees").insert(newAttendees).execute()
        }
        
        // Sync group events to Apple Calendar for all invited users (including the creator)
        if input.eventType == "group" {
            // Sync immediately (not in background Task) so it happens after attendees are inserted
            try? await syncGroupEventToAppleCalendar(eventId: eventId, input: input, creatorUserId: currentUserId)
        }
        
        // Notify attendees about the event update (async, don't fail if it errors)
        NotificationService.shared.notifyEventUpdate(eventId: eventId, updaterUserId: currentUserId)
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

        // If we updated at least one row, notify and return
        if !updatedForUser.isEmpty {
            // Notify event creator about the RSVP response (async, don't fail if it errors)
            NotificationService.shared.notifyRSVPResponse(eventId: eventId, responderUserId: currentUserId, status: statusLower)
            return
        }

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

            if !updatedGuest.isEmpty {
                // Notify event creator about the RSVP response (async, don't fail if it errors)
                NotificationService.shared.notifyRSVPResponse(eventId: eventId, responderUserId: currentUserId, status: statusLower)
                return
            }
        }

        // 3) If nothing was updated, do nothing (avoid insert/delete due to RLS). The UI will stay on the optimistic value.
    }

    // Delete an event (allowed by RLS only for the event owner)
    // Also deletes from EventKit if original_event_id is provided
    func deleteEvent(eventId: UUID, currentUserId: UUID, originalEventId: String?) async throws {
        // For group events, delete from Apple Calendar for all invited users
        struct AttendeeRow: Decodable {
            let user_id: UUID?
            let apple_calendar_event_id: String?
        }
        let attendeeRows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("user_id, apple_calendar_event_id")
            .eq("event_id", value: eventId)
            .execute()
            .value
        
        // Notify attendees about cancellation BEFORE deleting (async, don't fail if it errors)
        let attendeeUserIds = attendeeRows.compactMap { $0.user_id }
        NotificationService.shared.notifyEventCancellation(eventId: eventId, creatorUserId: currentUserId, attendeeUserIds: attendeeUserIds)
        
        // Delete Apple Calendar events for all attendees
        for attendee in attendeeRows {
            if let appleEventId = attendee.apple_calendar_event_id {
                try? await EventKitEventManager.shared.deleteEvent(identifier: appleEventId)
            }
        }
        
        // Delete from EventKit if original_event_id is provided (for personal events)
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
    private func notifyAttendees(eventId: UUID, creatorUserId: UUID) async throws {
        struct Payload: Encodable { 
            let event_id: UUID
            let creator_user_id: UUID
        }
        let payload = Payload(event_id: eventId, creator_user_id: creatorUserId)
        _ = try await client.functions
            .invoke("notify-event", options: FunctionInvokeOptions(body: payload))
    }
    
    // MARK: - Group Event Apple Calendar Sync
    
    /// Syncs a group event to Apple Calendar for all invited users
    /// Each user gets their own copy of the event in their Apple Calendar
    private func syncGroupEventToAppleCalendar(eventId: UUID, input: NewEventInput, creatorUserId: UUID) async throws {
        // Fetch event details including category
        struct EventRow: Decodable {
            let id: UUID
            let title: String
            let start_date: Date
            let end_date: Date
            let is_all_day: Bool
            let location: String?
            let notes: String?
            let category_id: UUID?
            let event_categories: CategoryInfo?
            
            struct CategoryInfo: Decodable {
                let color: ColorComponents
            }
        }
        
        let event: EventRow = try await client
            .from("calendar_events")
            .select("id, title, start_date, end_date, is_all_day, location, notes, category_id, event_categories(color)")
            .eq("id", value: eventId)
            .single()
            .execute()
            .value
        
        // Get category color if available
        let categoryColor = event.event_categories?.color
        
        // Get all user attendees (exclude guests)
        struct AttendeeRow: Decodable {
            let id: UUID
            let user_id: UUID?
            let apple_calendar_event_id: String?
        }
        
        let allAttendeeRows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("id, user_id, apple_calendar_event_id")
            .eq("event_id", value: eventId)
            .execute()
            .value
        
        // Filter to only user attendees (exclude guests where user_id is nil)
        let attendeeRows = allAttendeeRows.filter { $0.user_id != nil }
        
        // Get current user ID
        let currentUserId = try await client.auth.session.user.id
        
        // Create a set of all user IDs that should have this event (attendees + creator)
        var userIdsToSync = Set(attendeeRows.compactMap { $0.user_id })
        userIdsToSync.insert(creatorUserId) // Always include the creator
        
        // Sync to Apple Calendar for the current user only (if they're an attendee or creator)
        // Other users' devices will sync when they open the app
        guard userIdsToSync.contains(currentUserId) else {
            return
        }
        
        // Check if current user already has an attendee record
        let currentUserAttendee = attendeeRows.first { $0.user_id == currentUserId }
        
        // Check calendar permissions first
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        guard authStatus == .authorized else {
            throw NSError(domain: "CalendarEventService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Calendar access not authorized. Please grant calendar permissions in Settings."])
        }
        
        do {
            let appleEventId: String
            
            if let existingAppleEventId = currentUserAttendee?.apple_calendar_event_id {
                // Update existing Apple Calendar event
                appleEventId = existingAppleEventId
                try await EventKitEventManager.shared.updateEvent(
                    identifier: existingAppleEventId,
                    title: event.title,
                    start: event.start_date,
                    end: event.end_date,
                    isAllDay: event.is_all_day,
                    location: event.location,
                    notes: event.notes,
                    categoryColor: categoryColor
                )
            } else {
                // Check if event already exists in Apple Calendar before creating
                let eventStore = EKEventStore()
                let start = event.start_date
                let end = event.end_date
                let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
                let existingEvents = eventStore.events(matching: predicate)
                
                // Look for matching event
                let matchingEvent = existingEvents.first { ekEvent in
                    guard let eventTitle = ekEvent.title else { return false }
                    let titleMatch = eventTitle.trimmingCharacters(in: .whitespaces) == event.title.trimmingCharacters(in: .whitespaces)
                    let startMatch = abs(ekEvent.startDate.timeIntervalSince(event.start_date)) < 1.0
                    let endMatch = abs(ekEvent.endDate.timeIntervalSince(event.end_date)) < 1.0
                    let isAllDayMatch = ekEvent.isAllDay == event.is_all_day
                    return titleMatch && startMatch && endMatch && isAllDayMatch
                }
                
                if let existingEvent = matchingEvent, let existingEventId = existingEvent.eventIdentifier {
                    // Event already exists, use its ID
                    appleEventId = existingEventId
                    print("[CalendarEventService] Found existing Apple Calendar event for \(event.title), using ID: \(existingEventId)")
                } else {
                // Create new Apple Calendar event
                appleEventId = try await EventKitEventManager.shared.createEvent(
                    title: event.title,
                    start: event.start_date,
                    end: event.end_date,
                    isAllDay: event.is_all_day,
                    location: event.location,
                    notes: event.notes,
                    categoryColor: categoryColor
                )
                    print("[CalendarEventService] Created new Apple Calendar event for \(event.title), ID: \(appleEventId)")
                }
                
                // Store the Apple Calendar event ID
                // If user has an attendee record, update it; otherwise create one
                if let attendeeId = currentUserAttendee?.id {
                    // Update existing record (which we now guarantee exists)
                    struct UpdateAttendee: Encodable {
                        let apple_calendar_event_id: String
                    }
                    let update = UpdateAttendee(apple_calendar_event_id: appleEventId)
                    try await client
                        .from("event_attendees")
                        .update(update)
                        .eq("id", value: attendeeId)
                        .execute()
                } else {
                    // Fallback (should not be needed now as we insert creator in createEvent/updateEvent)
                    struct AttRow: Encodable {
                        let event_id: UUID
                        let user_id: UUID
                        let display_name: String
                        let status: String
                        let apple_calendar_event_id: String
                    }
                    let attendeeRow = AttRow(
                        event_id: eventId,
                        user_id: currentUserId,
                        display_name: "",
                        status: "going",
                        apple_calendar_event_id: appleEventId
                    )
                    try await client.from("event_attendees").insert(attendeeRow).execute()
                }
            }
        } catch {
            // Log error but re-throw so caller can handle it
            print("[CalendarEventService] Failed to sync event to Apple Calendar: \(error.localizedDescription)")
            throw error
        }
            
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
            
            // Combine with group categories first, then personal categories
            // Deduplicate by ID, prioritize group categories
            var combined: [EventCategory] = []
            let userCategoryIds = Set(userCategories.map { $0.id })
            
            // Add group categories first
            combined.append(contentsOf: groupCategories)
            
            // Add personal categories that aren't duplicates
            combined.append(contentsOf: userCategories.filter { !combined.map { $0.id }.contains($0.id) })
            
            return combined
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


