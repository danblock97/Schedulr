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
        HStack(alignment: .top) {
            Rectangle()
                .fill(schedulrPurple)
                .frame(width: 4)
                .cornerRadius(2)
            
            VStack(alignment: .leading, spacing: 2) {
                if let event = entry.event {
                    Text(event.title)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    
                    if !(event.isAllDay ?? false) {
                        Text(event.startDate, style: .time)
                            .font(.caption)
                    }
                    
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No upcoming events")
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
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryColor)
                    Text(formatEventDate(for: event, abbreviated: true))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    
                    // Pagination dots to indicate rotation
                    HStack(spacing: 3) {
                        Circle().fill(primaryColor).frame(width: 4, height: 4)
                        Circle().fill(Color.secondary.opacity(0.3)).frame(width: 4, height: 4)
                        Circle().fill(Color.secondary.opacity(0.3)).frame(width: 4, height: 4)
                    }
                }
                .padding(.bottom, 8)
                
                // Content
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .padding(.bottom, 4)
                
                Spacer()
                
                // Time
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                    if event.isAllDay ?? false {
                        Text("All Day")
                            .font(.caption)
                            .fontWeight(.medium)
                    } else {
                        Text(event.startDate, style: .time)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(.bottom, 2)
                
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                // Relative time footer
                if !(event.isAllDay ?? false) {
                    Text(event.startDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(primaryColor)
                        .padding(.top, 4)
                }
                    
            } else {
                emptyStateView
            }
        }
    }
    
    // MARK: - System Medium
    var mediumView: some View {
        HStack(spacing: 0) {
            if let event = entry.event {
                // Left side: Time & Date
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatEventDate(for: event, abbreviated: false))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(secondaryColor)
                    
                    if event.isAllDay ?? false {
                        Text("All Day")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    } else {
                        Text(event.startDate, style: .time)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    if !(event.isAllDay ?? false) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(primaryColor)
                            Text(event.startDate, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                
                // Divider
                Rectangle()
                    .fill(LinearGradient(colors: [primaryColor.opacity(0.5), secondaryColor.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2)
                    .padding(.vertical, 8)
                
                // Right side: Title & Details
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(3)
                    
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text(event.calendarTitle)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(event.color.opacity(0.2))
                        .foregroundStyle(event.color)
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                
            } else {
                emptyStateView
            }
        }
    }
    
    // MARK: - System Large
    var largeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !entry.upcomingEvents.isEmpty {
                // Large Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("Agenda")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .leading, endPoint: .trailing))
                    }
                    Spacer()
                }
                
                // List of Events
                VStack(spacing: 12) {
                    ForEach(entry.upcomingEvents.prefix(4)) { event in
                        HStack(alignment: .center, spacing: 12) {
                            // Time Column
                            VStack(alignment: .trailing) {
                                if event.isAllDay ?? false {
                                    Text("All Day")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                } else {
                                    Text(event.startDate, style: .time)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                Text(formatEventDate(for: event, abbreviated: true))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 60, alignment: .trailing)
                            
                            // Vertical Line
                            Rectangle()
                                .fill(event.color)
                                .frame(width: 4)
                                .cornerRadius(2)
                                .frame(height: 30)
                            
                            // Event Details
                            VStack(alignment: .leading) {
                                Text(event.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                
                                if let location = event.location, !location.isEmpty {
                                    Text(location)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
                
                Spacer()
                
            } else {
                emptyStateView
            }
        }
    }
    
    // MARK: - Shared Empty State
    var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(secondaryColor)
            Text("All caught up!")
                .font(.headline)
            Text("No upcoming events for the next 7 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // MARK: - Helpers
    private func formatEventDate(for event: WidgetEvent, abbreviated: Bool = true) -> String {
        let calendar = Calendar.current
        if !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            // Multi-day
            let startDay = event.startDate.formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide))
            // For all-day events, the end date is usually the start of the next day.
            // So we should subtract a second to get the actual last day of the event.
            let actualEndDate = event.endDate.addingTimeInterval(-1)
            let endDay = actualEndDate.formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide))
            
            return "\(startDay)-\(endDay)"
        }
        
        return event.startDate.formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide))
    }
}
