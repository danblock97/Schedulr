//
//  UpNextWidgetView.swift
//  Schedulr
//
//  Created by Daniel Block on 24/11/2025.
//

import SwiftUI
import WidgetKit

struct UpNextWidgetView: View {
    var entry: UpNextProvider.Entry
    @Environment(\.widgetFamily) var family
    
    // App Theme Colors (Dynamic)
    private var primaryColor: Color { entry.theme.primary }
    private var secondaryColor: Color { entry.theme.secondary }
    private let schedulrPurple = Color(red: 0.58, green: 0.41, blue: 0.87) // Keep for branding

    var body: some View {
        switch family {
        case .accessoryRectangular:
            lockScreenView
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    // MARK: - Lock Screen
    var lockScreenView: some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(schedulrPurple)
                .frame(width: 3)
                .cornerRadius(1.5)
            
            VStack(alignment: .leading, spacing: 1) {
                if let event = entry.event {
                    Text(event.title)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    
                    Group {
                        if event.isAllDay ?? false {
                            Text("All Day • \(formatEventDate(for: event, abbreviated: true))")
                        } else {
                            Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) • \(formatEventDate(for: event, abbreviated: true))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No events")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - System Small
    var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let event = entry.event {
                // Header
                HStack(alignment: .center) {
                    Label(formatEventDate(for: event, abbreviated: true).uppercased(), systemImage: "calendar")
                        .font(.system(size: 11, weight: .bold)) // Increased from 9
                        .foregroundStyle(secondaryColor)
                    
                    Spacer()
                    
                    // Rotation Indicator (only show in rolling mode)
                    if entry.displayMode == .rolling {
                        HStack(spacing: 3) {
                            Circle().fill(primaryColor).frame(width: 4, height: 4)
                            Circle().fill(primaryColor.opacity(0.2)).frame(width: 4, height: 4)
                            Circle().fill(primaryColor.opacity(0.1)).frame(width: 4, height: 4)
                        }
                    }
                }
                .padding(.bottom, 6)
                
                // Content
                Text(event.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded)) // Increased from 16
                    .lineLimit(2) // Reduced limit to allow more space for other info
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 4)
                
                // Details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(secondaryColor)
                        Text(event.isAllDay ?? false ? "All Day" : event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold)) // Increased size
                    }
                    
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(location)
                                .font(.system(size: 12)) // Increased from 10
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Relative time footer
                HStack(spacing: 2) {
                    Text(event.startDate > Date() ? "STARTS IN " : "STARTED ")
                        .font(.system(size: 10, weight: .black))
                    Text(event.startDate, style: .relative)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(primaryColor)
                .padding(.top, 6)
                .textCase(.uppercase)
                    
            } else {
                emptyStateView
            }
        }
        .padding(12)
    }
    
    // MARK: - System Medium
    var mediumView: some View {
        HStack(spacing: 0) {
            if let event = entry.event {
                // Left side: Time & Date
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatEventDate(for: event, abbreviated: false).uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(secondaryColor)
                    
                    if event.isAllDay ?? false {
                        Text("All Day")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    } else {
                        Text(event.startDate, style: .time)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch.fill")
                            .font(.caption2)
                            .foregroundStyle(primaryColor)
                        Text(event.startDate > Date() ? "IN " : "STARTED ")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(primaryColor)
                        + Text(event.startDate, style: .relative)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                
                // Divider
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(colors: [primaryColor.opacity(0.8), secondaryColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                
                // Right side: Title & Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 20, weight: .bold)) // Increased from 18
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "location.fill")
                            .font(.system(size: 13)) // Increased size
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack {
                        Circle()
                            .fill(event.color)
                            .frame(width: 8, height: 8)
                        Text(event.calendarTitle)
                            .font(.system(size: 12, weight: .bold)) // Increased and lightened weight
                            .foregroundStyle(event.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(event.color.opacity(0.1))
                    .cornerRadius(20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                
            } else {
                emptyStateView
            }
        }
        .padding(16)
    }
    
    // MARK: - System Large
    var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !entry.upcomingEvents.isEmpty {
                // Large Header
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upcoming Events".uppercased()) // Restored context
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(secondaryColor)
                        
                        Text(Date().formatted(.dateTime.month(.wide)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(primaryColor)
                }
                .padding(.horizontal, 4)
                
                // List of Events
                VStack(spacing: 10) {
                    ForEach(entry.upcomingEvents.prefix(4)) { event in
                        HStack(alignment: .center, spacing: 12) {
                            // Time Column
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(event.isAllDay ?? false ? "All Day" : event.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                Text(formatCompactDate(for: event))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 65, alignment: .trailing)
                            
                            // Color Indicator
                            Capsule()
                                .fill(event.color)
                                .frame(width: 4, height: 32)
                            
                            // Event Details
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(event.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text(event.startDate > Date() ? "• IN " : "• STARTED ")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(primaryColor)
                                    + Text(event.startDate, style: .relative)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(primaryColor.opacity(0.8))
                                }
                                
                                if let location = event.location, !location.isEmpty {
                                    Text(location)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
                
                Spacer()
                
            } else {
                emptyStateView
            }
        }
        .padding(16)
    }
    
    // MARK: - Shared Empty State
    var emptyStateView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(secondaryColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(secondaryColor)
            }
            
            VStack(spacing: 4) {
                Text("All Clear")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("No events scheduled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // MARK: - Helpers
    private func formatEventDate(for event: WidgetEvent, abbreviated: Bool = true) -> String {
        let calendar = Calendar.current
        if !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            // Multi-day event - show full date range
            // For all-day events, the end date is usually the start of the next day.
            // So we should subtract a second to get the actual last day of the event.
            let actualEndDate = event.endDate.addingTimeInterval(-1)
            
            if abbreviated {
                // e.g., "Sat Dec 7 - Sun Dec 8"
                let startFormatted = event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                let endFormatted = actualEndDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                return "\(startFormatted) - \(endFormatted)"
            } else {
                // e.g., "Saturday Dec 7 - Sunday Dec 8"
                let startFormatted = event.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                let endFormatted = actualEndDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                return "\(startFormatted) - \(endFormatted)"
            }
        }
        
        // Single day event - show day name and date
        if abbreviated {
            // e.g., "Sat Dec 7"
            return event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        } else {
            // e.g., "Saturday Dec 7"
            return event.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
    
    /// Compact date format for large widget list view (narrower column)
    private func formatCompactDate(for event: WidgetEvent) -> String {
        let calendar = Calendar.current
        if !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            // Multi-day event - show compact range like "18-19 Dec"
            let actualEndDate = event.endDate.addingTimeInterval(-1)
            let startDay = event.startDate.formatted(.dateTime.day())
            let endDay = actualEndDate.formatted(.dateTime.day())
            let month = actualEndDate.formatted(.dateTime.month(.abbreviated))
            return "\(startDay)-\(endDay) \(month)"
        }
        
        // Single day - show "Wed 3 Dec"
        return event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
