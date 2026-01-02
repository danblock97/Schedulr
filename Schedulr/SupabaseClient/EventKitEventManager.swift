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

    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        categoryColor: ColorComponents? = nil,
        recurrenceRule: RecurrenceRule? = nil
    ) async throws -> String {
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

        // Add recurrence rule if provided
        if let rule = recurrenceRule {
            if let ekRule = convertToEKRecurrenceRule(rule) {
                event.recurrenceRules = [ekRule]
            }
        }

        try store.save(event, span: recurrenceRule != nil ? .futureEvents : .thisEvent)
        guard let eventId = event.eventIdentifier, !eventId.isEmpty else {
            throw NSError(domain: "EventKitEventManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get event identifier after saving"])
        }
        return eventId
    }

    func updateEvent(identifier: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String?, notes: String?, categoryColor: ColorComponents? = nil, updateAllOccurrences: Bool = false) async throws {
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

        // Use .futureEvents to update all occurrences of recurring events
        let span: EKSpan = (updateAllOccurrences && event.hasRecurrenceRules) ? .futureEvents : .thisEvent
        try store.save(event, span: span)
    }

    func deleteEvent(identifier: String, deleteAllOccurrences: Bool = true) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        // Use .futureEvents for recurring events to delete all occurrences
        // Use .thisEvent for single events or when only deleting one occurrence
        let span: EKSpan = (deleteAllOccurrences && event.hasRecurrenceRules) ? .futureEvents : .thisEvent
        try store.remove(event, span: span, commit: true)
    }

    /// Delete a specific occurrence of a recurring event by finding the occurrence at the given date
    func deleteRecurringOccurrence(identifier: String, occurrenceDate: Date) async throws {
        try await ensureAccess()
        guard let masterEvent = store.event(withIdentifier: identifier) else { return }

        // Find the specific occurrence at the given date
        let startOfDay = Calendar.current.startOfDay(for: occurrenceDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? occurrenceDate.addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [masterEvent.calendar])
        let occurrences = store.events(matching: predicate)

        // Find the occurrence that matches the master event
        // For recurring events, occurrences have the same eventIdentifier as the master
        for occurrence in occurrences {
            // Match by eventIdentifier OR by title (for recurring events with the same master)
            let matchesById = occurrence.eventIdentifier == identifier
            let matchesByTitle = occurrence.title == masterEvent.title

            // Also check if the occurrence time is close to what we expect
            let startMatches = Calendar.current.isDate(occurrence.startDate, inSameDayAs: occurrenceDate)

            if (matchesById || matchesByTitle) && startMatches {
                // Use .thisEvent to only delete this specific occurrence
                // This creates an exception in Apple Calendar rather than deleting the series
                try store.remove(occurrence, span: .thisEvent, commit: true)
                print("[EventKitEventManager] Deleted single occurrence on \(occurrenceDate)")
                return
            }
        }

        print("[EventKitEventManager] Could not find occurrence to delete on \(occurrenceDate)")
    }

    /// Update a specific occurrence of a recurring event
    func updateRecurringOccurrence(
        identifier: String,
        occurrenceDate: Date,
        newTitle: String,
        newStart: Date,
        newEnd: Date,
        newIsAllDay: Bool,
        newLocation: String?,
        newNotes: String?
    ) async throws {
        try await ensureAccess()
        guard let masterEvent = store.event(withIdentifier: identifier) else { return }

        // Find the specific occurrence at the given date
        let startOfDay = Calendar.current.startOfDay(for: occurrenceDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? occurrenceDate.addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [masterEvent.calendar])
        let occurrences = store.events(matching: predicate)

        // Find the occurrence that matches the master event
        if let occurrence = occurrences.first(where: { $0.eventIdentifier == identifier || $0.title == masterEvent.title }) {
            occurrence.title = newTitle
            occurrence.startDate = newStart
            occurrence.endDate = newEnd
            occurrence.isAllDay = newIsAllDay
            occurrence.location = newLocation
            occurrence.notes = newNotes

            // Use .thisEvent to only update this specific occurrence
            try store.save(occurrence, span: .thisEvent)
        }
    }

    /// Update the recurrence end date to effectively delete future occurrences
    func endRecurrenceAt(identifier: String, date: Date) async throws {
        try await ensureAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        guard let rules = event.recurrenceRules, !rules.isEmpty else { return }

        // Update the recurrence rule to end at the given date
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let newEnd = EKRecurrenceEnd(end: dayBefore)

        // Create a new recurrence rule with the end date
        if let oldRule = rules.first {
            let newRule = EKRecurrenceRule(
                recurrenceWith: oldRule.frequency,
                interval: oldRule.interval,
                daysOfTheWeek: oldRule.daysOfTheWeek,
                daysOfTheMonth: oldRule.daysOfTheMonth,
                monthsOfTheYear: oldRule.monthsOfTheYear,
                weeksOfTheYear: oldRule.weeksOfTheYear,
                daysOfTheYear: oldRule.daysOfTheYear,
                setPositions: oldRule.setPositions,
                end: newEnd
            )
            event.recurrenceRules = [newRule]
            try store.save(event, span: .futureEvents)
        }
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

    // MARK: - Recurrence Conversion

    /// Converts a RecurrenceRule to an EKRecurrenceRule for Apple Calendar
    private func convertToEKRecurrenceRule(_ rule: RecurrenceRule) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }

        // Convert days of week
        var daysOfWeek: [EKRecurrenceDayOfWeek]? = nil
        if let days = rule.daysOfWeek {
            daysOfWeek = days.compactMap { dayIndex -> EKRecurrenceDayOfWeek? in
                // EKWeekday is 1-indexed (Sunday = 1)
                guard let weekday = EKWeekday(rawValue: dayIndex + 1) else { return nil }
                return EKRecurrenceDayOfWeek(weekday)
            }
            if daysOfWeek?.isEmpty == true {
                daysOfWeek = nil
            }
        }

        // Convert day of month
        var daysOfMonth: [NSNumber]? = nil
        if let day = rule.dayOfMonth {
            daysOfMonth = [NSNumber(value: day)]
        }

        // Convert month of year
        var monthsOfYear: [NSNumber]? = nil
        if let month = rule.monthOfYear {
            monthsOfYear = [NSNumber(value: month)]
        }

        // Recurrence end
        var recurrenceEnd: EKRecurrenceEnd? = nil
        if let count = rule.count {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count)
        } else if let endDate = rule.endDate {
            recurrenceEnd = EKRecurrenceEnd(end: endDate)
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: rule.interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: recurrenceEnd
        )
    }
}


