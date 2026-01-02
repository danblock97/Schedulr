import Foundation

final class RecurrenceService {
    static let shared = RecurrenceService()
    private init() {}

    /// Maximum occurrences to generate (1 year of daily = 365)
    private let maxOccurrences = 365

    // MARK: - Occurrence Generation

    /// Generate occurrence dates for a recurring event within a date range
    func generateOccurrences(
        for rule: RecurrenceRule,
        startingFrom eventStart: Date,
        inRange dateRange: ClosedRange<Date>,
        excludingDates: Set<Date> = []
    ) -> [Date] {
        var occurrences: [Date] = []
        var currentDate = eventStart
        var occurrenceCount = 0
        let calendar = Calendar.current

        // Determine effective end date
        let effectiveEndDate: Date
        if let ruleEndDate = rule.endDate {
            effectiveEndDate = min(ruleEndDate, dateRange.upperBound)
        } else {
            effectiveEndDate = dateRange.upperBound
        }

        // For weekly recurrence with specific days, we need to handle the first week specially
        if rule.frequency == .weekly, let daysOfWeek = rule.daysOfWeek, !daysOfWeek.isEmpty {
            // Start from the beginning of the week containing eventStart
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: eventStart)) ?? eventStart
            currentDate = weekStart
        }

        while currentDate <= effectiveEndDate && occurrenceCount < maxOccurrences {
            // Check count limit
            if let maxCount = rule.count, occurrenceCount >= maxCount {
                break
            }

            // Check if this date would be a valid occurrence (matching recurrence pattern)
            if shouldIncludeOccurrence(currentDate, for: rule, eventStart: eventStart) {
                // Apply the time from the original event
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: eventStart)
                if let occurrenceWithTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                           minute: timeComponents.minute ?? 0,
                                                           second: timeComponents.second ?? 0,
                                                           of: currentDate) {
                    // Only count if this is on or after the original event start
                    if occurrenceWithTime >= eventStart {
                        // This counts as an occurrence for the count limit, even if excluded
                        // This ensures excluded dates don't cause extra occurrences to be generated
                        occurrenceCount += 1

                        // Only add to results if within range and not excluded
                        if currentDate >= dateRange.lowerBound {
                            let startOfDay = calendar.startOfDay(for: currentDate)
                            let isExcluded = excludingDates.contains(startOfDay)
                            if !isExcluded {
                                print("[RecurrenceService] Adding occurrence: \(occurrenceWithTime), startOfDay: \(calendar.startOfDay(for: occurrenceWithTime)), isExcluded: \(isExcluded)")
                                occurrences.append(occurrenceWithTime)
                            } else {
                                print("[RecurrenceService] Skipping excluded occurrence: \(occurrenceWithTime), startOfDay: \(startOfDay)")
                            }
                        }
                    }
                }
            }

            // Advance to next potential occurrence
            currentDate = nextPotentialDate(after: currentDate, for: rule, calendar: calendar)
        }

        return occurrences
    }

    /// Expand a recurring event into individual occurrences for display
    func expandRecurringEvent(
        _ event: CalendarEventWithUser,
        inRange dateRange: ClosedRange<Date>,
        exceptions: [CalendarEventWithUser]
    ) -> [CalendarEventWithUser] {
        guard let rule = event.recurrenceRule else {
            return [event]
        }

        let eventDuration = event.end_date.timeIntervalSince(event.start_date)
        let calendar = Calendar.current

        // Build set of exception dates (original occurrence dates that were modified/cancelled)
        // Use start of day to ensure consistent comparison regardless of time precision differences
        let exceptionDates = Set(exceptions.compactMap { exception -> Date? in
            guard let originalDate = exception.originalOccurrenceDate else { return nil }
            let startOfDay = calendar.startOfDay(for: originalDate)
            print("[RecurrenceService] Exception date: \(originalDate) -> startOfDay: \(startOfDay)")
            return startOfDay
        })

        let occurrenceDates = generateOccurrences(
            for: rule,
            startingFrom: event.start_date,
            inRange: dateRange,
            excludingDates: exceptionDates
        )

        // Generate virtual instances
        return occurrenceDates.map { occurrenceStart in
            createVirtualInstance(from: event, at: occurrenceStart, duration: eventDuration)
        }
    }

    /// Get the next occurrence date after a given date
    func nextOccurrence(
        for rule: RecurrenceRule,
        after date: Date,
        startingFrom eventStart: Date
    ) -> Date? {
        let calendar = Calendar.current
        let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: date) ?? date

        let occurrences = generateOccurrences(
            for: rule,
            startingFrom: eventStart,
            inRange: date...oneYearFromNow
        )

        return occurrences.first { $0 > date }
    }

    /// Get human-readable description of recurrence
    func describeRecurrence(_ rule: RecurrenceRule) -> String {
        var description = "Every"

        if rule.interval > 1 {
            description += " \(rule.interval)"
        }

        switch rule.frequency {
        case .daily:
            description += rule.interval == 1 ? " day" : " days"

        case .weekly:
            description += rule.interval == 1 ? " week" : " weeks"
            if let days = rule.daysOfWeek, !days.isEmpty {
                let sortedDays = days.sorted()
                let dayNames = sortedDays.map { dayName(for: $0) }
                description += " on \(formatList(dayNames))"
            }

        case .monthly:
            description += rule.interval == 1 ? " month" : " months"
            if let day = rule.dayOfMonth {
                description += " on the \(ordinal(day))"
            }

        case .yearly:
            description += rule.interval == 1 ? " year" : " years"
            if let month = rule.monthOfYear, let day = rule.dayOfMonth {
                description += " on \(monthName(for: month)) \(day)"
            }
        }

        // End condition
        if let count = rule.count {
            description += ", \(count) times"
        } else if let endDate = rule.endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            description += ", until \(formatter.string(from: endDate))"
        }

        return description
    }

    // MARK: - Private Helpers

    private func shouldIncludeOccurrence(_ date: Date, for rule: RecurrenceRule, eventStart: Date) -> Bool {
        let calendar = Calendar.current

        switch rule.frequency {
        case .weekly:
            if let daysOfWeek = rule.daysOfWeek, !daysOfWeek.isEmpty {
                let weekday = calendar.component(.weekday, from: date) - 1 // Convert to 0-indexed (0 = Sunday)
                return daysOfWeek.contains(weekday)
            }
            // If no specific days, use the same weekday as the original event
            let eventWeekday = calendar.component(.weekday, from: eventStart)
            let dateWeekday = calendar.component(.weekday, from: date)
            return eventWeekday == dateWeekday

        case .monthly:
            if let dayOfMonth = rule.dayOfMonth {
                let day = calendar.component(.day, from: date)
                // Handle months with fewer days
                let range = calendar.range(of: .day, in: .month, for: date)
                let maxDay = range?.count ?? 31
                let targetDay = min(dayOfMonth, maxDay)
                return day == targetDay
            }
            // If no specific day, use the same day as the original event
            let eventDay = calendar.component(.day, from: eventStart)
            let dateDay = calendar.component(.day, from: date)
            return eventDay == dateDay

        case .yearly:
            if let monthOfYear = rule.monthOfYear, let dayOfMonth = rule.dayOfMonth {
                let month = calendar.component(.month, from: date)
                let day = calendar.component(.day, from: date)
                return month == monthOfYear && day == dayOfMonth
            }
            // If no specific month/day, use the same as the original event
            let eventMonth = calendar.component(.month, from: eventStart)
            let eventDay = calendar.component(.day, from: eventStart)
            let dateMonth = calendar.component(.month, from: date)
            let dateDay = calendar.component(.day, from: date)
            return eventMonth == dateMonth && eventDay == dateDay

        case .daily:
            return true
        }
    }

    private func nextPotentialDate(after date: Date, for rule: RecurrenceRule, calendar: Calendar) -> Date {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: date) ?? date

        case .weekly:
            if let daysOfWeek = rule.daysOfWeek, daysOfWeek.count > 1 {
                // For multiple days per week, advance by 1 day
                return calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: date) ?? date

        case .monthly:
            return calendar.date(byAdding: .month, value: rule.interval, to: date) ?? date

        case .yearly:
            return calendar.date(byAdding: .year, value: rule.interval, to: date) ?? date
        }
    }

    private func createVirtualInstance(
        from event: CalendarEventWithUser,
        at startDate: Date,
        duration: TimeInterval
    ) -> CalendarEventWithUser {
        CalendarEventWithUser(
            id: event.id,
            user_id: event.user_id,
            group_id: event.group_id,
            title: event.title,
            start_date: startDate,
            end_date: startDate.addingTimeInterval(duration),
            is_all_day: event.is_all_day,
            location: event.location,
            is_public: event.is_public,
            original_event_id: event.original_event_id,
            calendar_name: event.calendar_name,
            calendar_color: event.calendar_color,
            created_at: event.created_at,
            updated_at: event.updated_at,
            synced_at: event.synced_at,
            notes: event.notes,
            category_id: event.category_id,
            event_type: event.event_type,
            user: event.user,
            category: event.category,
            hasAttendees: event.hasAttendees,
            isCurrentUserAttendee: event.isCurrentUserAttendee,
            recurrenceRule: event.recurrenceRule,
            recurrenceEndDate: event.recurrenceEndDate,
            parentEventId: nil,
            isRecurrenceException: false,
            originalOccurrenceDate: startDate
        )
    }

    private func dayName(for dayIndex: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[dayIndex % 7]
    }

    private func fullDayName(for dayIndex: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayIndex % 7]
    }

    private func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        var components = DateComponents()
        components.month = month
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return ""
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 10 {
        case 1 where n % 100 != 11: suffix = "st"
        case 2 where n % 100 != 12: suffix = "nd"
        case 3 where n % 100 != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    private func formatList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let allButLast = items.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(items.last!)"
        }
    }
}
