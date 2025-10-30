import Foundation
import EventKit

final class EventKitEventManager {
    static let shared = EventKitEventManager()
    private let store = EKEventStore()
    private init() {}

    enum EKError: Error { case notAuthorized }

    func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized: return
        case .notDetermined:
            let granted = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .event) { granted, err in
                    if let err { c.resume(throwing: err) } else { c.resume(returning: granted) }
                }
            }
            if !granted { throw EKError.notAuthorized }
        default:
            throw EKError.notAuthorized
        }
    }

    func defaultTargetCalendar() -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == "Schedulr" }) {
            return existing
        }
        // Fallback to default calendar if creating a new one is not desired here
        return store.defaultCalendarForNewEvents ?? EKCalendar(for: .event, eventStore: store)
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?) async throws -> String {
        try await ensureAccess()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        event.calendar = defaultTargetCalendar()
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func updateEvent(identifier: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        try store.save(event, span: .thisEvent)
    }

    func deleteEvent(identifier: String) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }
}


