//
//  ContentView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var calendarManager: CalendarSyncManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var appIssueAlertService = AppIssueAlertService()
    @State private var selectedTab: Int = 0
    @State private var startAIWithVoice: Bool = false
    @State private var appIssueAlertDetail: AppIssueAlert?

    init(calendarManager: CalendarSyncManager) {
        _calendarManager = ObservedObject(initialValue: calendarManager)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(calendarManager: calendarManager))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0:
                    GroupDashboardView(viewModel: viewModel)
                case 1:
                    CalendarRootView(viewModel: viewModel)
                case 2:
                    AIAssistantView(
                        dashboardViewModel: viewModel,
                        calendarManager: calendarManager,
                        startWithVoice: startAIWithVoice,
                        userAvatarURL: profileViewModel.avatarURL
                    )
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

            FloatingTabBar(selectedTab: $selectedTab, avatarURL: profileViewModel.avatarURL)
                .environmentObject(themeManager)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if let alert = appIssueAlertService.currentAlert {
                        AppIssueBanner(alert: alert) {
                            appIssueAlertDetail = alert
                        } onDismiss: {
                            appIssueAlertService.dismissCurrentAlert()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, max(8, resolvedTopSafeInset(proxyTopInset: proxy.safeAreaInsets.top) + 6))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: appIssueAlertService.currentAlert?.displayInstanceKey)
        .sheet(item: $appIssueAlertDetail) { alert in
            AppIssueAlertDetailSheet(alert: alert)
        }
        .task {
            await loadTheme()
            // Initialize locale for date formatting in notifications
            await initializeLocale()
            // Load user profile to get avatar
            await profileViewModel.loadUserProfile()
            await appIssueAlertService.start()
        }
        .onDisappear {
            Task { await appIssueAlertService.stop() }
        }
        .onChange(of: authVM.phase) { _, phase in
            Task {
                if phase == .authenticated {
                    await appIssueAlertService.start()
                } else {
                    await appIssueAlertService.stop()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEvent"))) { notification in
            let eventId: UUID? = {
                if let uuid = notification.userInfo?["eventId"] as? UUID {
                    return uuid
                }
                if let value = notification.userInfo?["eventId"] as? String {
                    return UUID(uuidString: value)
                }
                return nil
            }()
            if let eventId {
                // Persist this so CalendarRootView can route to details even if
                // it mounts after this notification is posted.
                UserDefaults.standard.set(eventId.uuidString, forKey: "PendingNavigationEventId")
            }

            // Switch to calendar tab (index 1) when notification is tapped.
            // The detail routing is handled by CalendarRootView once it appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.selectedTab = 1
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

    private func resolvedTopSafeInset(proxyTopInset: CGFloat) -> CGFloat {
        #if os(iOS)
        if proxyTopInset > 0 {
            return proxyTopInset
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
        #else
        return proxyTopInset
        #endif
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
    
    private func initializeLocale() async {
        do {
            if let session = try? await SupabaseManager.shared.client.auth.session {
                let uid = session.user.id
                // Update locale if device locale has changed
                try await LocalePreferencesManager.shared.updateIfNeeded(for: uid)
            }
        } catch {
            #if DEBUG
            print("⚠️ Could not initialize locale: \(error)")
            #endif
            // Non-critical error, continue without locale update
        }
    }
}

private struct AppIssueAlertDetailSheet: View {
    let alert: AppIssueAlert
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: iconName)
                            .foregroundStyle(accentColor)
                            .font(.system(size: 18, weight: .semibold))
                        Text(alert.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text(alert.message)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let startsAt = alert.startsAt {
                        detailRow(title: "Starts", value: startsAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let endsAt = alert.endsAt {
                        detailRow(title: "Ends", value: endsAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Issue Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var iconName: String {
        switch alert.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "bolt.horizontal.circle.fill"
        }
    }

    private var accentColor: Color {
        switch alert.severity {
        case .info: return .blue
        case .warning: return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .critical: return .red
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
