import Foundation
import EventKit
import Combine

@MainActor
final class CalendarSyncManager: ObservableObject {
    struct ColorComponents: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
    }

    struct SyncedEvent: Identifiable, Equatable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let calendarTitle: String
        let isAllDay: Bool
        let calendarColor: ColorComponents
    }

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var syncEnabled: Bool
    @Published private(set) var isRequestingAccess: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var upcomingEvents: [SyncedEvent] = []
    @Published var lastSyncError: String?

    private let eventStore = EKEventStore()
    private var storeChangeObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private static let syncPreferenceKey = "CalendarSyncEnabled"

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

    private func observeEventStoreChanges() {
        guard storeChangeObserver == nil else { return }

        storeChangeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshEvents() }
        }
    }

    private func persistPreference() {
        defaults.set(syncEnabled, forKey: Self.syncPreferenceKey)
    }

    private func colorComponents(from cgColor: CGColor) -> ColorComponents {
        guard let space = cgColor.colorSpace, let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? space, intent: .defaultIntent, options: nil) else {
            return ColorComponents(red: 0.38, green: 0.55, blue: 0.93, opacity: 1.0)
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
        let opacity = comps.count >= 4 ? Double(comps[3]) : Double(converted.alpha)
        return ColorComponents(red: red, green: green, blue: blue, opacity: opacity)
    }
}
