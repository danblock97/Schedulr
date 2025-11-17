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
        // Create a new Schedulr calendar if it doesn't exist
        let newCalendar = EKCalendar(for: .event, eventStore: store)
        newCalendar.title = "Schedulr"
        newCalendar.source = store.defaultCalendarForNewEvents?.source ?? store.sources.first
        do {
            try store.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            // If we can't create, fall back to default
            return store.defaultCalendarForNewEvents ?? EKCalendar(for: .event, eventStore: store)
        }
    }
    
    func getOrCreateCalendarForCategory(color: ColorComponents?) -> EKCalendar {
        // For now, use the default Schedulr calendar
        // In the future, we could create separate calendars per category if needed
        let calendar = defaultTargetCalendar()
        
        // Set the calendar color if provided
        if let color = color {
            let cgColor = CGColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(color.alpha)
            )
            // Note: cgColor is read-only for some calendar types, but we'll try to set it
            // If it fails, the calendar will use its default color
            calendar.cgColor = cgColor
            // Save the calendar to persist changes
            try? store.saveCalendar(calendar, commit: true)
        }
        
        return calendar
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?, categoryColor: ColorComponents? = nil) async throws -> String {
        try await ensureAccess()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        
        // Get calendar with category color if provided
        let calendar = getOrCreateCalendarForCategory(color: categoryColor)
        event.calendar = calendar
        
        try store.save(event, span: .thisEvent)
        guard let eventId = event.eventIdentifier, !eventId.isEmpty else {
            throw NSError(domain: "EventKitEventManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get event identifier after saving"])
        }
        return eventId
    }

    func updateEvent(identifier: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?, categoryColor: ColorComponents? = nil) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.location = location
        event.notes = notes
        
        // If category color is provided, update the calendar
        if let color = categoryColor {
            let calendar = getOrCreateCalendarForCategory(color: color)
            event.calendar = calendar
        }
        
        try store.save(event, span: .thisEvent)
    }

    func deleteEvent(identifier: String) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func findMatchingEvent(title: String, start: Date, end: Date, isAllDay: Bool, tolerance: TimeInterval = 60) async throws -> EKEvent? {
        try await ensureAccess()
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-tolerance),
            end: end.addingTimeInterval(tolerance),
            calendars: nil
        )
        let events = store.events(matching: predicate)
        return events.first(where: { event in
            guard let eventTitle = event.title else { return false }
            let titleMatch = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines) == title.trimmingCharacters(in: .whitespacesAndNewlines)
            let startMatch = abs(event.startDate.timeIntervalSince(start)) <= tolerance
            let endMatch = abs(event.endDate.timeIntervalSince(end)) <= tolerance
            let isAllDayMatch = event.isAllDay == isAllDay
            return titleMatch && startMatch && endMatch && isAllDayMatch
        })
    }
}


