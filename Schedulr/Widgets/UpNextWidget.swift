//
//  UpNextWidget.swift
//  Schedulr
//
//  Created by Daniel Block on 24/11/2025.
//

import WidgetKit
import SwiftUI

struct UpNextEntry: TimelineEntry {
    let date: Date
    let event: WidgetEvent? // The primary event to show (rotates)
    let upcomingEvents: [WidgetEvent] // List of next few events (for Large view)
    let theme: WidgetTheme
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
            theme: WidgetTheme(primary: Color(red: 0.85, green: 0.45, blue: 0.65), secondary: Color(red: 0.65, green: 0.55, blue: 0.80))
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
        
        // Calculate the end of the current month using proper Calendar date arithmetic
        // This correctly handles year wraparound (e.g., December -> January)
        let endOfMonth: Date
        if let monthInterval = calendar.dateInterval(of: .month, for: now) {
            endOfMonth = monthInterval.end
        } else {
            // Fallback: add 1 month to start of current month
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
        }
        
        // Read from Shared UserDefaults
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            // Read Events
            if let data = userDefaults.data(forKey: dataKey),
               let decodedEvents = try? JSONDecoder().decode([WidgetEvent].self, from: data) {
                // Filter: only current/future events within the current month
                widgetEvents = decodedEvents.filter { event in
                    // Event must not have ended yet
                    guard event.endDate > now else { return false }
                    // Event must start before end of current month
                    guard event.startDate < endOfMonth else { return false }
                    return true
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
        }
        
        var entries: [UpNextEntry] = []
        
        // Create a timeline that rotates through the top 3 events every 10 minutes
        // We generate entries for the next 2 hours
        let rotationInterval: TimeInterval = 10 * 60 // 10 minutes
        let timelineDuration: TimeInterval = 2 * 60 * 60 // 2 hours
        
        // If no events, just one entry
        if widgetEvents.isEmpty {
            let entry = UpNextEntry(date: now, event: nil, upcomingEvents: [], theme: theme)
            let timeline = Timeline(entries: [entry], policy: .after(now.addingTimeInterval(900))) // Retry in 15 mins
            completion(timeline)
            return
        }
        
        let topEvents = Array(widgetEvents.prefix(3)) // Take top 3 for rotation
        
        for offset in stride(from: 0, to: timelineDuration, by: rotationInterval) {
            let entryDate = now.addingTimeInterval(offset)
            
            // Determine which event to show based on the rotation index
            let index = Int(offset / rotationInterval) % topEvents.count
            let rotatedEvent = topEvents[index]
            
            // For Large widget, we always pass the top 4 events
            let listEvents = Array(widgetEvents.prefix(4))
            
            let entry = UpNextEntry(
                date: entryDate,
                event: rotatedEvent,
                upcomingEvents: listEvents,
                theme: theme
            )
            entries.append(entry)
        }
        
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
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
