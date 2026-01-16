//
//  SchedulrTests.swift
//  SchedulrTests
//
//  Created by Daniel Block on 29/10/2025.
//

import Testing
@testable import Schedulr

struct SchedulrTests {
    
    @Test func freeRangesWithNoEventsReturnsAllDay() async throws {
        let dayStart = makeDate(year: 2026, month: 1, day: 16, hour: 0, minute: 0)
        let dayEnd = makeDate(year: 2026, month: 1, day: 17, hour: 0, minute: 0)
        
        let ranges = AvailabilityRangeCalculator.freeRanges(
            dayStart: dayStart,
            dayEnd: dayEnd,
            busyPeriods: []
        )
        
        #expect(ranges.count == 1)
        #expect(ranges[0].startDate == dayStart)
        #expect(ranges[0].endDate == dayEnd)
    }
    
    @Test func freeRangesSplitBySingleBusyBlock() async throws {
        let dayStart = makeDate(year: 2026, month: 1, day: 16, hour: 0, minute: 0)
        let dayEnd = makeDate(year: 2026, month: 1, day: 17, hour: 0, minute: 0)
        
        let busy = [
            BusyPeriod(start: makeDate(year: 2026, month: 1, day: 16, hour: 10, minute: 0),
                       end: makeDate(year: 2026, month: 1, day: 16, hour: 12, minute: 0))
        ]
        
        let ranges = AvailabilityRangeCalculator.freeRanges(
            dayStart: dayStart,
            dayEnd: dayEnd,
            busyPeriods: busy
        )
        
        #expect(ranges.count == 2)
        #expect(ranges[0].startDate == dayStart)
        #expect(ranges[0].endDate == busy[0].start)
        #expect(ranges[1].startDate == busy[0].end)
        #expect(ranges[1].endDate == dayEnd)
    }
    
    @Test func freeRangesMergeOverlappingBusyBlocks() async throws {
        let dayStart = makeDate(year: 2026, month: 1, day: 16, hour: 0, minute: 0)
        let dayEnd = makeDate(year: 2026, month: 1, day: 17, hour: 0, minute: 0)
        
        let busy = [
            BusyPeriod(start: makeDate(year: 2026, month: 1, day: 16, hour: 9, minute: 0),
                       end: makeDate(year: 2026, month: 1, day: 16, hour: 11, minute: 0)),
            BusyPeriod(start: makeDate(year: 2026, month: 1, day: 16, hour: 10, minute: 0),
                       end: makeDate(year: 2026, month: 1, day: 16, hour: 12, minute: 0)),
            BusyPeriod(start: makeDate(year: 2026, month: 1, day: 16, hour: 14, minute: 0),
                       end: makeDate(year: 2026, month: 1, day: 16, hour: 15, minute: 0))
        ]
        
        let ranges = AvailabilityRangeCalculator.freeRanges(
            dayStart: dayStart,
            dayEnd: dayEnd,
            busyPeriods: busy
        )
        
        #expect(ranges.count == 3)
        #expect(ranges[0].startDate == dayStart)
        #expect(ranges[0].endDate == makeDate(year: 2026, month: 1, day: 16, hour: 9, minute: 0))
        #expect(ranges[1].startDate == makeDate(year: 2026, month: 1, day: 16, hour: 12, minute: 0))
        #expect(ranges[1].endDate == makeDate(year: 2026, month: 1, day: 16, hour: 14, minute: 0))
        #expect(ranges[2].startDate == makeDate(year: 2026, month: 1, day: 16, hour: 15, minute: 0))
        #expect(ranges[2].endDate == dayEnd)
    }
    
    @Test func freeRangesRespectTimeWindowBounds() async throws {
        let dayStart = makeDate(year: 2026, month: 1, day: 16, hour: 9, minute: 0)
        let dayEnd = makeDate(year: 2026, month: 1, day: 16, hour: 17, minute: 0)
        
        let busy = [
            BusyPeriod(start: makeDate(year: 2026, month: 1, day: 16, hour: 12, minute: 0),
                       end: makeDate(year: 2026, month: 1, day: 16, hour: 13, minute: 0))
        ]
        
        let ranges = AvailabilityRangeCalculator.freeRanges(
            dayStart: dayStart,
            dayEnd: dayEnd,
            busyPeriods: busy
        )
        
        #expect(ranges.count == 2)
        #expect(ranges[0].startDate == dayStart)
        #expect(ranges[0].endDate == busy[0].start)
        #expect(ranges[1].startDate == busy[0].end)
        #expect(ranges[1].endDate == dayEnd)
    }
    
    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components) ?? Date()
    }
}
