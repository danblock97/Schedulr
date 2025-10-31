//
//  CalendarAnalysisService.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import Foundation
import Supabase

final class CalendarAnalysisService {
    static let shared = CalendarAnalysisService()
    
    private var client: SupabaseClient? {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Event Row Model
    private struct EventRow: Decodable {
        let id: UUID
        let user_id: UUID
        let start_date: Date
        let end_date: Date
        let is_all_day: Bool
    }
    
    // MARK: - Find Free Time Slots
    
    /// Finds free time slots for specified users within given constraints
    /// - Parameters:
    ///   - userIds: Array of user IDs to check availability for
    ///   - groupId: Group ID to fetch events from
    ///   - durationHours: Required duration for the meeting/event
    ///   - timeWindow: Optional time window (e.g., 12:00-17:00)
    ///   - dateRange: Date range to search within
    /// - Returns: Array of free time slots, sorted by confidence (best first)
    func findFreeTimeSlots(
        userIds: [UUID],
        groupId: UUID,
        durationHours: Double,
        timeWindow: AvailabilityQuery.TimeWindow?,
        dateRange: AvailabilityQuery.DateRange?
    ) async throws -> [FreeTimeSlot] {
        guard let client = client else {
            throw NSError(domain: "CalendarAnalysisService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Supabase client not available"])
        }
        
        guard !userIds.isEmpty else {
            return []
        }
        
        // Determine date range
        let calendar = Calendar.current
        let now = Date()
        let searchStart: Date
        let searchEnd: Date
        
        if let dateRange = dateRange {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            searchStart = formatter.date(from: dateRange.start) ?? now
            searchEnd = formatter.date(from: dateRange.end) ?? calendar.date(byAdding: .day, value: 30, to: now) ?? now
        } else {
            searchStart = now
            searchEnd = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        }
        
        // Fetch all events for specified users in the date range
        let rows: [EventRow] = try await client
            .from("calendar_events")
            .select("id, user_id, start_date, end_date, is_all_day")
            .eq("group_id", value: groupId)
            .in("user_id", value: userIds)
            .gte("end_date", value: searchStart)
            .lte("start_date", value: searchEnd)
            .order("start_date", ascending: true)
            .execute()
            .value
        
        // Group events by user
        var userEvents: [UUID: [EventRow]] = [:]
        for userId in userIds {
            userEvents[userId] = []
        }
        
        for event in rows {
            userEvents[event.user_id, default: []].append(event)
        }
        
        // Find free time slots
        var freeSlots: [FreeTimeSlot] = []
        let duration = durationHours * 3600 // Convert to seconds
        let slotDuration = duration
        
        // Iterate through days in the search range
        var currentDate = calendar.startOfDay(for: searchStart)
        let endDate = calendar.startOfDay(for: searchEnd)
        
        while currentDate <= endDate {
            // Get time window for this day
            let dayStart: Date
            let dayEnd: Date
            
            if let timeWindow = timeWindow {
                dayStart = parseTimeWindow(time: timeWindow.start, for: currentDate)
                dayEnd = parseTimeWindow(time: timeWindow.end, for: currentDate)
            } else {
                dayStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: currentDate) ?? currentDate
                dayEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: currentDate) ?? currentDate
            }
            
            // Find all free slots for this day
            let daySlots = findFreeSlotsForDay(
                dayStart: dayStart,
                dayEnd: dayEnd,
                userEvents: userEvents,
                slotDuration: slotDuration,
                date: currentDate
            )
            
            freeSlots.append(contentsOf: daySlots)
            
