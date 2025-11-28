//
//  WidgetDataEncoder.swift
//  Schedulr
//
//  Created by Daniel Block on 24/11/2025.
//

import Foundation
import SwiftUI

/// Helper to share data between the main app and widget extension via App Groups
struct WidgetDataEncoder {
    static let shared = WidgetDataEncoder()
    
    // IMPORTANT: This must match the App Group ID you configure in Xcode
    // Format: group.uk.co.schedulr.Schedulr (or similar)
    // Since I don't know the exact bundle ID prefix, I'll use a standard convention.
    // The user will need to verify this matches their App Group.
    let appGroupId = "group.uk.co.schedulr.Schedulr"
    let dataKey = "upcoming_widget_events"
    
    private init() {}
    
    struct SharedEvent: Codable, Identifiable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let colorData: Data // Store color as Data (archived UIColor/Color)
        let calendarTitle: String
        let isAllDay: Bool
        
        var color: Color {
            if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return Color(uiColor)
            }
            return .blue
        }
    }
    
    func saveEvents(_ events: [CalendarEventWithUser]) {
        // Convert to SharedEvent
        let sharedEvents = events.prefix(10).map { event in
            // Convert ColorComponents to UIColor data
            let uiColor: UIColor
            if let cc = event.calendar_color {
                uiColor = UIColor(red: cc.red, green: cc.green, blue: cc.blue, alpha: cc.alpha)
            } else {
                uiColor = .systemBlue
            }
            
            let colorData = (try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false)) ?? Data()
            
            return SharedEvent(
                id: event.id.uuidString,
                title: event.title,
                startDate: event.start_date,
                endDate: event.end_date,
                location: event.location,
                colorData: colorData,
                calendarTitle: event.calendar_name ?? "Schedulr",
                isAllDay: event.is_all_day
            )
        }
        
        // Write to Shared UserDefaults
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            if let encoded = try? JSONEncoder().encode(sharedEvents) {
                userDefaults.set(encoded, forKey: dataKey)
                // Force widget reload
                // Note: WidgetCenter import required, but this file is in main app
                // We'll handle reload in CalendarSyncManager
            }
        } else {
            print("WARNING: Could not access App Group UserDefaults with suite name: \(appGroupId)")
        }
    }
}
