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
                calendar_color: dbColorComps
            )
        }

        // Upload to Supabase (using upsert to handle duplicates)
        if !dbEvents.isEmpty {
            try await client
                .from("calendar_events")
                .upsert(dbEvents, onConflict: "user_id,group_id,original_event_id")
                .execute()
        }
    }

    /// Fetches all calendar events for a group from Supabase
    func fetchGroupEvents(groupId: UUID) async throws {
        guard let client = client else {
            throw NSError(domain: "CalendarSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not available"])
        }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start

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
            let users: UserInfo?

            struct UserInfo: Decodable {
                let id: UUID
                let display_name: String?
                let avatar_url: String?
            }
        }

        let rows: [EventRow] = try await client
            .from("calendar_events")
            .select("*, users(id, display_name, avatar_url)")
            .eq("group_id", value: groupId)
            .gte("end_date", value: start)
            .lte("start_date", value: end)
            .order("start_date", ascending: true)
            .execute()
            .value

        // Convert to CalendarEventWithUser
        groupEvents = rows.map { row in
            let user = row.users.map { userInfo in
                DBUser(
                    id: userInfo.id,
                    display_name: userInfo.display_name,
                    avatar_url: userInfo.avatar_url,
                    created_at: nil,
                    updated_at: nil
                )
            }

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
                user: user
            )
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
        } catch {
            lastSyncError = error.localizedDescription
            print("Error syncing calendar with group: \(error)")
        }
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