            // Move to next day
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDay
        }
        
        // Sort by confidence (highest first), then by start date
        return freeSlots.sorted { slot1, slot2 in
            if slot1.confidence != slot2.confidence {
                return slot1.confidence > slot2.confidence
            }
            return slot1.startDate < slot2.startDate
        }
    }
    
    // MARK: - Helper Methods
    
    private func findFreeSlotsForDay(
        dayStart: Date,
        dayEnd: Date,
        userEvents: [UUID: [EventRow]],
        slotDuration: TimeInterval,
        date: Date
    ) -> [FreeTimeSlot] {
        var slots: [FreeTimeSlot] = []
        let calendar = Calendar.current
        
        // Create a timeline of busy periods for all users
        var busyPeriods: [(start: Date, end: Date)] = []
        
        for (_, events) in userEvents {
            for event in events {
                if calendar.isDate(event.start_date, inSameDayAs: date) ||
                   calendar.isDate(event.end_date, inSameDayAs: date) ||
                   (event.start_date < date && event.end_date > calendar.date(byAdding: .day, value: 1, to: date) ?? date) {
                    let periodStart = max(event.start_date, dayStart)
                    let periodEnd = min(event.end_date, dayEnd)
                    if periodStart < periodEnd {
                        busyPeriods.append((start: periodStart, end: periodEnd))
                    }
                }
            }
        }
        
        // Sort busy periods by start time
        busyPeriods.sort { $0.start < $1.start }
        
        // Merge overlapping busy periods
        var mergedPeriods: [(start: Date, end: Date)] = []
        for period in busyPeriods {
            if let last = mergedPeriods.last, period.start <= last.end {
                mergedPeriods[mergedPeriods.count - 1] = (start: last.start, end: max(last.end, period.end))
            } else {
                mergedPeriods.append(period)
            }
        }
        
        // Find gaps between busy periods
        var currentTime = dayStart
        
        for period in mergedPeriods {
            let gapStart = currentTime
            let gapEnd = period.start
            
            if gapEnd.timeIntervalSince(gapStart) >= slotDuration {
                // Found a free slot
                let slotEnd = min(gapEnd, calendar.date(byAdding: .second, value: Int(slotDuration), to: gapStart) ?? gapEnd)
                
                // Calculate confidence based on how many users are available
                let totalUsers = userEvents.keys.count
                let availableUsers = findAvailableUsers(in: userEvents, forSlot: gapStart..<slotEnd, date: date)
                let confidence = Double(availableUsers.count) / Double(totalUsers)
                
                if confidence > 0 {
                    slots.append(FreeTimeSlot(
                        startDate: gapStart,
                        endDate: slotEnd,
                        durationHours: slotDuration / 3600,
                        confidence: confidence,
                        availableUsers: availableUsers
                    ))
                }
            }
            
            currentTime = period.end
        }
        
        // Check if there's a free slot after the last busy period
        if dayEnd.timeIntervalSince(currentTime) >= slotDuration {
            let slotEnd = min(dayEnd, calendar.date(byAdding: .second, value: Int(slotDuration), to: currentTime) ?? dayEnd)
            let availableUsers = findAvailableUsers(in: userEvents, forSlot: currentTime..<slotEnd, date: date)
            let totalUsers = userEvents.keys.count
            let confidence = Double(availableUsers.count) / Double(totalUsers)
            
            if confidence > 0 {
                slots.append(FreeTimeSlot(
                    startDate: currentTime,
                    endDate: slotEnd,
                    durationHours: slotDuration / 3600,
                    confidence: confidence,
                    availableUsers: availableUsers
                ))
            }
        }
        
        return slots
    }
    
    private func findAvailableUsers(
        in userEvents: [UUID: [EventRow]],
        forSlot slotRange: Range<Date>,
        date: Date
    ) -> [UUID] {
        var availableUsers: [UUID] = []
        let calendar = Calendar.current
        
        for (userId, events) in userEvents {
            var hasConflict = false
            
            for event in events {
                if calendar.isDate(event.start_date, inSameDayAs: date) ||
                   calendar.isDate(event.end_date, inSameDayAs: date) ||
                   (event.start_date < date && event.end_date > calendar.date(byAdding: .day, value: 1, to: date) ?? date) {
                    if event.start_date < slotRange.upperBound && event.end_date > slotRange.lowerBound {
                        hasConflict = true
                        break
                    }
                }
            }
            
            if !hasConflict {
                availableUsers.append(userId)
            }
        }
        
        return availableUsers
    }
    
    private func parseTimeWindow(time: String, for date: Date) -> Date {
        let calendar = Calendar.current
        let components = time.split(separator: ":")
        
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            // Default to 9 AM if parsing fails
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}

