//
//  UpNextWidget.swift
//  Schedulr
//
//  Created by Daniel Block on 24/11/2025.
//

import WidgetKit
import SwiftUI

// Note: This enum is duplicated in WidgetDataEncoder.swift for the main app target
// Both definitions must match exactly for UserDefaults compatibility
enum WidgetDisplayMode: String, Codable, CaseIterable {
    case rolling = "rolling"
    case staticNextUp = "static"
    
    var displayName: String {
        switch self {
        case .rolling: return "Rolling Events"
        case .staticNextUp: return "Next Up Only"
        }
    }
}

struct UpNextEntry: TimelineEntry {
    let date: Date
    let event: WidgetEvent? // The primary event to show (rotates)
    let upcomingEvents: [WidgetEvent] // List of next few events (for Large view)
    let theme: WidgetTheme
    let displayMode: WidgetDisplayMode
}

struct WidgetTheme {
    let primary: Color
    let secondary: Color
}

struct WidgetEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let colorData: Data
    let calendarTitle: String
    let isAllDay: Bool?
    
    var color: Color {
        if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            return Color(uiColor)
        }
        return .blue
    }
}

struct UpNextProvider: TimelineProvider {
    // IMPORTANT: Must match the App Group ID used in the main app
    let appGroupId = "group.uk.co.schedulr.Schedulr"
    let dataKey = "upcoming_widget_events"
    let themeKey = "widget_theme_colors"
    let displayModeKey = "widget_display_mode"
    
    func placeholder(in context: Context) -> UpNextEntry {
        let sampleEvent = WidgetEvent(
            id: "preview",
            title: "Team Sync",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(7200),
            location: "Conference Room A",
            colorData: (try? NSKeyedArchiver.archivedData(withRootObject: UIColor.systemPurple, requiringSecureCoding: false)) ?? Data(),
            calendarTitle: "Work",
            isAllDay: false
        )
        return UpNextEntry(
            date: Date(),
            event: sampleEvent,
            upcomingEvents: [sampleEvent],
            theme: WidgetTheme(primary: Color(red: 0.85, green: 0.45, blue: 0.65), secondary: Color(red: 0.65, green: 0.55, blue: 0.80)),
            displayMode: .rolling
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> ()) {
        let entry = placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> ()) {
        let now = Date()
        let calendar = Calendar.current
        var widgetEvents: [WidgetEvent] = []
        var theme = WidgetTheme(primary: Color(red: 0.85, green: 0.45, blue: 0.65), secondary: Color(red: 0.65, green: 0.55, blue: 0.80)) // Default Pink & Purple
        
        // Calculate the lookahead window (30 days from now)
        // This ensures users see upcoming events regardless of month boundaries
        // Fallback to distant future if date calculation fails, so we show all future events rather than none
        let lookaheadEnd = calendar.date(byAdding: .day, value: 30, to: now) ?? Date.distantFuture
        
        // Read from Shared UserDefaults
        var displayMode: WidgetDisplayMode = .rolling // Default to rolling
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            // Read Events
            if let data = userDefaults.data(forKey: dataKey),
               let decodedEvents = try? JSONDecoder().decode([WidgetEvent].self, from: data) {
                // Filter: only current/future events within the next 30 days
                widgetEvents = decodedEvents
                    .filter { event in
                        // Event must not have ended yet
                        guard event.endDate > now else { return false }
                        // Event must start within the lookahead window
                        guard event.startDate < lookaheadEnd else { return false }
                        return true
                    }
                    .sorted { lhs, rhs in
                        if lhs.startDate == rhs.startDate {
                            return lhs.endDate < rhs.endDate
                        }
                        return lhs.startDate < rhs.startDate
                }
            }
            
            // Read Theme
            struct WidgetThemeColors: Codable {
                let primaryData: Data
                let secondaryData: Data
            }
            
            if let themeData = userDefaults.data(forKey: themeKey),
               let decodedTheme = try? JSONDecoder().decode(WidgetThemeColors.self, from: themeData) {
                
                let primaryUi = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: decodedTheme.primaryData)) ?? UIColor.systemPink
                let secondaryUi = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: decodedTheme.secondaryData)) ?? UIColor.systemPurple
                
                theme = WidgetTheme(primary: Color(primaryUi), secondary: Color(secondaryUi))
            }
            
            // Read Display Mode
            if let modeString = userDefaults.string(forKey: displayModeKey),
               let mode = WidgetDisplayMode(rawValue: modeString) {
                displayMode = mode
            }
        }
        
        var entries: [UpNextEntry] = []
        
        // For Large widget, we always pass the top 4 events
        let listEvents = Array(widgetEvents.prefix(4))
        
        // If no events, just one entry
        if widgetEvents.isEmpty {
            let entry = UpNextEntry(date: now, event: nil, upcomingEvents: [], theme: theme, displayMode: displayMode)
            let timeline = Timeline(entries: [entry], policy: .after(now.addingTimeInterval(900))) // Retry in 15 mins
            completion(timeline)
            return
        }
        
        // Handle display mode
        switch displayMode {
        case .staticNextUp:
            // Static mode: show only the next event, no rotation
            let nextEvent = widgetEvents.first
            let entry = UpNextEntry(
                date: now,
                event: nextEvent,
                upcomingEvents: listEvents,
                theme: theme,
                displayMode: displayMode
            )
            // Refresh in 1 hour or when the event ends, whichever comes first
            let refreshDate = min(
                calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600),
                nextEvent?.endDate ?? now.addingTimeInterval(3600)
            )
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
            return
            
        case .rolling:
            // Rolling mode: rotate through all upcoming events (next 30 days) every 10 minutes.
            let rotationInterval: TimeInterval = 10 * 60 // 10 minutes
            let timelineDuration: TimeInterval = 24 * 60 * 60 // Build 24 hours; system requests a new timeline at end.
            let rotationEvents = widgetEvents
            
            for offset in stride(from: 0, to: timelineDuration, by: rotationInterval) {
                let entryDate = now.addingTimeInterval(offset)
                
                // Use a time-based index so rotation continues smoothly across timeline refreshes.
                let slot = Int(floor(entryDate.timeIntervalSinceReferenceDate / rotationInterval))
                let index = ((slot % rotationEvents.count) + rotationEvents.count) % rotationEvents.count
                let rotatedEvent = rotationEvents[index]
                
                let entry = UpNextEntry(
                    date: entryDate,
                    event: rotatedEvent,
                    upcomingEvents: listEvents,
                    theme: theme,
                    displayMode: displayMode
                )
                entries.append(entry)
            }
            
            let timeline = Timeline(entries: entries, policy: .atEnd)
            completion(timeline)
        }
    }
}

struct UpNextWidget: Widget {
    let kind: String = "UpNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("See your next upcoming event at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
