import Foundation
import SwiftUI
import Combine

/// ViewModel for the group availability heat map view
@MainActor
final class GroupAvailabilityViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var availabilitySummary: [AvailabilitySummary] = []
    @Published private(set) var everyoneFreeHighlights: [EveryoneFreeHighlight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedSlot: AvailabilitySummary?
    
    // MARK: - Configuration
    
    /// Number of days to show in the heat map
    let daysToShow = 7
    
    /// Hours to display (typical waking hours)
    let displayHours = Array(7..<22)  // 7am to 9pm
    
    /// Time blocks for simplified view
    enum TimeBlock: String, CaseIterable, Identifiable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        
        var id: String { rawValue }
        
        var hours: ClosedRange<Int> {
            switch self {
            case .morning: return 7...11
            case .afternoon: return 12...16
            case .evening: return 17...21
            }
        }
        
        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening: return "sunset.fill"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let groupId: UUID
    private let members: [DashboardViewModel.MemberSummary]
    
    // MARK: - Computed Properties
    
    /// Dates to display in the heat map
    var displayDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<daysToShow).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }
    
    /// The top highlight to show ("Everyone's free Saturday afternoon!")
    var topHighlight: EveryoneFreeHighlight? {
        everyoneFreeHighlights.first
    }
    
    /// Member names lookup
    var memberNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
    }
    
    // MARK: - Initialization
    
    init(groupId: UUID, members: [DashboardViewModel.MemberSummary]) {
        self.groupId = groupId
        self.members = members
    }
    
    // MARK: - Data Loading
    
    /// Loads availability data for the group
    func loadAvailability() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: daysToShow, to: startDate) else {
            errorMessage = "Failed to calculate date range"
            return
        }
        
        do {
            // Fetch availability summary and highlights in parallel
            async let summaryTask = AvailabilityService.shared.fetchAvailabilitySummary(
                groupId: groupId,
                startDate: startDate,
                endDate: endDate
            )
            
            async let highlightsTask = AvailabilityService.shared.findEveryoneFreeHighlights(
                groupId: groupId,
                startDate: startDate,
                endDate: endDate
            )
            
            let (summary, highlights) = try await (summaryTask, highlightsTask)
            
            availabilitySummary = summary
            everyoneFreeHighlights = highlights
        } catch {
            errorMessage = error.localizedDescription
            print("[GroupAvailabilityViewModel] Failed to load availability: \(error)")
        }
    }
    
    /// Refreshes availability data
    func refresh() async {
        await loadAvailability()
    }
    
    // MARK: - Data Access
    
    /// Gets the availability summary for a specific date and hour
    func getSummary(for date: Date, hour: Int) -> AvailabilitySummary? {
        let calendar = Calendar.current
        return availabilitySummary.first { summary in
            calendar.isDate(summary.slotDate, inSameDayAs: date) && summary.slotHour == hour
        }
    }
    
    /// Gets the aggregated availability for a time block on a specific date
    func getBlockSummary(for date: Date, block: TimeBlock) -> BlockSummary {
        let calendar = Calendar.current
        let relevantSlots = availabilitySummary.filter { summary in
            calendar.isDate(summary.slotDate, inSameDayAs: date) &&
            block.hours.contains(summary.slotHour)
        }
        
        guard !relevantSlots.isEmpty else {
            return BlockSummary(
                totalMembers: members.count,
                freeMembers: 0,
                allSlotsFree: false,
                freeMemberIds: []
            )
        }
        
        // A member is free for the block if they're free for ALL hours in that block
        let allFreeMemberIds = Set(relevantSlots.flatMap { $0.freeMemberIds })
        let membersFreeThroughoutBlock = allFreeMemberIds.filter { memberId in
            relevantSlots.allSatisfy { $0.freeMemberIds.contains(memberId) }
        }
        
        let totalMembers = relevantSlots.first?.totalMembers ?? members.count
        
        return BlockSummary(
            totalMembers: totalMembers,
            freeMembers: membersFreeThroughoutBlock.count,
            allSlotsFree: membersFreeThroughoutBlock.count == totalMembers && totalMembers > 0,
            freeMemberIds: Array(membersFreeThroughoutBlock)
        )
    }
    
    /// Summary for a time block
    struct BlockSummary {
        let totalMembers: Int
        let freeMembers: Int
        let allSlotsFree: Bool
        let freeMemberIds: [UUID]
        
        var freePercentage: Double {
            guard totalMembers > 0 else { return 0 }
            return Double(freeMembers) / Double(totalMembers)
        }
    }
    
    /// Gets the color for a given free percentage
    func colorForPercentage(_ percentage: Double) -> Color {
        switch percentage {
        case 1.0:
            return Color.green
        case 0.75..<1.0:
            return Color.green.opacity(0.7)
        case 0.5..<0.75:
            return Color.yellow
        case 0.25..<0.5:
            return Color.orange
        case 0.0..<0.25:
            return Color.red.opacity(0.6)
        default:
            return Color.gray.opacity(0.3)
        }
    }
    
    /// Gets the names of members who are free
    func freeMemberNames(for memberIds: [UUID]) -> [String] {
        memberIds.compactMap { memberNames[$0] }
    }
}

