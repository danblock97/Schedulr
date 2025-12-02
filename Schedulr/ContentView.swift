//
//  ContentView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var calendarManager: CalendarSyncManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedTab: Int = 0
    @State private var startAIWithVoice: Bool = false

    init(calendarManager: CalendarSyncManager) {
        _calendarManager = ObservedObject(initialValue: calendarManager)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(calendarManager: calendarManager))
    }

    var body: some View {
        ZStack {
            // Main content area
            Group {
                switch selectedTab {
                case 0:
                    GroupDashboardView(viewModel: viewModel)
                case 1:
                    CalendarRootView(viewModel: viewModel)
                case 2:
                    AIAssistantView(dashboardViewModel: viewModel, calendarManager: calendarManager, startWithVoice: startAIWithVoice)
                        .onAppear {
                            // Reset voice flag after use
                            if startAIWithVoice {
                                startAIWithVoice = false
                            }
                        }
                case 3:
                    ProfileView(viewModel: profileViewModel)
                        .environmentObject(authVM)
                        .environmentObject(calendarManager)
                default:
                    GroupDashboardView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(themeManager)

            // Tab bar - edge to edge at bottom
            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab, avatarURL: profileViewModel.avatarURL)
                    .environmentObject(themeManager)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .task {
            await loadTheme()
            // Load user profile to get avatar
            await profileViewModel.loadUserProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEvent"))) { notification in
            if let eventId = notification.userInfo?["eventId"] as? UUID {
                // Switch to calendar tab (index 1) when notification is tapped
                // Use a longer delay when app is launching from background to ensure views are ready
                // This is especially important when app launches from a cold start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.selectedTab = 1
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToAIChat"))) { notification in
            let withVoice = notification.userInfo?["voice"] as? Bool ?? false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.startAIWithVoice = withVoice
                self.selectedTab = 2
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToGroup"))) { notification in
            // Switch to dashboard/groups tab (index 0) for group-related notifications
            // The groupId can be used by GroupDashboardView to highlight/scroll to the specific group
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.selectedTab = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToProfile"))) { notification in
            // Switch to profile tab (index 3) for subscription/account notifications
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.selectedTab = 3
            }
        }
    }
    
    private func loadTheme() async {
        do {
            if let session = try? await SupabaseManager.shared.client.auth.session {
                let uid = session.user.id
                let theme = try await ThemePreferencesManager.shared.load(for: uid)
                await MainActor.run {
                    themeManager.setTheme(theme)
                }
            }
        } catch {
            print("⚠️ Could not load theme: \(error)")
            // Use default theme (already set in ThemeManager.shared)
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 72, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                        .padding()
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )

                    VStack(spacing: 12) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(message)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .padding(.bottom, 100) // Space for floating tab bar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    return ContentView(calendarManager: calendarManager)
        .environmentObject(AuthViewModel())
        .environmentObject(calendarManager)
}
