import Foundation
import SwiftUI
import Combine
import WidgetKit

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Calendar Preferences
    @Published var calendarPrefs = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
    
    // MARK: - Notification Preferences
    @Published var notificationPrefs = NotificationPreferences.default
    @Published var selectedReminderTiming: ReminderTiming = .oneDay
    
    // MARK: - Widget Preferences
    @Published var widgetDisplayMode: WidgetDisplayMode = .rolling
    
    // MARK: - Loading States
    @Published var isLoadingCalendarPrefs = false
    @Published var isLoadingNotificationPrefs = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    private var userId: UUID?
    
    // MARK: - Load All Settings
    
    func loadSettings() async {
        guard let client = SupabaseManager.shared.client else { return }
        
        do {
            let session = try await client.auth.session
            userId = session.user.id
            
            await loadCalendarPrefs()
            await loadNotificationPrefs()
            await loadWidgetDisplayMode()
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Calendar Preferences
    
    func loadCalendarPrefs() async {
        guard let userId else { return }
        isLoadingCalendarPrefs = true
        defer { isLoadingCalendarPrefs = false }
        
        do {
            calendarPrefs = try await CalendarPreferencesManager.shared.load(for: userId)
        } catch {
            #if DEBUG
            print("[SettingsViewModel] Failed to load calendar prefs: \(error)")
            #endif
        }
    }
    
    func saveCalendarPrefs() async {
        guard let userId else { return }
        
        do {
            try await CalendarPreferencesManager.shared.save(calendarPrefs, for: userId)
        } catch {
            errorMessage = "Failed to save calendar preferences"
        }
    }
    
    // MARK: - Notification Preferences
    
    func loadNotificationPrefs() async {
        guard let userId else { return }
        isLoadingNotificationPrefs = true
        defer { isLoadingNotificationPrefs = false }
        
        do {
            notificationPrefs = try await NotificationPreferencesManager.shared.load(for: userId)
            selectedReminderTiming = ReminderTiming.from(hoursValue: notificationPrefs.eventReminderHoursBefore)
        } catch {
            #if DEBUG
            print("[SettingsViewModel] Failed to load notification prefs: \(error)")
            #endif
        }
    }
    
    func saveNotificationPrefs() async {
        guard let userId else { return }
        isSaving = true
        defer { isSaving = false }
        
        do {
            // Update reminder timing from picker selection
            notificationPrefs.eventReminderHoursBefore = selectedReminderTiming.hoursValue
            try await NotificationPreferencesManager.shared.save(notificationPrefs, for: userId)
        } catch {
            errorMessage = "Failed to save notification preferences"
        }
    }
    
    func updateReminderTiming(_ timing: ReminderTiming) {
        selectedReminderTiming = timing
        Task {
            await saveNotificationPrefs()
        }
    }
    
    func toggleNotificationPreference(keyPath: WritableKeyPath<NotificationPreferences, Bool>, value: Bool) {
        notificationPrefs[keyPath: keyPath] = value
        Task {
            await saveNotificationPrefs()
        }
    }
    
    // MARK: - Theme Preferences
    
    func saveTheme(_ theme: ColorTheme) async {
        guard let userId else { return }
        
        do {
            try await ThemePreferencesManager.shared.save(theme, for: userId)
        } catch {
            errorMessage = "Failed to save theme"
        }
    }
    
    // MARK: - Widget Display Mode
    
    func loadWidgetDisplayMode() async {
        let appGroupId = "group.uk.co.schedulr.Schedulr"
        let displayModeKey = "widget_display_mode"
        
        if let userDefaults = UserDefaults(suiteName: appGroupId),
           let modeString = userDefaults.string(forKey: displayModeKey),
           let mode = WidgetDisplayMode(rawValue: modeString) {
            widgetDisplayMode = mode
        } else {
            // Default to rolling if not set
            widgetDisplayMode = .rolling
        }
    }
    
    func saveWidgetDisplayMode(_ mode: WidgetDisplayMode) async {
        let appGroupId = "group.uk.co.schedulr.Schedulr"
        let displayModeKey = "widget_display_mode"
        
        widgetDisplayMode = mode
        
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            userDefaults.set(mode.rawValue, forKey: displayModeKey)
            // Reload all widget timelines to apply the change
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func updateWidgetDisplayMode(_ mode: WidgetDisplayMode) {
        Task {
            await saveWidgetDisplayMode(mode)
        }
    }
    
    // toggleLiquidGlass removed in favor of system settings
}

