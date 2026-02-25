//
//  SchedulrTests.swift
//  SchedulrTests
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation
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

    @Test func appIssueAlertSeenKeyIsNamespacedByUserAndRevision() async throws {
        let userA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let keyA1 = AppIssueAlertStore.makeSeenKey(userId: userA, alertKey: "incident-api", revision: 1)
        let keyA2 = AppIssueAlertStore.makeSeenKey(userId: userA, alertKey: "incident-api", revision: 2)
        let keyB1 = AppIssueAlertStore.makeSeenKey(userId: userB, alertKey: "incident-api", revision: 1)

        #expect(keyA1 != keyA2)
        #expect(keyA1 != keyB1)
        #expect(keyA1.contains(userA.uuidString))
        #expect(keyA1.contains(".r1"))
    }

    @Test func appIssueAlertShowOncePersistsAcrossReinstantiation() async throws {
        let defaults = makeIsolatedDefaults()
        let userId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let alert = makeAlert(key: "incident-calendar-sync", revision: 1)

        #expect(AppIssueAlertStore.hasSeen(alert: alert, userId: userId, defaults: defaults) == false)
        AppIssueAlertStore.markSeen(alert: alert, userId: userId, defaults: defaults)
        #expect(AppIssueAlertStore.hasSeen(alert: alert, userId: userId, defaults: defaults) == true)

        let defaultsReloaded = UserDefaults(suiteName: defaultsSuiteName)!
        #expect(AppIssueAlertStore.hasSeen(alert: alert, userId: userId, defaults: defaultsReloaded) == true)
    }

    @Test func appIssueAlertRevisionBumpBecomesVisibleAgain() async throws {
        let defaults = makeIsolatedDefaults()
        let userId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let v1 = makeAlert(key: "incident-ai", revision: 1)
        let v2 = makeAlert(key: "incident-ai", revision: 2)

        AppIssueAlertStore.markSeen(alert: v1, userId: userId, defaults: defaults)

        #expect(AppIssueAlertStore.hasSeen(alert: v1, userId: userId, defaults: defaults) == true)
        #expect(AppIssueAlertStore.hasSeen(alert: v2, userId: userId, defaults: defaults) == false)
    }

    @Test func appIssueAlertFiltersInactiveAndExpiredAlerts() async throws {
        let now = makeDate(year: 2026, month: 2, day: 25, hour: 12, minute: 0)

        let inactive = makeAlert(key: "inactive", isActive: false, updatedAt: now.addingTimeInterval(10))
        let expired = makeAlert(
            key: "expired",
            startsAt: now.addingTimeInterval(-3600),
            endsAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(20)
        )
        let future = makeAlert(
            key: "future",
            startsAt: now.addingTimeInterval(3600),
            endsAt: now.addingTimeInterval(7200),
            updatedAt: now.addingTimeInterval(30)
        )
        let valid = makeAlert(key: "valid", updatedAt: now)

        let selected = AppIssueAlertService.selectNextVisibleAlert(from: [inactive, expired, future, valid], now: now) { _ in false }
        #expect(selected?.key == "valid")
    }

    @Test func appIssueAlertRanksSeverityThenNewestUpdate() async throws {
        let now = makeDate(year: 2026, month: 2, day: 25, hour: 12, minute: 0)

        let warningNewest = makeAlert(key: "warning-new", severity: .warning, updatedAt: now.addingTimeInterval(120))
        let criticalOlder = makeAlert(key: "critical-old", severity: .critical, updatedAt: now.addingTimeInterval(-120))
        let criticalNewest = makeAlert(key: "critical-new", severity: .critical, updatedAt: now.addingTimeInterval(240))

        let selected = AppIssueAlertService.selectNextVisibleAlert(
            from: [warningNewest, criticalOlder, criticalNewest],
            now: now
        ) { alert in
            alert.key == "critical-new" // simulate already seen top candidate
        }

        #expect(selected?.key == "critical-old")
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

    private let defaultsSuiteName = "SchedulrTests.AppIssueAlerts.\(UUID().uuidString)"

    private func makeIsolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private func makeAlert(
        key: String,
        revision: Int = 1,
        isActive: Bool = true,
        severity: AppIssueAlert.Severity = .warning,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> AppIssueAlert {
        AppIssueAlert(
            id: UUID(),
            key: key,
            title: "Title \(key)",
            message: "Message \(key)",
            isActive: isActive,
            presentation: .banner,
            severity: severity,
            ctaLabel: nil,
            ctaURL: nil,
            startsAt: startsAt,
            endsAt: endsAt,
            revision: revision,
            createdAt: makeDate(year: 2026, month: 2, day: 25, hour: 10, minute: 0),
            updatedAt: updatedAt ?? makeDate(year: 2026, month: 2, day: 25, hour: 11, minute: 0)
        )
    }
}
