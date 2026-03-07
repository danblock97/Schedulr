import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingThemePicker = false
    @State private var sectionsAppeared = false
    
    private var currentThemeName: String {
        if case .preset = themeManager.currentTheme.type,
           let name = themeManager.currentTheme.name,
           let preset = PresetTheme(rawValue: name) {
            return preset.displayName
        }
        return "Custom"
    }

    private var notificationGroups: [NotificationGroup] {
        [
            NotificationGroup(
                title: "Event Notifications",
                subtitle: "Updates, cancellations, RSVPs, and reminders",
                keyPaths: [
                    \.notifyEventUpdates,
                    \.notifyEventCancellations,
                    \.notifyRsvpResponses,
                    \.notifyEventReminders
                ]
            ),
            NotificationGroup(
                title: "Group Notifications",
                subtitle: "Membership, ownership, and group changes",
                keyPaths: [
                    \.notifyNewGroupMembers,
                    \.notifyGroupMemberLeft,
                    \.notifyGroupOwnershipTransfer,
                    \.notifyGroupRenamed,
                    \.notifyGroupDeleted
                ]
            ),
            NotificationGroup(
                title: "Subscription Notifications",
                subtitle: "Plan changes and limit warnings",
                keyPaths: [
                    \.notifySubscriptionChanges,
                    \.notifyFeatureLimitWarnings
                ]
            ),
            NotificationGroup(
                title: "Engagement Nudges",
                subtitle: "Gentle reminders to stay active",
                keyPaths: [
                    \.notifyEmptyWeekNudges,
                    \.notifyGroupQuietPings,
                    \.notifyAIAssistFollowups
                ]
            )
        ]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                SettingsAnimatedBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Notification Preferences Section
                        notificationPreferencesSection
                        
                        // Calendar Preferences Section
                        calendarPreferencesSection
                        
                        // Widgets Section
                        widgetsSection

                        // AI Communication Section
                        aiCommunicationSection
                        
                        // Appearance Section
                        appearanceSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .offset(y: sectionsAppeared ? 0 : 20)
                    .opacity(sectionsAppeared ? 1 : 0)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await viewModel.loadSettings()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    sectionsAppeared = true
                }
            }
            .sheet(isPresented: $showingThemePicker) {
                ThemePickerView(themeManager: themeManager) { selectedTheme in
                    Task {
                        await viewModel.saveTheme(selectedTheme)
                    }
                }
            }
        }
    }
    
    // MARK: - Notification Preferences Section
    
    private var notificationPreferencesSection: some View {
        SettingsSectionCard(title: "Notifications", icon: "bell.fill") {
            VStack(spacing: 18) {
                // Event Reminder Timing Picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("Event Reminder Timing")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Picker("Reminder Timing", selection: $viewModel.selectedReminderTiming) {
                        ForEach(ReminderTiming.allCases) { timing in
                            Text(timing.displayName).tag(timing)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(themeManager.primaryColor)
                    .onChange(of: viewModel.selectedReminderTiming) { _, newValue in
                        viewModel.updateReminderTiming(newValue)
                    }
                }
                .padding(.bottom, 8)
                
                Divider().opacity(0.5)

                VStack(spacing: 14) {
                    ForEach(Array(notificationGroups.enumerated()), id: \.offset) { index, group in
                        SettingsGroupToggleRow(
                            title: group.title,
                            subtitle: group.subtitle,
                            isOn: Binding(
                                get: {
                                    group.keyPaths.allSatisfy { viewModel.notificationPrefs[keyPath: $0] }
                                },
                                set: { newValue in
                                    viewModel.updateNotificationPreferences(group.keyPaths, value: newValue)
                                }
                            )
                        )

                        if index < notificationGroups.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar Preferences Section
    
    private var calendarPreferencesSection: some View {
        SettingsSectionCard(title: "Calendar", icon: "calendar") {
            VStack(spacing: 14) {
                SettingsToggleRow(
                    title: "Hide public holidays",
                    subtitle: "Filters calendars such as UK bank holidays",
                    isOn: Binding(
                        get: { viewModel.calendarPrefs.hideHolidays },
                        set: { newVal in
                            viewModel.calendarPrefs.hideHolidays = newVal
                            Task { await viewModel.saveCalendarPrefs() }
                        }
                    )
                )
                
                Divider().opacity(0.5)
                
                SettingsToggleRow(
                    title: "Deduplicate all‑day events",
                    subtitle: "Combines same‑title events into one row",
                    isOn: Binding(
                        get: { viewModel.calendarPrefs.dedupAllDay },
                        set: { newVal in
                            viewModel.calendarPrefs.dedupAllDay = newVal
                            Task { await viewModel.saveCalendarPrefs() }
                        }
                    )
                )
            }
        }
    }
    
    // MARK: - Widgets Section
    
    private var widgetsSection: some View {
        SettingsSectionCard(title: "Widgets", icon: "square.grid.2x2.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Display Mode")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Picker("Widget Display Mode", selection: $viewModel.widgetDisplayMode) {
                    ForEach(WidgetDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(themeManager.primaryColor)
                .onChange(of: viewModel.widgetDisplayMode) { _, newValue in
                    viewModel.updateWidgetDisplayMode(newValue)
                }
                
                Text("Choose how widgets display upcoming events. Rolling mode rotates through events every 10 minutes. Next Up Only shows just the next event.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
        }
    }
    
    // MARK: - Appearance Section

    private var aiCustomNoteBinding: Binding<String> {
        Binding(
            get: { viewModel.aiCommunicationPrefs.customNote ?? "" },
            set: { newValue in
                viewModel.aiCommunicationPrefs.customNote = newValue
                viewModel.markAICommunicationPrefsDirty()
            }
        )
    }

    private var aiCommunicationSection: some View {
        SettingsSectionCard(title: "AI Communication", icon: "text.bubble.fill") {
            if subscriptionManager.isPro {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tone")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Picker("Tone", selection: $viewModel.aiCommunicationPrefs.tone) {
                            ForEach(AIResponseTone.allCases) { tone in
                                Text(tone.displayName).tag(tone)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(themeManager.primaryColor)
                        .onChange(of: viewModel.aiCommunicationPrefs.tone) { _, _ in
                            viewModel.markAICommunicationPrefsDirty()
                        }
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Response Style")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Picker("Response Style", selection: $viewModel.aiCommunicationPrefs.communicationStyle) {
                            ForEach(AIResponseStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.aiCommunicationPrefs.communicationStyle) { _, _ in
                            viewModel.markAICommunicationPrefsDirty()
                        }
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Formality")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Picker("Formality", selection: $viewModel.aiCommunicationPrefs.formality) {
                            ForEach(AIResponseFormality.allCases) { formality in
                                Text(formality.displayName).tag(formality)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.aiCommunicationPrefs.formality) { _, _ in
                            viewModel.markAICommunicationPrefsDirty()
                        }
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Personality Traits")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        ForEach(AIPersonalityTrait.allCases) { trait in
                            SettingsToggleRow(
                                title: trait.displayName,
                                subtitle: "Presentation only",
                                isOn: Binding(
                                    get: { viewModel.aiCommunicationPrefs.personalityTraits.contains(trait) },
                                    set: { newValue in
                                        let isEnabled = viewModel.aiCommunicationPrefs.personalityTraits.contains(trait)
                                        if newValue != isEnabled {
                                            viewModel.toggleAICommunicationTrait(trait)
                                        }
                                    }
                                )
                            )
                        }

                        Text("Choose up to \(AICommunicationPreferences.maxPersonalityTraits). These only affect phrasing and tone.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Optional Style Note")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                        TextField("Example: Keep replies calm and succinct.", text: aiCustomNoteBinding, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.systemBackground).opacity(colorScheme == .dark ? 0.35 : 0.8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                        Text("\((viewModel.aiCommunicationPrefs.customNote ?? "").count)/\(AICommunicationPreferences.maxCustomNoteLength)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    if let errorMessage = viewModel.aiCommunicationErrorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.red)
                    }

                    if let successMessage = viewModel.aiCommunicationSuccessMessage, !successMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(successMessage)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Reset") {
                            Task {
                                await viewModel.resetAICommunicationPrefs()
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            Task {
                                await viewModel.saveAICommunicationPrefs()
                            }
                        } label: {
                            Text(viewModel.isSaving ? "Saving..." : "Save Preferences")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(themeManager.gradient, in: Capsule())
                        }
                        .disabled(viewModel.isSaving)
                        .opacity(viewModel.isSaving ? 0.7 : 1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom AI tone and personality is a Pro feature.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Pro members can choose tone, formality, communication style, and a tightly validated style note.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSectionCard(title: "Appearance", icon: "paintpalette.fill") {
            Button {
                showingThemePicker = true
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor,
                                    themeManager.secondaryColor
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Theme")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(currentThemeName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            

        }
    }
}

// MARK: - Settings Section Card

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.gradient)
                
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: "1a1a2e").opacity(0.7) : Color.white.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .tint(themeManager.primaryColor)
        .padding(.vertical, 6)
    }
}

// MARK: - Notification Group Model

private struct NotificationGroup {
    let title: String
    let subtitle: String
    let keyPaths: [WritableKeyPath<NotificationPreferences, Bool>]
}

// MARK: - Settings Group Toggle Row

private struct SettingsGroupToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .tint(themeManager.primaryColor)
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Animated Background

private struct SettingsAnimatedBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "0a0a0f"), Color(hex: "1a1a2e")]
                    : [Color(hex: "f8f9fa"), Color(hex: "e9ecef")],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle accent orbs
            GeometryReader { geometry in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                themeManager.primaryColor.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.2)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                themeManager.secondaryColor.opacity(colorScheme == .dark ? 0.06 : 0.04),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 250
                        )
                    )
                    .frame(width: 500, height: 500)
                    .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.7)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeManager.shared)
}
