import Foundation
import SwiftUI
import EventKit
import Combine
import Supabase

@MainActor
final class CalendarSyncManager: ObservableObject {
    struct SyncedEvent: Identifiable, Equatable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let calendarTitle: String
        let isAllDay: Bool
        let calendarColor: ColorComponents
        var userId: UUID?
        var userName: String?
    }

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var syncEnabled: Bool
    @Published private(set) var isRequestingAccess: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var upcomingEvents: [SyncedEvent] = []
    @Published private(set) var groupEvents: [CalendarEventWithUser] = []
    @Published var lastSyncError: String?

    private let eventStore = EKEventStore()
    private var storeChangeObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private static let syncPreferenceKey = "CalendarSyncEnabled"

    // Computed property to lazily access Supabase client
    private var client: SupabaseClient? {
        SupabaseManager.shared.client
    }

    init() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status

        let storedPreference = defaults.object(forKey: Self.syncPreferenceKey) as? Bool ?? false
        if status == .authorized {
            syncEnabled = storedPreference
        } else {
            syncEnabled = false
            if storedPreference {
                defaults.set(false, forKey: Self.syncPreferenceKey)
            }
        }

        if status == .authorized {
            observeEventStoreChanges()
            if syncEnabled {
                Task { await refreshEvents() }
            }
        }
    }

    deinit {
        if let observer = storeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func enableSyncFlow() async -> Bool {
        lastSyncError = nil
        if authorizationStatus == .authorized {
            if !syncEnabled {
                syncEnabled = true
                persistPreference()
            }
            observeEventStoreChanges()
            await refreshEvents()
            return true
        }

        guard authorizationStatus == .notDetermined else {
            // Permission previously denied or restricted.
            syncEnabled = false
            persistPreference()
            return false
        }

        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            let granted = try await requestEventKitAccess()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                syncEnabled = true
                persistPreference()
                observeEventStoreChanges()
                await refreshEvents()
            } else {
                syncEnabled = false
                persistPreference()
            }
            return granted
        } catch {
            syncEnabled = false
            persistPreference()
            lastSyncError = error.localizedDescription
            return false
        }
    }

    func disableSync() {
        syncEnabled = false
        persistPreference()
        upcomingEvents = []
    }

    func refreshEvents() async {
        guard syncEnabled, authorizationStatus == .authorized else {
            upcomingEvents = []
            return
        }
        isRefreshing = true
        lastSyncError = nil
        defer { isRefreshing = false }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }

        upcomingEvents = events.map { event in
            SyncedEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Busy",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                calendarTitle: event.calendar.title,
                isAllDay: event.isAllDay,
                calendarColor: colorComponents(from: event.calendar.cgColor)
            )
        }
    }

    func resetAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus != .authorized {
            syncEnabled = false
            persistPreference()
            upcomingEvents = []
        } else if syncEnabled {
            observeEventStoreChanges()
            Task { await refreshEvents() }
        }
    }

    private func requestEventKitAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    static let calendarDidChangeNotification = Notification.Name("calendarDidChangeNotification")

    private func observeEventStoreChanges() {
        guard storeChangeObserver == nil else { return }

        storeChangeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            
            // Post a custom notification instead of directly refreshing
            NotificationCenter.default.post(name: Self.calendarDidChangeNotification, object: nil)
        }
    }

    private func persistPreference() {
        defaults.set(syncEnabled, forKey: Self.syncPreferenceKey)
    }

    private func colorComponents(from cgColor: CGColor) -> ColorComponents {
        guard let space = cgColor.colorSpace, let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? space, intent: .defaultIntent, options: nil) else {
            return ColorComponents(red: 0.38, green: 0.55, blue: 0.93, alpha: 1.0)
        }
        let comps = converted.components ?? [0.38, 0.55, 0.93, 1.0]
        let red: Double
        let green: Double
        let blue: Double
        if comps.count >= 3 {
            red = Double(comps[0])
            green = Double(comps[1])
            blue = Double(comps[2])
        } else if comps.count == 2 {
            red = Double(comps[0])
            green = Double(comps[0])
            blue = Double(comps[0])
        } else {
            red = 0.38
            green = 0.55
            blue = 0.93
        }
        let alpha = comps.count >= 4 ? Double(comps[3]) : Double(converted.alpha)
        return ColorComponents(red: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: - Supabase Sync Methods

    /// Uploads local calendar events to Supabase for the given group
    func uploadEventsToDatabase(groupId: UUID, userId: UUID) async throws {
        guard let client = client else {
            throw NSError(domain: "CalendarSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not available"])
        }

        guard syncEnabled, authorizationStatus == .authorized else {
            throw NSError(domain: "CalendarSyncManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Calendar sync not enabled"])
        }

        // Fetch events from EventKit
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        // Convert to database format
        let dbEvents: [DBCalendarEventInsert] = events.compactMap { event in
            guard let eventId = event.eventIdentifier else { return nil }

            let colorComps = colorComponents(from: event.calendar.cgColor)
            let dbColorComps = ColorComponents(
                red: colorComps.red,
                green: colorComps.green,
                blue: colorComps.blue,
                alpha: colorComps.alpha
            )

            return DBCalendarEventInsert(
                user_id: userId,
                group_id: groupId,
                title: event.title ?? "Busy",
                start_date: event.startDate,
                end_date: event.endDate,
                is_all_day: event.isAllDay,
                location: event.location,
                is_public: true,
                original_event_id: eventId,
                calendar_name: event.calendar.title,
                calendar_color: dbColorComps,
                event_type: "personal"
            )
        }

        // Upload to Supabase (using upsert to handle duplicates)
        if !dbEvents.isEmpty {
            // For personal events, check if they already exist in ANY group for this user
            // to prevent duplicates across different groups
            var eventsToUpsert: [DBCalendarEventInsert] = []
            
            for event in dbEvents {
                if event.event_type == "personal", let originalId = event.original_event_id {
                    // Check if this personal event already exists for this user in any group
                    struct ExistingEvent: Decodable {
                        let id: UUID
                    }
                    let existing: [ExistingEvent] = try await client
                        .from("calendar_events")
                        .select("id")
                        .eq("user_id", value: event.user_id)
                        .eq("original_event_id", value: originalId)
                        .eq("event_type", value: "personal")
                        .limit(1)
                        .execute()
                        .value
                    
                    // Only include if it doesn't exist yet
                    if existing.isEmpty {
                        eventsToUpsert.append(event)
                    }
                } else {
                    // Group events or events without original_event_id: include them
                    eventsToUpsert.append(event)
                }
            }
            
            // Now upsert the filtered events
            if !eventsToUpsert.isEmpty {
                try await client
                    .from("calendar_events")
                    .upsert(eventsToUpsert, onConflict: "user_id,group_id,original_event_id")
                    .execute()
            }
        }
    }

    /// Fetches all calendar events for a group from Supabase
    /// Also fetches events from other groups the user is a member of (for cross-group visibility)
    func fetchGroupEvents(groupId: UUID) async throws {
        guard let client = client else {
            throw NSError(domain: "CalendarSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not available"])
        }

        // Fetch a much wider range: 30 days in the past and 1 year in the future
        // This ensures events show up regardless of when they're created
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

        // Query structure to join with users table
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

        // Get current user ID for filtering personal events
        let currentUserId = try await client.auth.session.user.id
        
        // Get all groups the user is a member of
        struct UserGroupRow: Decodable {
            let group_id: UUID
        }
        let userGroupRows: [UserGroupRow] = try await client
            .from("group_members")
            .select("group_id")
            .eq("user_id", value: currentUserId)
            .execute()
            .value
        let userGroupIds = userGroupRows.map { $0.group_id }
        
        // Get all members of the CURRENT group (for cross-group visibility)
        struct GroupMemberRow: Decodable {
            let user_id: UUID
        }
        let currentGroupMemberRows: [GroupMemberRow] = try await client
            .from("group_members")
            .select("user_id")
            .eq("group_id", value: groupId)
            .execute()
            .value
        let currentGroupMemberIds = currentGroupMemberRows.map { $0.user_id }
        
        // Get all groups that current group members are in (including groups the current user is NOT in)
        // This allows us to see events from other groups where our group members are busy
        struct MemberGroupRow: Decodable {
            let group_id: UUID
            let user_id: UUID
        }
        let memberGroupRows: [MemberGroupRow] = try await client
            .from("group_members")
            .select("group_id, user_id")
            .in("user_id", values: currentGroupMemberIds)
            .execute()
            .value
        
        let allMemberGroupIds = Array(Set(memberGroupRows.map { $0.group_id })) // Deduplicate
        
        // Get all user IDs from all groups the current user is in (for personal events)
        let allGroupMemberRows: [GroupMemberRow] = try await client
            .from("group_members")
            .select("user_id")
            .in("group_id", values: userGroupIds)
            .execute()
            .value
        let allGroupMemberIds = allGroupMemberRows.map { $0.user_id }
        
        // Query group events from ALL groups that current group members are in
        // This includes events from other groups where our members are busy
        var groupEventRows: [EventRow] = []
        
        if !allMemberGroupIds.isEmpty {
            groupEventRows = try await client
                .from("calendar_events")
                .select("*, users(id, display_name, avatar_url), event_categories(*)")
                .in("group_id", values: allMemberGroupIds)  // Fetch from all groups members are in
                .eq("event_type", value: "group")
                .lte("start_date", value: end)
                .gte("end_date", value: start)
                .order("start_date", ascending: true)
                .execute()
                .value
        }
        
        // ALSO: Query events where current group members are attendees (regardless of group membership)
        // This catches cases where RLS might prevent us from seeing group memberships
        struct AttendeeEventRow: Decodable {
            let event_id: UUID
            let user_id: UUID?
        }
        let allAttendeeRows: [AttendeeEventRow] = try await client
            .from("event_attendees")
            .select("event_id, user_id")
            .in("user_id", values: currentGroupMemberIds)
            .execute()
            .value
        
        // Filter to only user attendees (exclude guests where user_id is nil)
        let attendeeEventRows = allAttendeeRows.filter { $0.user_id != nil }
        let attendeeEventIds = Set(attendeeEventRows.map { $0.event_id })
        
        if !attendeeEventIds.isEmpty {
            // Fetch those events
            let attendeeEvents: [EventRow] = try await client
                .from("calendar_events")
                .select("*, users(id, display_name, avatar_url), event_categories(*)")
                .in("id", values: Array(attendeeEventIds))
                .eq("event_type", value: "group")
                .lte("start_date", value: end)
                .gte("end_date", value: start)
                .order("start_date", ascending: true)
                .execute()
                .value
            
            // Merge with existing events, avoiding duplicates
            let existingEventIds = Set(groupEventRows.map { $0.id })
            for event in attendeeEvents {
                if !existingEventIds.contains(event.id) {
                    groupEventRows.append(event)
                }
            }
        }
        
        
        // Query personal events from group members (can be in any group)
        let personalEventRows: [EventRow] = try await client
            .from("calendar_events")
            .select("*, users(id, display_name, avatar_url), event_categories(*)")
            .eq("event_type", value: "personal")
            .in("user_id", values: allGroupMemberIds)
            .lte("start_date", value: end)
            .gte("end_date", value: start)
            .order("start_date", ascending: true)
            .execute()
            .value
        
        // Combine both sets of events
        var allRows = groupEventRows + personalEventRows
        
        // Deduplicate personal events by original_event_id if they exist
        // Group personal events by original_event_id and keep only the oldest one per user
        var personalEventMap: [String: EventRow] = [:]
        for row in personalEventRows {
            if let originalId = row.original_event_id {
                if let existing = personalEventMap[originalId] {
                    // Keep the older event (lower ID typically means older in PostgreSQL)
                    if row.id.uuidString < existing.id.uuidString {
                        personalEventMap[originalId] = row
                    }
                } else {
                    personalEventMap[originalId] = row
                }
            }
        }
        
        // Rebuild allRows with deduplicated personal events
        allRows = groupEventRows + Array(personalEventMap.values)
        
        // Fetch attendees for all events to mark which have attendees
        let eventIds = allRows.map { $0.id }
        struct AttendeeRow: Decodable {
            let event_id: UUID
            let user_id: UUID?
            let users: UserInfo?
            
            struct UserInfo: Decodable {
                let display_name: String?
            }
        }
        
        let attendeeRows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("event_id, user_id, users(display_name)")
            .in("event_id", values: eventIds)
            .execute()
            .value
        
        let eventsWithAttendees = Set(attendeeRows.map { $0.event_id })
        
        // Build a map of event_id -> list of attending user IDs (for cross-group events)
        var eventAttendeesMap: [UUID: [UUID]] = [:]
        for attendee in attendeeRows {
            if let userId = attendee.user_id {
                eventAttendeesMap[attendee.event_id, default: []].append(userId)
            }
        }
        
        // Build a map of event_id -> list of attending member names (for display)
        var eventAttendeeNamesMap: [UUID: [String]] = [:]
        for attendee in attendeeRows {
            if let userId = attendee.user_id, currentGroupMemberIds.contains(userId) {
                let userName = attendee.users?.display_name ?? "Member"
                eventAttendeeNamesMap[attendee.event_id, default: []].append(userName)
            }
        }
        
        // Filter events: show all events from current group, and cross-group events where members are attending
        let filteredRows = allRows.filter { row in
            // Always show events from the current group
            if row.group_id == groupId {
                return true
            }
            // For cross-group events, only show if a current group member is attending
            if row.event_type == "group" {
                let attendingMemberIds = eventAttendeesMap[row.id] ?? []
                return attendingMemberIds.contains { currentGroupMemberIds.contains($0) }
            }
            // Show personal events (they're already filtered to group members)
            return true
        }
        
        // Convert to CalendarEventWithUser, marking which events have attendees
        // Since class is @MainActor, this assignment will automatically update on main thread
        let mappedEvents = filteredRows.map { row in
            let user = row.users.map { userInfo in
                DBUser(
                    id: userInfo.id,
                    display_name: userInfo.display_name,
                    avatar_url: userInfo.avatar_url,
                    created_at: nil,
                    updated_at: nil
                )
            }

            let category = row.event_categories.map { catInfo in
                EventCategory(
                    id: catInfo.id,
                    user_id: catInfo.user_id,
                    group_id: catInfo.group_id,
                    name: catInfo.name,
                    color: catInfo.color,
                    created_at: catInfo.created_at,
                    updated_at: catInfo.updated_at
                )
            }
            
            let hasAttendees = eventsWithAttendees.contains(row.id)
            
            // Determine if this is a cross-group event (from a different group than the current one)
            let isCrossGroup = row.group_id != groupId && row.event_type == "group"
            
            // For cross-group events, check if any current group members are attendees
            // Only show cross-group events if a member of the current group is attending
            let attendingMemberNames = eventAttendeeNamesMap[row.id] ?? []
            let shouldShowCrossGroup = isCrossGroup && !attendingMemberNames.isEmpty
            
            // For cross-group events, show as "BUSY" with user name(s) (hide details)
            let displayTitle: String
            if shouldShowCrossGroup {
                // Show "BUSY - [User Name]" for cross-group events
                // If multiple members are attending, show first one (or combine them)
                let userName = attendingMemberNames.first ?? "Member"
                if attendingMemberNames.count > 1 {
                    displayTitle = "BUSY - \(userName) +\(attendingMemberNames.count - 1)"
                } else {
                    displayTitle = "BUSY - \(userName)"
                }
            } else if isCrossGroup {
                // Cross-group event but no current group members are attending - don't show
                // This shouldn't happen due to our query, but handle it gracefully
                displayTitle = row.title
            } else {
                displayTitle = row.title
            }
            let displayLocation = shouldShowCrossGroup ? nil : row.location
            let displayNotes = shouldShowCrossGroup ? nil : row.notes
            
            return CalendarEventWithUser(
                id: row.id,
                user_id: row.user_id,
                group_id: row.group_id,
                title: displayTitle,
                start_date: row.start_date,
                end_date: row.end_date,
                is_all_day: row.is_all_day,
                location: displayLocation,
                is_public: row.is_public,
                original_event_id: row.original_event_id,
                calendar_name: row.calendar_name,
                calendar_color: row.calendar_color,
                created_at: row.created_at,
                updated_at: row.updated_at,
                synced_at: row.synced_at,
                notes: displayNotes,
                category_id: row.category_id,
                event_type: row.event_type,
                user: user,
                category: category,
                hasAttendees: hasAttendees
            )
        }
        
        // Update on main thread to trigger UI refresh
        await MainActor.run {
            groupEvents = mappedEvents
        }
    }

    /// Full sync: uploads local events and fetches all group events
    func syncWithGroup(groupId: UUID, userId: UUID) async {
        isRefreshing = true
        lastSyncError = nil
        defer { isRefreshing = false }

        do {
            // First refresh local events
            await refreshEvents()

            // Upload to database
            try await uploadEventsToDatabase(groupId: groupId, userId: userId)

            // Fetch all group events
            try await fetchGroupEvents(groupId: groupId)
            
            // Sync any group events the user is invited to but haven't been synced to Apple Calendar yet
            try await syncPendingGroupEventsToAppleCalendar(userId: userId)
        } catch {
            lastSyncError = error.localizedDescription
            print("Error syncing calendar with group: \(error)")
        }
    }
    
    /// Syncs group events the user is invited to but haven't been synced to Apple Calendar yet
    private func syncPendingGroupEventsToAppleCalendar(userId: UUID) async throws {
        guard let client = client else { return }
        
        // Find group events the user is invited to that don't have apple_calendar_event_id set
        struct PendingEventRow: Decodable {
            let event_id: UUID
            let attendee_id: UUID
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
        
        struct AttendeeRow: Decodable {
            let event_id: UUID
            let id: UUID
            let calendar_events: EventInfo?
            
            struct EventInfo: Decodable {
                let title: String
                let start_date: Date
                let end_date: Date
                let is_all_day: Bool
                let location: String?
                let notes: String?
                let category_id: UUID?
                let event_type: String
                let event_categories: CategoryInfo?
                
                struct CategoryInfo: Decodable {
                    let color: ColorComponents
                }
            }
        }
        
        let attendeeRows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("event_id, id, calendar_events(title, start_date, end_date, is_all_day, location, notes, category_id, event_type, event_categories(color))")
            .eq("user_id", value: userId)
            .is("apple_calendar_event_id", value: nil)
            .execute()
            .value
        
        // Filter to only group events and map to PendingEventRow
        let groupPendingEvents = attendeeRows.compactMap { row -> PendingEventRow? in
            guard let event = row.calendar_events, event.event_type == "group" else { return nil }
            return PendingEventRow(
                event_id: row.event_id,
                attendee_id: row.id,
                title: event.title,
                start_date: event.start_date,
                end_date: event.end_date,
                is_all_day: event.is_all_day,
                location: event.location,
                notes: event.notes,
                category_id: event.category_id,
                event_categories: event.event_categories.map { cat in
                    PendingEventRow.CategoryInfo(color: cat.color)
                }
            )
        }
        
        // Sync each pending event to Apple Calendar
        for pendingEvent in groupPendingEvents {
            do {
                let categoryColor = pendingEvent.event_categories?.color
                let appleEventId = try await EventKitEventManager.shared.createEvent(
                    title: pendingEvent.title,
                    start: pendingEvent.start_date,
                    end: pendingEvent.end_date,
                    isAllDay: pendingEvent.is_all_day,
                    location: pendingEvent.location,
                    notes: pendingEvent.notes,
                    categoryColor: categoryColor
                )
                
                // Store the Apple Calendar event ID
                struct UpdateAttendee: Encodable {
                    let apple_calendar_event_id: String
                }
                let update = UpdateAttendee(apple_calendar_event_id: appleEventId)
                try await client
                    .from("event_attendees")
                    .update(update)
                    .eq("id", value: pendingEvent.attendee_id)
                    .execute()
            } catch {
                // Log error but continue with other events
                print("[CalendarSyncManager] Failed to sync pending event to Apple Calendar: \(error)")
            }
        }
    }

    /// Clear cached group events (useful when leaving a group)
    func clearGroupEvents() {
        groupEvents = []
    }

    /// Get user color for consistent color coding
    func userColor(for userId: UUID) -> Color {
        let colors: [Color] = [
            Color(red: 0.98, green: 0.29, blue: 0.55), // Pink
            Color(red: 0.58, green: 0.41, blue: 0.87), // Purple
            Color(red: 0.27, green: 0.63, blue: 0.98), // Blue
            Color(red: 0.20, green: 0.78, blue: 0.74), // Teal
            Color(red: 0.59, green: 0.85, blue: 0.34), // Green
            Color(red: 1.00, green: 0.78, blue: 0.16), // Yellow
            Color(red: 1.00, green: 0.45, blue: 0.34), // Coral
            Color(red: 0.68, green: 0.47, blue: 0.86), // Lavender
            Color(red: 0.20, green: 0.80, blue: 0.55), // Emerald
            Color(red: 0.95, green: 0.61, blue: 0.07)  // Orange
        ]

        // Use UUID hash to consistently assign colors
        let hash = abs(userId.hashValue)
        return colors[hash % colors.count]
    }
}
