import Foundation
import Supabase

// MARK: - Models

/// Aggregated availability summary for a time slot
struct AvailabilitySummary: Identifiable, Equatable {
    let slotDate: Date
    let slotHour: Int
    let totalMembers: Int
    let freeMembers: Int
    let freeMemberIds: [UUID]
    
    var id: String { "\(slotDate.ISO8601Format())-\(slotHour)" }
    
    /// Percentage of members who are free (0.0 to 1.0)
    var freePercentage: Double {
        guard totalMembers > 0 else { return 0 }
        return Double(freeMembers) / Double(totalMembers)
    }
    
    /// Whether everyone in the group is free
    var isEveryoneFree: Bool {
        totalMembers > 0 && freeMembers == totalMembers
    }
}

/// A highlighted "everyone's free" slot
struct EveryoneFreeSlot: Identifiable, Equatable {
    let slotDate: Date
    let slotHour: Int
    let memberCount: Int
    
    var id: String { "\(slotDate.ISO8601Format())-\(slotHour)" }
    
    /// Human-readable description like "Saturday afternoon"
    var friendlyDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"  // Day name
        let dayName = formatter.string(from: slotDate)
        
        let timeOfDay: String
        switch slotHour {
        case 6..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        case 17..<21: timeOfDay = "evening"
        default: timeOfDay = "night"
        }
        
        return "\(dayName) \(timeOfDay)"
    }
}

/// Grouped "everyone's free" slots by day and time period
struct EveryoneFreeHighlight: Identifiable, Equatable {
    let date: Date
    let startHour: Int
    let endHour: Int
    let memberCount: Int
    
    var id: String { "\(date.ISO8601Format())-\(startHour)-\(endHour)" }
    
    /// Human-readable description
    var friendlyDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: date)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "ha"
        
        let calendar = Calendar.current
        let startDate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date
        let endDate = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date) ?? date
        
        let startTime = timeFormatter.string(from: startDate).lowercased()
        let endTime = timeFormatter.string(from: endDate).lowercased()
        
        // If it spans a full period, use friendly names
        if startHour >= 12 && endHour <= 17 {
            return "\(dayName) afternoon"
        } else if startHour >= 6 && endHour <= 12 {
            return "\(dayName) morning"
        } else if startHour >= 17 && endHour <= 21 {
            return "\(dayName) evening"
        }
        
        return "\(dayName) \(startTime)-\(endTime)"
    }
}

// MARK: - AvailabilityService

/// Service for computing availability from calendar events (zero storage approach)
/// All availability is computed on-demand from existing calendar_events table
final class AvailabilityService {
    static let shared = AvailabilityService()
    
    private init() {}
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    // MARK: - Fetch Availability (Computed On-Demand)
    
    /// Fetches aggregated availability summary for a group
    /// Computed on-demand from calendar_events - no additional storage required
    /// - Parameters:
    ///   - groupId: The group to fetch availability for
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of availability summaries showing how many members are free per slot
    func fetchAvailabilitySummary(
        groupId: UUID,
        startDate: Date,
        endDate: Date
    ) async throws -> [AvailabilitySummary] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        struct SummaryRow: Decodable {
            let slot_date: String
            let slot_hour: Int
            let total_members: Int
            let free_members: Int
            let free_member_ids: [UUID]?
        }
        
        let rows: [SummaryRow] = try await client.rpc(
            "get_group_availability_summary",
            params: [
                "p_group_id": groupId.uuidString,
                "p_start_date": dateFormatter.string(from: startDate),
                "p_end_date": dateFormatter.string(from: endDate)
            ]
        )
        .execute()
        .value
        
        return rows.compactMap { row in
            guard let date = dateFormatter.date(from: row.slot_date) else { return nil }
            return AvailabilitySummary(
                slotDate: date,
                slotHour: row.slot_hour,
                totalMembers: row.total_members,
                freeMembers: row.free_members,
                freeMemberIds: row.free_member_ids ?? []
            )
        }
    }
    
    /// Finds all "everyone's free" slots for a group
    /// Computed on-demand from calendar_events
    /// - Parameters:
    ///   - groupId: The group to check
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of slots where everyone is free
    func findEveryoneFreeSlots(
        groupId: UUID,
        startDate: Date,
        endDate: Date
    ) async throws -> [EveryoneFreeSlot] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        struct SlotRow: Decodable {
            let slot_date: String
            let slot_hour: Int
            let member_count: Int
        }
        
        let rows: [SlotRow] = try await client.rpc(
            "find_everyone_free_slots",
            params: [
                "p_group_id": groupId.uuidString,
                "p_start_date": dateFormatter.string(from: startDate),
                "p_end_date": dateFormatter.string(from: endDate)
            ]
        )
        .execute()
        .value
        
        return rows.compactMap { row in
            guard let date = dateFormatter.date(from: row.slot_date) else { return nil }
            return EveryoneFreeSlot(
                slotDate: date,
                slotHour: row.slot_hour,
                memberCount: row.member_count
            )
        }
    }
    
    /// Groups consecutive "everyone's free" slots into highlights
    /// e.g., 2pm, 3pm, 4pm -> "Saturday afternoon"
    func findEveryoneFreeHighlights(
        groupId: UUID,
        startDate: Date,
        endDate: Date
    ) async throws -> [EveryoneFreeHighlight] {
        let slots = try await findEveryoneFreeSlots(
            groupId: groupId,
            startDate: startDate,
            endDate: endDate
        )
        
        guard !slots.isEmpty else { return [] }
        
        // Group by date
        let calendar = Calendar.current
        var slotsByDate: [Date: [EveryoneFreeSlot]] = [:]
        
        for slot in slots {
            let dayStart = calendar.startOfDay(for: slot.slotDate)
            slotsByDate[dayStart, default: []].append(slot)
        }
        
        // Find consecutive hour ranges
        var highlights: [EveryoneFreeHighlight] = []
        
        for (date, daySlots) in slotsByDate {
            let sortedHours = daySlots.map { $0.slotHour }.sorted()
            guard !sortedHours.isEmpty else { continue }
            
            var rangeStart = sortedHours[0]
            var rangeEnd = sortedHours[0]
            let memberCount = daySlots.first?.memberCount ?? 0
            
            for i in 1..<sortedHours.count {
                if sortedHours[i] == rangeEnd + 1 {
                    // Consecutive hour
                    rangeEnd = sortedHours[i]
                } else {
                    // Gap found, save current range if it's meaningful (2+ hours)
                    if rangeEnd > rangeStart {
                        highlights.append(EveryoneFreeHighlight(
                            date: date,
                            startHour: rangeStart,
                            endHour: rangeEnd + 1,  // End hour is exclusive
                            memberCount: memberCount
                        ))
                    }
                    rangeStart = sortedHours[i]
                    rangeEnd = sortedHours[i]
                }
            }
            
            // Don't forget the last range
            if rangeEnd > rangeStart {
                highlights.append(EveryoneFreeHighlight(
                    date: date,
                    startHour: rangeStart,
                    endHour: rangeEnd + 1,
                    memberCount: memberCount
                ))
            }
        }
        
        // Sort by date, then by duration (longest first)
        return highlights.sorted { h1, h2 in
            if h1.date != h2.date {
                return h1.date < h2.date
            }
            return (h2.endHour - h2.startHour) < (h1.endHour - h1.startHour)
        }
    }
}
