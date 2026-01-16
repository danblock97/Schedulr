import Foundation

struct DisplayEvent: Identifiable, Equatable {
    let base: CalendarEventWithUser
    let sharedCount: Int
    var id: UUID { base.id }
}

struct MultiDaySpanSegment: Identifiable, Equatable {
    let event: DisplayEvent
    let weekStart: Date
    let startIndex: Int
    let endIndex: Int
    let continuesFromPrevious: Bool
    let continuesToNext: Bool

    var id: String {
        "\(event.base.id.uuidString)-\(weekStart.timeIntervalSince1970)-\(startIndex)-\(endIndex)"
    }
}

extension DisplayEvent {
    var startDay: Date {
        Calendar.current.startOfDay(for: base.start_date)
    }

    var endDayInclusive: Date {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: base.start_date)
        var endDay = calendar.startOfDay(for: base.end_date)

        if !base.is_all_day, base.end_date > base.start_date, base.end_date == endDay {
            endDay = calendar.date(byAdding: .day, value: -1, to: endDay) ?? endDay
        }

        if endDay < startDay {
            return startDay
        }
        return endDay
    }

    var isMultiDay: Bool {
        startDay != endDayInclusive
    }
}

func multiDaySegments(for events: [DisplayEvent], weekDays: [Date]) -> [MultiDaySpanSegment] {
    let calendar = Calendar.current
    guard weekDays.count == 7, let firstDay = weekDays.first, let lastDay = weekDays.last else {
        return []
    }

    let weekStart = calendar.startOfDay(for: firstDay)
    let weekEnd = calendar.startOfDay(for: lastDay)

    return events.filter { $0.isMultiDay }.compactMap { event in
        let startDay = event.startDay
        let endDay = event.endDayInclusive

        if endDay < weekStart || startDay > weekEnd {
            return nil
        }

        let startIndex: Int
        if startDay <= weekStart {
            startIndex = 0
        } else {
            startIndex = weekDays.firstIndex(where: { calendar.isDate($0, inSameDayAs: startDay) }) ?? 0
        }

        let endIndex: Int
        if endDay >= weekEnd {
            endIndex = 6
        } else {
            endIndex = weekDays.firstIndex(where: { calendar.isDate($0, inSameDayAs: endDay) }) ?? 6
        }

        return MultiDaySpanSegment(
            event: event,
            weekStart: weekStart,
            startIndex: startIndex,
            endIndex: endIndex,
            continuesFromPrevious: startDay < weekStart,
            continuesToNext: endDay > weekEnd
        )
    }
}


