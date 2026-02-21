import Foundation
import SwiftUI
import EventKit
import Combine
import Supabase
import WidgetKit

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
    private static let syncedGroupEventsKey = "SyncedGroupEventsMapping"

    // Track if syncPendingGroupEventsToAppleCalendar is currently running to prevent concurrent execution
    private var isSyncingPendingEvents: Bool = false

    // MARK: - Local Storage for Synced Group Events

    /// Stores the mapping of event_id -> apple_calendar_event_id locally
    /// This allows cleanup even after attendee records are cascade-deleted
    private func storeSyncedGroupEvent(eventId: UUID, appleCalendarEventId: String) {
        var mapping = getSyncedGroupEventsMapping()
        mapping[eventId.uuidString] = appleCalendarEventId
        defaults.set(mapping, forKey: Self.syncedGroupEventsKey)
    }

    /// Gets the mapping of event_id -> apple_calendar_event_id from local storage
    private func getSyncedGroupEventsMapping() -> [String: String] {
        return defaults.dictionary(forKey: Self.syncedGroupEventsKey) as? [String: String] ?? [:]
    }

    /// Removes an event from the local synced events mapping
    private func removeSyncedGroupEvent(eventId: UUID) {
        var mapping = getSyncedGroupEventsMapping()
        mapping.removeValue(forKey: eventId.uuidString)
        defaults.set(mapping, forKey: Self.syncedGroupEventsKey)
    }

    /// Removes an Apple Calendar event ID from the local synced events mapping
    private func removeSyncedGroupEventByAppleId(_ appleCalendarEventId: String) {
        var mapping = getSyncedGroupEventsMapping()
        if let key = mapping.first(where: { $0.value == appleCalendarEventId })?.key {
            mapping.removeValue(forKey: key)
            defaults.set(mapping, forKey: Self.syncedGroupEventsKey)
        }
    }

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

        // Fetch all apple_calendar_event_id values from event_attendees for this user
        // These represent group events that were synced FROM Supabase TO Apple Calendar
        // We should NOT upload them back to avoid duplicates
        struct AttendeeAppleEventId: Decodable {
            let apple_calendar_event_id: String?
        }
        let attendeeRows: [AttendeeAppleEventId] = try await client
            .from("event_attendees")
            .select("apple_calendar_event_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        
        // Create a Set of Apple Calendar event IDs that are already synced group events
        // Filter out nil values since we only care about events that have been synced
        let syncedGroupEventIds = Set(attendeeRows.compactMap { $0.apple_calendar_event_id })

        // Filter out events that were synced FROM Supabase (group events)
        // Only upload personal events that aren't already synced group events
        let eventsToUpload = events.filter { event in
            guard let eventId = event.eventIdentifier else { return false }
            // Skip if this event is a group event that was synced FROM Supabase
            return !syncedGroupEventIds.contains(eventId)
        }

        // Convert to database format
        let dbEvents: [DBCalendarEventInsert] = eventsToUpload.compactMap { event in
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
            // Also check if this event matches an existing group event (to prevent uploading group events as personal)
            var eventsToUpsert: [DBCalendarEventInsert] = []
            
            // Get all group event IDs that this user is an attendee of
            struct GroupEventAttendee: Decodable {
                let event_id: UUID
            }
            let groupEventAttendeeRows: [GroupEventAttendee] = try await client
                .from("event_attendees")
                .select("event_id")
                .eq("user_id", value: userId)
                .execute()
                .value
            let userGroupEventIds = Set(groupEventAttendeeRows.map { $0.event_id })
            
            // Fetch details of these group events to compare
            struct GroupEventDetails: Decodable {
                let id: UUID
                let title: String
                let start_date: Date
                let end_date: Date
            }
            let groupEventDetails: [GroupEventDetails] = try await client
                .from("calendar_events")
                .select("id, title, start_date, end_date")
                .in("id", values: Array(userGroupEventIds))
                .eq("event_type", value: "group")
                .execute()
                .value
            
            // Create a map for quick lookup
            let groupEventMap = Dictionary(uniqueKeysWithValues: groupEventDetails.map { ($0.id, $0) })
            
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
                    
                    // Check if this event matches an existing group event the user is attending
                    // Compare by title, start_date, and end_date (within 1 second tolerance for exact matches)
                    let matchesGroupEvent = groupEventDetails.contains { groupEvent in
                        let titleMatch = groupEvent.title.trimmingCharacters(in: .whitespaces) == event.title.trimmingCharacters(in: .whitespaces)
                        let startMatch = abs(groupEvent.start_date.timeIntervalSince(event.start_date)) < 1.0
                        let endMatch = abs(groupEvent.end_date.timeIntervalSince(event.end_date)) < 1.0
                        return titleMatch && startMatch && endMatch
                    }
                    
                    // Only include if it doesn't exist yet and doesn't match a group event
                    if existing.isEmpty && !matchesGroupEvent {
                        eventsToUpsert.append(event)
                    }
                } else {
                    // Group events or events without original_event_id: include them
                    eventsToUpsert.append(event)
                }
            }
            
            // Deduplicate events by (user_id, group_id, original_event_id) before upserting
            // This prevents "ON CONFLICT DO UPDATE command cannot affect row a second time" error
            var seenKeys = Set<String>()
            let deduplicatedEvents = eventsToUpsert.filter { event in
                let key = "\(event.user_id)|\(event.group_id)|\(event.original_event_id ?? "")"
                if seenKeys.contains(key) {
                    return false
                }
                seenKeys.insert(key)
                return true
            }

            // Now upsert the filtered events
            if !deduplicatedEvents.isEmpty {
                try await client
                    .from("calendar_events")
                    .upsert(deduplicatedEvents, onConflict: "user_id,group_id,original_event_id")
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
            // Recurrence fields
            let recurrence_rule: RecurrenceRule?
            let recurrence_end_date: Date?
            let parent_event_id: UUID?
            let is_recurrence_exception: Bool?
            let original_occurrence_date: Date?
            // Rain check fields
            let event_status: String?
            let rain_checked_at: Date?
            let rain_check_requested_by: UUID?
            let rain_check_reason: String?
            let original_event_id_for_reschedule: UUID?

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
                let emoji: String?
                let cover_image_url: String?
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
            let fetchedGroupEvents: [EventRow] = try await client
                .from("calendar_events")
                .select("*, users(id, display_name, avatar_url), event_categories(*)")
                .in("group_id", values: allMemberGroupIds)  // Fetch from all groups members are in
                .eq("event_type", value: "group")
                .or("event_status.is.null,event_status.eq.active")  // Exclude rain-checked and rescheduled events
                .lte("start_date", value: end)
                .gte("end_date", value: start)
                .order("start_date", ascending: true)
                .execute()
                .value
            
            // Deduplicate immediately by event ID to prevent duplicates
            var groupEventMap: [UUID: EventRow] = [:]
            for event in fetchedGroupEvents {
                if groupEventMap[event.id] == nil {
                    groupEventMap[event.id] = event
                }
            }
            groupEventRows = Array(groupEventMap.values)
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
            let fetchedAttendeeEvents: [EventRow] = try await client
                .from("calendar_events")
                .select("*, users(id, display_name, avatar_url), event_categories(*)")
                .in("id", values: Array(attendeeEventIds))
                .eq("event_type", value: "group")
                .or("event_status.is.null,event_status.eq.active")  // Exclude rain-checked and rescheduled events
                .lte("start_date", value: end)
                .gte("end_date", value: start)
                .order("start_date", ascending: true)
                .execute()
                .value
            
            // Deduplicate attendee events by ID first
            var attendeeEventMap: [UUID: EventRow] = [:]
            for event in fetchedAttendeeEvents {
                if attendeeEventMap[event.id] == nil {
                    attendeeEventMap[event.id] = event
                }
            }
            let attendeeEvents = Array(attendeeEventMap.values)
            
            // Merge with existing events, avoiding duplicates by ID
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
            .or("event_status.is.null,event_status.eq.active")  // Exclude rain-checked and rescheduled events
            .in("user_id", values: allGroupMemberIds)
            .lte("start_date", value: end)
            .gte("end_date", value: start)
            .order("start_date", ascending: true)
            .execute()
            .value
        
        // Deduplicate group events by event id to ensure each group event appears only once
        // regardless of how many attendees or groups it's associated with
        var groupEventMap: [UUID: EventRow] = [:]
        for row in groupEventRows {
            // If event already exists, keep the existing one (they should be identical)
            if groupEventMap[row.id] == nil {
                groupEventMap[row.id] = row
            }
        }
        let deduplicatedGroupEvents = Array(groupEventMap.values)
        
        // Deduplicate personal events by original_event_id if they exist
        // Group personal events by original_event_id and keep only the oldest one per user
        var personalEventMap: [String: EventRow] = [:]
        var personalEventsWithoutOriginalId: [EventRow] = []
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
            } else {
                // Include personal events without original_event_id
                personalEventsWithoutOriginalId.append(row)
            }
        }
        
        // Combine deduplicated events
        var allRows = deduplicatedGroupEvents + Array(personalEventMap.values) + personalEventsWithoutOriginalId
        
        // Final deduplication: ensure each event appears only once by event id
        // This handles cases where the same event might appear in multiple queries
        var finalEventMap: [UUID: EventRow] = [:]
        for row in allRows {
            // If event already exists, keep the existing one (they should be identical)
            // Prefer group events over personal events if there's a conflict
            if let existing = finalEventMap[row.id] {
                // If existing is personal and new is group, replace it
                if existing.event_type == "personal" && row.event_type == "group" {
                    finalEventMap[row.id] = row
                }
                // Otherwise keep the existing one
            } else {
                finalEventMap[row.id] = row
            }
        }
        allRows = Array(finalEventMap.values)
        
        // Additional deduplication by title + start_date + end_date to catch cases where
        // the same event appears with different IDs (e.g., group event synced to Apple Calendar
        // and then uploaded back as a personal event)
        // Prefer group events over personal events when there's a match
        var deduplicatedByContent: [EventRow] = []
        var seenContentSignatures: Set<String> = []
        
        // Sort so group events come first (they'll be preferred)
        let sortedRows = allRows.sorted { $0.event_type == "group" && $1.event_type != "group" }
        
        for row in sortedRows {
            // Create a signature: title|startTimestamp|endTimestamp|isAllDay
            let signature = "\(row.title)|\(row.start_date.timeIntervalSince1970)|\(row.end_date.timeIntervalSince1970)|\(row.is_all_day)"
            
            if seenContentSignatures.contains(signature) {
                // This event matches another by content - skip it
                // Group events are already in the set (since we sorted them first)
                // so personal events that match group events will be skipped
                continue
            }
            
            seenContentSignatures.insert(signature)
            deduplicatedByContent.append(row)
        }
        
        allRows = deduplicatedByContent
        
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
                    emoji: catInfo.emoji,
                    cover_image_url: catInfo.cover_image_url,
                    created_at: catInfo.created_at,
                    updated_at: catInfo.updated_at
                )
            }
            
            let hasAttendees = eventsWithAttendees.contains(row.id)
            let isCurrentUserAttendee = eventAttendeesMap[row.id]?.contains(currentUserId) ?? false
            
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
                hasAttendees: hasAttendees,
                isCurrentUserAttendee: isCurrentUserAttendee,
                recurrenceRule: row.recurrence_rule,
                recurrenceEndDate: row.recurrence_end_date,
                parentEventId: row.parent_event_id,
                isRecurrenceException: row.is_recurrence_exception ?? false,
                originalOccurrenceDate: row.original_occurrence_date,
                eventStatus: row.event_status,
                rainCheckedAt: row.rain_checked_at,
                rainCheckRequestedBy: row.rain_check_requested_by,
                rainCheckReason: row.rain_check_reason,
                originalEventIdForReschedule: row.original_event_id_for_reschedule
            )
        }
        
        // Expand recurring events within the date range
        let dateRange = start...end
        var expandedEvents: [CalendarEventWithUser] = []

        // Separate recurring parents, exceptions, and regular events
        var recurringParents: [CalendarEventWithUser] = []
        var exceptions: [UUID: [CalendarEventWithUser]] = [:] // parent_event_id -> exceptions
        var regularEvents: [CalendarEventWithUser] = []

        print("[CalendarSyncManager] Processing \(mappedEvents.count) events for date range")

        for event in mappedEvents {
            if event.isRecurrenceException, let parentId = event.parentEventId {
                // This is an exception (modified or cancelled occurrence)
                print("[CalendarSyncManager] Found exception: \(event.title), parentId: \(parentId), is_public: \(event.is_public), originalOccurrenceDate: \(String(describing: event.originalOccurrenceDate))")
                exceptions[parentId, default: []].append(event)
            } else if event.recurrenceRule != nil && event.parentEventId == nil {
                // This is a recurring parent event
                print("[CalendarSyncManager] Found recurring parent: \(event.title), id: \(event.id)")
                recurringParents.append(event)
            } else if event.parentEventId == nil {
                // Regular non-recurring event
                regularEvents.append(event)
            }
            // Skip orphaned exceptions (parentEventId != nil but no recurrence rule and not an exception)
        }

        print("[CalendarSyncManager] Recurring parents: \(recurringParents.count), Exceptions: \(exceptions.values.flatMap { $0 }.count), Regular: \(regularEvents.count)")

        // Expand recurring events
        for parent in recurringParents {
            let parentExceptions = exceptions[parent.id] ?? []
            print("[CalendarSyncManager] Expanding parent \(parent.title) with \(parentExceptions.count) exceptions")
            let expanded = RecurrenceService.shared.expandRecurringEvent(
                parent,
                inRange: dateRange,
                exceptions: parentExceptions
            )
            print("[CalendarSyncManager] Expanded to \(expanded.count) occurrences")
            expandedEvents.append(contentsOf: expanded)

            // Add modified exceptions (not cancelled ones) to the list
            for exception in parentExceptions {
                if exception.is_public { // is_public = false means cancelled
                    if let occDate = exception.originalOccurrenceDate, dateRange.contains(occDate) {
                        expandedEvents.append(exception)
                    }
                }
            }
        }

        // Add regular events
        expandedEvents.append(contentsOf: regularEvents)

        // Update on main thread to trigger UI refresh
        await MainActor.run {
            // Sort events by start date to ensure chronological order
            let sortedEvents = expandedEvents.sorted { lhs, rhs in
                if lhs.start_date == rhs.start_date {
                    return lhs.end_date < rhs.end_date
                }
                return lhs.start_date < rhs.start_date
            }

            groupEvents = sortedEvents

            // Save to shared container for Widget (Embedded logic to avoid file issues)
            saveEventsToWidget(sortedEvents)
        }
    }
    
    // MARK: - Widget Data Sharing (Embedded)
    private func saveEventsToWidget(_ events: [CalendarEventWithUser]) {
        let appGroupId = "group.uk.co.schedulr.Schedulr"
        let dataKey = "upcoming_widget_events"
        
        // Fetch current user ID to load preferences
        // Since we are in an async context (Task in refreshEvents), we can try to get it
        // However, this function is synchronous. We'll launch a Task.
        Task {
            guard let userId = try? await client?.auth.session.user.id else { return }
            
            // Load preferences
            let prefs = try? await CalendarPreferencesManager.shared.load(for: userId)
            let hideHolidays = prefs?.hideHolidays ?? true
            
            // Filter events
            var filteredEvents = events
            
            if hideHolidays {
                filteredEvents = filteredEvents.filter { ev in
                    let title = ev.title.lowercased()
                    let calendarName = (ev.calendar_name ?? "").lowercased()
                    let isHoliday = title.contains("holiday") || calendarName.contains("holiday")
                    let isBirthday = title.contains("birthday") || calendarName.contains("birthday")
                    return !(isHoliday || isBirthday)
                }
            }
            
            // Filter to only show events relevant to the current user:
            // - Group events where the user is invited/attending (or they created it)
            // - The user's own personal events
            filteredEvents = filteredEvents.filter { event in
                if event.event_type == "group" {
                    let isInvitedOrOwner = event.isCurrentUserAttendee == true || event.user_id == userId
                    return isInvitedOrOwner
                } else if event.event_type == "personal" {
                    // Only show the current user's own personal events
                    return event.user_id == userId
                }
                return false
            }

            // Keep only active/upcoming events in the next 30 days, sorted chronologically.
            // This avoids truncating to old historical events before widget-side filtering runs.
            let now = Date()
            let lookaheadEnd = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? Date.distantFuture
            filteredEvents = filteredEvents
                .filter { event in
                    event.end_date > now && event.start_date < lookaheadEnd
                }
                .sorted { lhs, rhs in
                    if lhs.start_date == rhs.start_date {
                        return lhs.end_date < rhs.end_date
                    }
                    return lhs.start_date < rhs.start_date
                }
            
            struct SharedEvent: Codable {
                let id: String
                let title: String
                let startDate: Date
                let endDate: Date
                let location: String?
                let colorData: Data
                let calendarTitle: String
                let isAllDay: Bool
            }
            
            let sharedEvents = filteredEvents.map { event in
                let uiColor: UIColor
                if let cc = event.calendar_color {
                    uiColor = UIColor(red: cc.red, green: cc.green, blue: cc.blue, alpha: cc.alpha)
                } else {
                    uiColor = .systemBlue
                }
                let colorData = (try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)) ?? Data()
                
                return SharedEvent(
                    id: event.id.uuidString,
                    title: event.title,
                    startDate: event.start_date,
                    endDate: event.end_date,
                    location: event.location,
                    colorData: colorData,
                    calendarTitle: event.calendar_name ?? "Schedulr",
                    isAllDay: event.is_all_day
                )
            }
            
            if let userDefaults = UserDefaults(suiteName: appGroupId) {
                if let encoded = try? JSONEncoder().encode(sharedEvents) {
                    userDefaults.set(encoded, forKey: dataKey)
                    // Reload timeline after saving
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
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

            // Clean up deleted group events from Apple Calendar
            // This handles events that were deleted by another user (e.g., event creator)
            try await cleanupDeletedGroupEventsFromAppleCalendar(userId: userId)

            // IMPORTANT: Sync group events to Apple Calendar FIRST, before uploading personal events
            // This ensures that group events synced to Apple Calendar are marked with apple_calendar_event_id
            // so they won't be uploaded back as personal events
            try await syncPendingGroupEventsToAppleCalendar(userId: userId)

            // Update already-synced group events in Apple Calendar if they've been modified
            try await updateSyncedGroupEventsInAppleCalendar(userId: userId)
            
            // Sync recurrence exceptions (modified/cancelled occurrences) to Apple Calendar
            try await syncRecurrenceExceptionsToAppleCalendar(userId: userId)

            // Refresh Apple Calendar events after syncing group events to get the latest state
            await refreshEvents()

            // Upload to database (this will skip group events that were just synced)
            try await uploadEventsToDatabase(groupId: groupId, userId: userId)

            // Fetch all group events
            try await fetchGroupEvents(groupId: groupId)
        } catch {
            lastSyncError = error.localizedDescription
            print("Error syncing calendar with group: \(error)")
        }
    }
    
    /// Syncs group events the user is invited to but haven't been synced to Apple Calendar yet
    private func syncPendingGroupEventsToAppleCalendar(userId: UUID) async throws {
        // Prevent concurrent execution - if already syncing, skip this call
        guard !isSyncingPendingEvents else {
            return
        }
        
        isSyncingPendingEvents = true
        defer { isSyncingPendingEvents = false }
        
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
            let recurrence_rule: RecurrenceRule?
            // Exception fields
            let is_recurrence_exception: Bool?
            let parent_event_id: UUID?
            let original_occurrence_date: Date?
            let is_public: Bool?

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
                let recurrence_rule: RecurrenceRule?
                // Exception fields
                let is_recurrence_exception: Bool?
                let parent_event_id: UUID?
                let original_occurrence_date: Date?
                let is_public: Bool?

                struct CategoryInfo: Decodable {
                    let color: ColorComponents
                }
            }
        }
        
        let attendeeRows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("event_id, id, calendar_events(title, start_date, end_date, is_all_day, location, notes, category_id, event_type, event_categories(color), recurrence_rule, is_recurrence_exception, parent_event_id, original_occurrence_date, is_public)")
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
                },
                recurrence_rule: event.recurrence_rule,
                is_recurrence_exception: event.is_recurrence_exception,
                parent_event_id: event.parent_event_id,
                original_occurrence_date: event.original_occurrence_date,
                is_public: event.is_public
            )
        }
        // CRITICAL: Deduplicate by event_id to ensure we only process each unique event once
        // Multiple attendee rows can exist for the same event (e.g., across different groups)
        var eventMap: [UUID: PendingEventRow] = [:]
        for pendingEvent in groupPendingEvents {
            if eventMap[pendingEvent.event_id] == nil {
                eventMap[pendingEvent.event_id] = pendingEvent
            }
        }
        let uniquePendingEvents = Array(eventMap.values)
        
        // Sync each pending event to Apple Calendar
        // First check if the event already exists in Apple Calendar to avoid duplicates
        guard authorizationStatus == .authorized else { return }
        
        // Refresh Apple Calendar events to get the latest state
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        var existingAppleEvents = eventStore.events(matching: predicate)
        
        // Track which event_ids we've already processed AND which Apple Calendar event IDs we've created
        // This prevents duplicates even if EventKit hasn't updated yet
        var processedEventIds: Set<UUID> = []
        var createdAppleEventIds: Set<String> = []
        
        // Track events we've created by title+time signature to prevent duplicates
        // Format: "title|startTimestamp|endTimestamp|isAllDay"
        var createdEventSignatures: Set<String> = []
        
        for pendingEvent in uniquePendingEvents {
            // Skip if we've already processed this event_id in this sync session
            if processedEventIds.contains(pendingEvent.event_id) {
                continue
            }
            
            // Skip exception events - they should be handled by syncRecurrenceExceptionsToAppleCalendar
            // which modifies existing occurrences rather than creating new events
            // Skip exception events - they are handled by syncRecurrenceExceptionsToAppleCalendar
            if pendingEvent.is_recurrence_exception == true {
                processedEventIds.insert(pendingEvent.event_id)
                continue
            }
            
            do {
                let appleEventId: String
                
                // Create a signature for this event to check for duplicates
                let eventSignature = "\(pendingEvent.title.trimmingCharacters(in: .whitespaces))|\(pendingEvent.start_date.timeIntervalSince1970)|\(pendingEvent.end_date.timeIntervalSince1970)|\(pendingEvent.is_all_day)"
                
                // First check: Have we already created an event with matching title/time in this session?
                // This prevents duplicates even if EventKit hasn't updated yet
                if createdEventSignatures.contains(eventSignature) {
                    // Find the existing event ID from Apple Calendar
                    let matchingEvent = existingAppleEvents.first { event in
                        guard let eventTitle = event.title else { return false }
                        guard let eventId = event.eventIdentifier else { return false }
                        
                        // Check if this is an event we've already created
                        if createdAppleEventIds.contains(eventId) {
                            let titleMatch = eventTitle.trimmingCharacters(in: .whitespaces) == pendingEvent.title.trimmingCharacters(in: .whitespaces)
                            let startMatch = abs(event.startDate.timeIntervalSince(pendingEvent.start_date)) < 1.0
                            let endMatch = abs(event.endDate.timeIntervalSince(pendingEvent.end_date)) < 1.0
                            let isAllDayMatch = event.isAllDay == pendingEvent.is_all_day
                            return titleMatch && startMatch && endMatch && isAllDayMatch
                        }
                        return false
                    }
                    if let existingEvent = matchingEvent, let existingEventId = existingEvent.eventIdentifier {
                        appleEventId = existingEventId
                        // Ensure signature is tracked (should already be, but just in case)
                        createdEventSignatures.insert(eventSignature)
                    } else {
                        // This shouldn't happen, but if it does, skip this event
                        processedEventIds.insert(pendingEvent.event_id)
                        continue
                    }
                } else {
                    // Check if an event with the same title, start, and end already exists in Apple Calendar
                    // Use a more strict matching: exact title match and times within 1 second
                    let matchingEvent = existingAppleEvents.first { event in
                        guard let eventTitle = event.title else { return false }
                        let titleMatch = eventTitle.trimmingCharacters(in: .whitespaces) == pendingEvent.title.trimmingCharacters(in: .whitespaces)
                        let startMatch = abs(event.startDate.timeIntervalSince(pendingEvent.start_date)) < 1.0
                        let endMatch = abs(event.endDate.timeIntervalSince(pendingEvent.end_date)) < 1.0
                        let isAllDayMatch = event.isAllDay == pendingEvent.is_all_day
                        return titleMatch && startMatch && endMatch && isAllDayMatch
                    }
                    
                    if let existingEvent = matchingEvent, let existingEventId = existingEvent.eventIdentifier {
                        // Event already exists in Apple Calendar, use its ID
                        appleEventId = existingEventId
                        // Track this ID and signature so we don't create another one
                        createdAppleEventIds.insert(existingEventId)
                        createdEventSignatures.insert(eventSignature)
                    } else {
                        // Create new Apple Calendar event only if it doesn't exist
                        let categoryColor = pendingEvent.event_categories?.color
                        appleEventId = try await EventKitEventManager.shared.createEvent(
                            title: pendingEvent.title,
                            start: pendingEvent.start_date,
                            end: pendingEvent.end_date,
                            isAllDay: pendingEvent.is_all_day,
                            location: pendingEvent.location,
                            notes: pendingEvent.notes,
                            categoryColor: categoryColor,
                            recurrenceRule: pendingEvent.recurrence_rule
                        )
                        
                        // Track this newly created ID and signature immediately to prevent duplicates
                        createdAppleEventIds.insert(appleEventId)
                        createdEventSignatures.insert(eventSignature)
                        
                        // Refresh the existing events list to include the newly created event
                        // This prevents creating duplicates if the same event appears multiple times
                        existingAppleEvents = eventStore.events(matching: predicate)
                    }
                }
                
                // Store the mapping locally for cleanup purposes
                // This survives even if attendee records are cascade-deleted
                storeSyncedGroupEvent(eventId: pendingEvent.event_id, appleCalendarEventId: appleEventId)

                // Store the Apple Calendar event ID for ALL attendee records for this event and user
                // Update all attendee records that don't have an apple_calendar_event_id yet
                struct UpdateAttendee: Encodable {
                    let apple_calendar_event_id: String
                }
                let update = UpdateAttendee(apple_calendar_event_id: appleEventId)
                
                // Update all attendee records for this event_id and user_id that don't have an apple_calendar_event_id
                // Use .select() to return the updated rows so we can count them
                struct UpdatedAttendee: Decodable {
                    let id: UUID
                }
                let updatedAttendees: [UpdatedAttendee] = try await client
                    .from("event_attendees")
                    .update(update)
                    .eq("event_id", value: pendingEvent.event_id)
                    .eq("user_id", value: userId)
                    .is("apple_calendar_event_id", value: nil)
                    .select("id")
                    .execute()
                    .value
                
                
                // Mark this event as processed to prevent duplicates
                processedEventIds.insert(pendingEvent.event_id)
            } catch {
                // Log error but continue with other events
                print("[CalendarSyncManager] Failed to sync pending event to Apple Calendar: \(error)")
            }
        }
    }

    /// Updates Apple Calendar events for group events that have been modified since last sync
    /// This handles the case where the event creator updates an event that the invited user already has synced
    private func updateSyncedGroupEventsInAppleCalendar(userId: UUID) async throws {
        guard let client = client else { return }
        guard authorizationStatus == .authorized else { return }

        // Fetch all attendee records where user has an apple_calendar_event_id (already synced)
        // Join with calendar_events to get the current event details and updated_at timestamp
        struct SyncedEventRow: Decodable {
            let event_id: UUID
            let apple_calendar_event_id: String
            let calendar_events: EventInfo?

            struct EventInfo: Decodable {
                let id: UUID
                let title: String
                let start_date: Date
                let end_date: Date
                let is_all_day: Bool
                let location: String?
                let notes: String?
                let updated_at: Date?
                let event_type: String
                let category_id: UUID?
                let event_categories: CategoryInfo?
                let recurrence_rule: RecurrenceRule?
                let recurrence_end_date: Date?  // Added for "this and future" delete sync
                // Exception fields for debugging
                let is_recurrence_exception: Bool?
                let parent_event_id: UUID?

                struct CategoryInfo: Decodable {
                    let color: ColorComponents
                }
            }
        }

        let syncedRows: [SyncedEventRow] = try await client
            .from("event_attendees")
            .select("event_id, apple_calendar_event_id, calendar_events(id, title, start_date, end_date, is_all_day, location, notes, updated_at, event_type, category_id, event_categories(color), recurrence_rule, recurrence_end_date, is_recurrence_exception, parent_event_id)")
            .eq("user_id", value: userId)
            .not("apple_calendar_event_id", operator: .is, value: "null")
            .execute()
            .value
        // Get local sync timestamps
        let localSyncTimestamps = getLocalSyncTimestamps()
        let localRecurrenceEndDates = getLocalRecurrenceEndDates()

        // Filter to only group events that have been updated since last sync
        let eventsToUpdate = syncedRows.filter { row in
            guard let event = row.calendar_events, event.event_type == "group" else { return false }
            
            // Check if recurrence_end_date has changed (for "this and future" deletes)
            if let currentEndDate = event.recurrence_end_date {
                let storedEndDateTimestamp = localRecurrenceEndDates[row.event_id.uuidString]
                if storedEndDateTimestamp == nil || abs(currentEndDate.timeIntervalSince1970 - storedEndDateTimestamp!) > 1.0 {
                    // recurrence_end_date is new or changed - needs sync
                    return true
                }
            }
            
            guard let updatedAt = event.updated_at else { return false }

            // Check local storage for last sync timestamp
            if let lastSynced = localSyncTimestamps[row.event_id.uuidString] {
                return updatedAt > lastSynced
            }

            // If no local sync timestamp, we should update (first time checking)
            return true
        }

        guard !eventsToUpdate.isEmpty else { return }

        print("[CalendarSyncManager] Found \(eventsToUpdate.count) group events to update in Apple Calendar")

        for row in eventsToUpdate {
            guard let event = row.calendar_events else { continue }

            do {
                let categoryColor = event.event_categories?.color

                // Handle "this and future" delete: if recurrence_end_date is set and event has a recurrence rule,
                // update the Apple Calendar event's recurrence to end at that date
                if let recurrenceEndDate = event.recurrence_end_date, event.recurrence_rule != nil {
                    // End the recurrence at the specified date (adds 1 day because endRecurrenceAt subtracts 1)
                    let calendar = Calendar.current
                    let dayAfter = calendar.date(byAdding: .day, value: 1, to: recurrenceEndDate) ?? recurrenceEndDate
                    try await EventKitEventManager.shared.endRecurrenceAt(identifier: row.apple_calendar_event_id, date: dayAfter)
                    
                    // Store the recurrence end date locally to avoid re-syncing
                    storeLocalRecurrenceEndDate(eventId: row.event_id, endDate: recurrenceEndDate)
                    
                    print("[CalendarSyncManager] Updated recurrence end date in Apple Calendar for invited user: \(event.title)")
                } else {
                    // Regular update for non-recurring or events without end date change
                    try await EventKitEventManager.shared.updateEvent(
                        identifier: row.apple_calendar_event_id,
                        title: event.title,
                        start: event.start_date,
                        end: event.end_date,
                        isAllDay: event.is_all_day,
                        location: event.location,
                        notes: event.notes,
                        categoryColor: categoryColor,
                        updateAllOccurrences: event.recurrence_rule != nil
                    )
                }

                // Store sync timestamp locally
                storeLocalSyncTimestamp(eventId: row.event_id, timestamp: Date())

                print("[CalendarSyncManager] Updated Apple Calendar event: \(event.title)")
            } catch {
                print("[CalendarSyncManager] Failed to update Apple Calendar event \(event.title): \(error)")
            }
        }
    }

    /// Syncs recurrence exceptions (modified or cancelled occurrences) to Apple Calendar for invited users
    /// This handles the case where the creator modifies or deletes a single occurrence
    private func syncRecurrenceExceptionsToAppleCalendar(userId: UUID) async throws {
        guard let client = client else { return }
        guard authorizationStatus == .authorized else { return }
        // Fetch all recurrence exceptions that this user might need to sync
        // These are events where is_recurrence_exception = true
        struct ExceptionRow: Decodable {
            let id: UUID
            let title: String
            let start_date: Date
            let end_date: Date
            let is_all_day: Bool
            let location: String?
            let notes: String?
            let is_public: Bool
            let parent_event_id: UUID?
            let original_occurrence_date: Date?
            let updated_at: Date?
        }
        
        // Get recurrence exceptions from groups the user is a member of
        struct UserGroupRow: Decodable { let group_id: UUID }
        let userGroupRows: [UserGroupRow] = try await client
            .from("group_members")
            .select("group_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        let userGroupIds = userGroupRows.map { $0.group_id }
        
        guard !userGroupIds.isEmpty else { return }
        
        let exceptionRows: [ExceptionRow] = try await client
            .from("calendar_events")
            .select("id, title, start_date, end_date, is_all_day, location, notes, is_public, parent_event_id, original_occurrence_date, updated_at")
            .eq("is_recurrence_exception", value: true)
            .in("group_id", values: userGroupIds)
            .execute()
            .value
        // Get local sync timestamps for exceptions
        let exceptionSyncTimestamps = getExceptionSyncTimestamps()
        
        for exception in exceptionRows {
            guard let parentEventId = exception.parent_event_id,
                  let originalOccurrenceDate = exception.original_occurrence_date else { continue }
            
            // Check if we've already synced this exception
            let exceptionKey = "\(exception.id.uuidString)"
            if let lastSynced = exceptionSyncTimestamps[exceptionKey],
               let updatedAt = exception.updated_at,
               updatedAt <= lastSynced {
                continue // Already synced this version
            }
            
            // Get the parent event's Apple Calendar ID for this user
            struct ParentAttendee: Decodable {
                let apple_calendar_event_id: String?
            }
            let parentAttendees: [ParentAttendee] = try await client
                .from("event_attendees")
                .select("apple_calendar_event_id")
                .eq("event_id", value: parentEventId)
                .eq("user_id", value: userId)
                .execute()
                .value
            
            guard let appleEventId = parentAttendees.first?.apple_calendar_event_id else {
                continue // User doesn't have this event in Apple Calendar
            }
            
            do {
                if !exception.is_public {
                    // This is a cancelled occurrence - delete it from Apple Calendar
                    try await EventKitEventManager.shared.deleteRecurringOccurrence(
                        identifier: appleEventId,
                        occurrenceDate: originalOccurrenceDate
                    )
                    print("[CalendarSyncManager] Deleted cancelled occurrence for invited user: \(exception.title) on \(originalOccurrenceDate)")
                } else {
                    // This is a modified occurrence - update it in Apple Calendar
                    try await EventKitEventManager.shared.updateRecurringOccurrence(
                        identifier: appleEventId,
                        occurrenceDate: originalOccurrenceDate,
                        newTitle: exception.title,
                        newStart: exception.start_date,
                        newEnd: exception.end_date,
                        newIsAllDay: exception.is_all_day,
                        newLocation: exception.location,
                        newNotes: exception.notes
                    )
                    print("[CalendarSyncManager] Updated modified occurrence for invited user: \(exception.title) on \(originalOccurrenceDate)")
                }
                
                // Store sync timestamp
                storeExceptionSyncTimestamp(exceptionId: exception.id, timestamp: Date())
                
            } catch {
                print("[CalendarSyncManager] Failed to sync exception to Apple Calendar: \(error)")
            }
        }
    }
    
    // MARK: - Exception Sync Timestamp Storage
    
    private static let exceptionSyncTimestampsKey = "RecurrenceExceptionSyncTimestamps"
    
    private func getExceptionSyncTimestamps() -> [String: Date] {
        guard let data = defaults.dictionary(forKey: Self.exceptionSyncTimestampsKey) as? [String: Double] else {
            return [:]
        }
        return data.mapValues { Date(timeIntervalSince1970: $0) }
    }
    
    private func storeExceptionSyncTimestamp(exceptionId: UUID, timestamp: Date) {
        var timestamps = defaults.dictionary(forKey: Self.exceptionSyncTimestampsKey) as? [String: Double] ?? [:]
        timestamps[exceptionId.uuidString] = timestamp.timeIntervalSince1970
        defaults.set(timestamps, forKey: Self.exceptionSyncTimestampsKey)
    }

    // MARK: - Local Sync Timestamp Storage

    private static let localSyncTimestampsKey = "GroupEventSyncTimestamps"
    private static let localRecurrenceEndDatesKey = "GroupEventRecurrenceEndDates"

    private func getLocalSyncTimestamps() -> [String: Date] {
        guard let data = defaults.dictionary(forKey: Self.localSyncTimestampsKey) as? [String: Double] else {
            return [:]
        }
        return data.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func storeLocalSyncTimestamp(eventId: UUID, timestamp: Date) {
        var timestamps = defaults.dictionary(forKey: Self.localSyncTimestampsKey) as? [String: Double] ?? [:]
        timestamps[eventId.uuidString] = timestamp.timeIntervalSince1970
        defaults.set(timestamps, forKey: Self.localSyncTimestampsKey)
    }
    
    private func getLocalRecurrenceEndDates() -> [String: Double] {
        return defaults.dictionary(forKey: Self.localRecurrenceEndDatesKey) as? [String: Double] ?? [:]
    }
    
    private func storeLocalRecurrenceEndDate(eventId: UUID, endDate: Date?) {
        var dates = defaults.dictionary(forKey: Self.localRecurrenceEndDatesKey) as? [String: Double] ?? [:]
        if let endDate = endDate {
            dates[eventId.uuidString] = endDate.timeIntervalSince1970
        } else {
            dates.removeValue(forKey: eventId.uuidString)
        }
        defaults.set(dates, forKey: Self.localRecurrenceEndDatesKey)
    }

    /// Cleans up Apple Calendar events for group events that have been deleted from the database
    /// This handles the case where another user (e.g., event creator) deleted a group event
    private func cleanupDeletedGroupEventsFromAppleCalendar(userId: UUID) async throws {
        guard let client = client else { return }
        guard authorizationStatus == .authorized else { return }
        // APPROACH 1: Check local storage for synced group events and verify they still exist and are active
        // This is the most reliable method as it doesn't depend on server-side records
        // Also handles rain-checked events which should be removed from Apple Calendar
        let localMapping = getSyncedGroupEventsMapping()
        if !localMapping.isEmpty {
            let localEventIds = localMapping.keys.compactMap { UUID(uuidString: $0) }

            if !localEventIds.isEmpty {
                struct ExistingEvent: Decodable {
                    let id: UUID
                    let event_status: String?
                }
                let existingEvents: [ExistingEvent] = try await client
                    .from("calendar_events")
                    .select("id, event_status")
                    .in("id", values: localEventIds)
                    .execute()
                    .value

                let activeEventIds = Set(existingEvents.filter { event in
                    // Event is active if status is null or "active"
                    event.event_status == nil || event.event_status == "active"
                }.map { $0.id })

                // Find events in local storage that no longer exist, are deleted, or are rain-checked
                for (eventIdString, appleCalendarEventId) in localMapping {
                    guard let eventId = UUID(uuidString: eventIdString) else { continue }

                    if !activeEventIds.contains(eventId) {
                        // Event was deleted from database or rain-checked, delete from Apple Calendar
                        do {
                            try await EventKitEventManager.shared.deleteEvent(identifier: appleCalendarEventId)
                            print("[CalendarSyncManager] Deleted Apple Calendar event for deleted/rain-checked group event: \(appleCalendarEventId)")
                        } catch {
                            print("[CalendarSyncManager] Failed to delete Apple Calendar event (may already be deleted): \(error)")
                        }
                        // Remove from local storage
                        removeSyncedGroupEvent(eventId: eventId)
                    }
                }
            }
        }

        // APPROACH 2: Check for pending deletions table (if it exists)
        struct PendingDeletion: Decodable {
            let id: UUID
            let apple_calendar_event_id: String
        }
        let pendingDeletions: [PendingDeletion] = (try? await client
            .from("pending_apple_calendar_deletions")
            .select("id, apple_calendar_event_id")
            .eq("user_id", value: userId)
            .execute()
            .value) ?? []

        // Delete Apple Calendar events from pending deletions
        var deletedPendingIds: [UUID] = []
        for pending in pendingDeletions {
            do {
                try await EventKitEventManager.shared.deleteEvent(identifier: pending.apple_calendar_event_id)
                deletedPendingIds.append(pending.id)
                print("[CalendarSyncManager] Deleted Apple Calendar event from pending deletion: \(pending.apple_calendar_event_id)")
            } catch {
                // Still mark as processed even if delete fails (event might already be gone)
                deletedPendingIds.append(pending.id)
                print("[CalendarSyncManager] Failed to delete pending Apple Calendar event (may already be deleted): \(error)")
            }
            // Also remove from local storage if present
            removeSyncedGroupEventByAppleId(pending.apple_calendar_event_id)
        }

        // Remove processed pending deletions
        if !deletedPendingIds.isEmpty {
            _ = try? await client
                .from("pending_apple_calendar_deletions")
                .delete()
                .in("id", values: deletedPendingIds)
                .execute()
        }

        // APPROACH 3: Check for orphaned attendee records (fallback for older events)
        // Also handles rain-checked events that should be removed from Apple Calendar
        struct AttendeeAppleEventId: Decodable {
            let event_id: UUID
            let apple_calendar_event_id: String?
        }
        let attendeeRows: [AttendeeAppleEventId] = try await client
            .from("event_attendees")
            .select("event_id, apple_calendar_event_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        // Filter to only rows that have an apple_calendar_event_id
        let syncedAttendees = attendeeRows.filter { $0.apple_calendar_event_id != nil }
        guard !syncedAttendees.isEmpty else { return }

        // Get the event IDs and check which ones still exist and are active in calendar_events
        let eventIds = syncedAttendees.map { $0.event_id }

        struct ExistingEventCheck: Decodable {
            let id: UUID
            let event_status: String?
        }
        let existingEventsCheck: [ExistingEventCheck] = try await client
            .from("calendar_events")
            .select("id, event_status")
            .in("id", values: eventIds)
            .execute()
            .value

        // Events are active if status is null or "active" (exclude rain-checked and deleted)
        let activeEventIdsCheck = Set(existingEventsCheck.filter { event in
            event.event_status == nil || event.event_status == "active"
        }.map { $0.id })

        // Find attendee records where the event no longer exists or is rain-checked
        let deletedAttendees = syncedAttendees.filter { !activeEventIdsCheck.contains($0.event_id) }

        // Delete the Apple Calendar events for deleted or rain-checked group events
        for attendee in deletedAttendees {
            if let appleEventId = attendee.apple_calendar_event_id {
                do {
                    try await EventKitEventManager.shared.deleteEvent(identifier: appleEventId)
                    print("[CalendarSyncManager] Deleted orphaned/rain-checked Apple Calendar event: \(appleEventId)")
                } catch {
                    print("[CalendarSyncManager] Failed to delete orphaned Apple Calendar event: \(error)")
                }
                // Also remove from local storage if present
                removeSyncedGroupEventByAppleId(appleEventId)
            }
        }

        // Clean up the orphaned attendee records
        let deletedEventIds = deletedAttendees.map { $0.event_id }
        if !deletedEventIds.isEmpty {
            _ = try? await client
                .from("event_attendees")
                .delete()
                .eq("user_id", value: userId)
                .in("event_id", values: deletedEventIds)
                .execute()
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
