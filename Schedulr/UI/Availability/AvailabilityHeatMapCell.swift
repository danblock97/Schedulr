import SwiftUI

/// A single cell in the availability heat map
struct AvailabilityHeatMapCell: View {
    let freePercentage: Double
    let isEveryoneFree: Bool
    let freeCount: Int
    let totalCount: Int
    
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    
    private var cellColor: Color {
        if isEveryoneFree {
            return themeManager.primaryColor
        }
        
        switch freePercentage {
        case 1.0:
            return Color.green
        case 0.75..<1.0:
            return Color.green.opacity(0.7)
        case 0.5..<0.75:
            return Color.yellow.opacity(0.8)
        case 0.25..<0.5:
            return Color.orange.opacity(0.7)
        case 0.01..<0.25:
            return colorScheme == .dark ? Color.red.opacity(0.5) : Color.red.opacity(0.4)
        default:
            // No data or all busy
            return colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.15)
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cellColor)
            
            if isEveryoneFree {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(minWidth: 40, minHeight: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isEveryoneFree ? themeManager.primaryColor.opacity(0.5) : Color.clear,
                    lineWidth: isEveryoneFree ? 2 : 0
                )
        )
    }
}

/// A row representing a time block (Morning/Afternoon/Evening) for all days
struct TimeBlockRow: View {
    let block: GroupAvailabilityViewModel.TimeBlock
    let dates: [Date]
    let viewModel: GroupAvailabilityViewModel
    let onTap: (Date, GroupAvailabilityViewModel.TimeBlock) -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 6) {
            // Time block label
            VStack(spacing: 2) {
                Image(systemName: block.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(themeManager.primaryColor)
                
                Text(block.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)
            
            // Cells for each day
            ForEach(dates, id: \.self) { date in
                let summary = viewModel.getBlockSummary(for: date, block: block)
                
                Button {
                    onTap(date, block)
                } label: {
                    AvailabilityHeatMapCell(
                        freePercentage: summary.freePercentage,
                        isEveryoneFree: summary.allSlotsFree,
                        freeCount: summary.freeMembers,
                        totalCount: summary.totalMembers
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Header row showing day names
struct DayHeaderRow: View {
    let dates: [Date]
    
    @EnvironmentObject var themeManager: ThemeManager
    
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    
    var body: some View {
        HStack(spacing: 6) {
            // Empty space for time label column
            Color.clear
                .frame(width: 50)
            
            // Day headers
            ForEach(dates, id: \.self) { date in
                let isToday = Calendar.current.isDateInToday(date)
                
                VStack(spacing: 2) {
                    Text(dayFormatter.string(from: date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? themeManager.primaryColor : .secondary)
                    
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? themeManager.primaryColor : .primary)
                }
                .frame(minWidth: 40)
                .padding(.vertical, 4)
                .background(
                    isToday ?
                    themeManager.primaryColor.opacity(0.1) :
                        Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }
}

/// "Everyone's free!" highlight banner
struct EveryoneFreeHighlightBanner: View {
    let highlight: EveryoneFreeHighlight
    let memberCount: Int
    let onTap: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(themeManager.primaryColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(themeManager.gradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everyone's free!")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(highlight.friendlyDescription)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Member count badge
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(memberCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(themeManager.primaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(themeManager.primaryColor.opacity(0.12), in: Capsule())
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [themeManager.primaryColor.opacity(0.3), themeManager.secondaryColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// Detail popover showing who's free
struct AvailabilityDetailPopover: View {
    let date: Date
    let block: GroupAvailabilityViewModel.TimeBlock
    let freeMemberNames: [String]
    let totalMembers: Int
    let onDismiss: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    
                    HStack(spacing: 6) {
                        Image(systemName: block.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(themeManager.primaryColor)
                        Text(block.rawValue)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Free members list
            if freeMemberNames.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No one's shared yet")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Members need to share their availability")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who's free")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    ForEach(freeMemberNames, id: \.self) { name in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.green)
                            
                            Text(name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                        }
                    }
                    
                    let busyCount = totalMembers - freeMemberNames.count
                    if busyCount > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.7))
                            
                            Text("\(busyCount) \(busyCount == 1 ? "person" : "people") busy")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}


