import SwiftUI
import PhotosUI
import Supabase
import Auth

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var calendarManager: CalendarSyncManager
    @State private var isEditingName = false
    @State private var tempDisplayName = ""
    @State private var calendarPrefs = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
    @State private var isLoadingPrefs = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var aiUsageInfo: AIUsageInfo?
    @State private var groupLimitInfo: (current: Int, max: Int)?

    var body: some View {
        NavigationStack {
            ZStack {
                // Bubbly background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                BubblyProfileBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Avatar Section
                        VStack(spacing: 16) {
                            ZStack {
                                if let avatarURL = viewModel.avatarURL, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 4
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Text(viewModel.displayName.prefix(1).uppercased())
                                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                                }

                                // Camera button overlay
                                PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 16))
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
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                                }
                                .offset(x: 40, y: 40)
                            }

                            Text("✨ Tap to change")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)

                        // Name Section
                        VStack(spacing: 12) {
                            if isEditingName {
                                VStack(spacing: 12) {
                                    TextField("Display Name", text: $tempDisplayName)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .padding()
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    HStack(spacing: 12) {
                                        Button {
                                            isEditingName = false
                                            tempDisplayName = viewModel.displayName
                                        } label: {
                                            Text("Cancel")
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }

                                        Button {
                                            viewModel.displayName = tempDisplayName
                                            Task {
                                                await viewModel.updateDisplayName()
                                                isEditingName = false
                                            }
                                        } label: {
                                            Text("Save")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding()
                                                .background(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.98, green: 0.29, blue: 0.55),
                                                            Color(red: 0.58, green: 0.41, blue: 0.87)
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 12, x: 0, y: 6)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                Button {
                                    tempDisplayName = viewModel.displayName
                                    isEditingName = true
                                } label: {
                                    HStack {
                                        Text(viewModel.displayName.isEmpty ? "Set your name" : viewModel.displayName)
                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                            .foregroundColor(.primary)

                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 20))
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
                                    }
                                }
                            }
                        }

                        // Subscription Section
                        subscriptionSection

                        // Groups Section
                        if !viewModel.userGroups.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("👥 Your Groups")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal)

                                VStack(spacing: 12) {
                                    ForEach(viewModel.userGroups) { group in
                                        GroupCard(group: group) {
                                            viewModel.groupToLeave = group
                                            viewModel.showingLeaveGroupConfirmation = true
                                        }
                                    }
                                }
                            }
                        }

                        // Calendar Preferences Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("📅 Calendar Preferences")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal)

                            VStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle("Hide holidays & birthdays", isOn: Binding(
                                    get: { calendarPrefs.hideHolidays },
                                    set: { newVal in
                                        calendarPrefs.hideHolidays = newVal
                                        Task { await saveCalendarPrefs() }
                                    }
                                ))
                                    .padding(.bottom, 2)
                                    .accessibilityHint("Filters common holiday and birthday calendars from your views and dashboard")
                                    
                                    Text("Filters common holiday and birthday calendars from your Calendar and Upcoming.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle("Deduplicate identical all‑day events", isOn: Binding(
                                    get: { calendarPrefs.dedupAllDay },
                                    set: { newVal in
                                        calendarPrefs.dedupAllDay = newVal
                                        Task { await saveCalendarPrefs() }
                                    }
                                ))
                                    .padding(.bottom, 2)
                                    .accessibilityHint("Combines same-title all-day events on a day into one row with a shared count")

                                    Text("Combines same‑title all‑day events on a day into one row with a shared count.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .padding(.horizontal)
                        }

                        // Action Buttons Section
                        VStack(spacing: 12) {
                            // Sign Out Button
                            Button {
                                Task {
                                    await authViewModel.signOut()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Sign Out")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                            }

                            // Delete Account Button
                            Button {
                                viewModel.showingDeleteAccountConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Delete Account")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        // Error Message
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.red)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100) // Space for floating tab bar
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .alert("Leave Group", isPresented: $viewModel.showingLeaveGroupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    if let group = viewModel.groupToLeave {
                        Task {
                            await viewModel.leaveGroup(group)
                            // Clear cached calendar events from the group we left
                            calendarManager.clearGroupEvents()
                        }
                    }
                }
            } message: {
                if let group = viewModel.groupToLeave {
                    Text("Are you sure you want to leave \"\(group.name)\"? You'll need a new invite to rejoin.")
                }
            }
            .alert("Delete Account", isPresented: $viewModel.showingDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Forever", role: .destructive) {
                    Task {
                        let success = await viewModel.deleteAccount()
                        if success {
                            await authViewModel.signOut()
                        }
                    }
                }
            } message: {
                Text("⚠️ This action cannot be undone!\n\nDeleting your account will:\n• Remove you from all groups\n• Delete all your data\n• Sign you out permanently")
            }
            .task {
                await viewModel.loadUserProfile()
                await loadCalendarPrefs()
                await loadSubscriptionInfo()
            }
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task {
                    await viewModel.uploadAvatar()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .refreshable {
                await SubscriptionManager.shared.fetchSubscriptionStatus()
                await loadSubscriptionInfo()
            }
            .onChange(of: subscriptionManager.currentTier) { _, _ in
                Task {
                    await loadSubscriptionInfo()
                }
            }
        }
    }
    
    // MARK: - Subscription Section
    
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💎 Subscription")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                HStack {
                    SubscriptionBadge(tier: subscriptionManager.currentTier)
                    
                    Spacer()
                    
                    if subscriptionManager.currentTier == .free {
                        Button(action: { showPaywall = true }) {
                            Text("Upgrade")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                }
                
                // Grace period warning
                if subscriptionManager.isInGracePeriod {
                    GracePeriodWarningView()
                }
                
                // Usage stats
                if let groupLimitInfo = groupLimitInfo {
                    UsageStatRow(
                        icon: "person.3.fill",
                        title: "Groups",
                        current: groupLimitInfo.current,
                        max: groupLimitInfo.max
                    )
                }
                
                if subscriptionManager.currentTier == .pro,
                   let aiUsage = aiUsageInfo {
                    UsageStatRow(
                        icon: "sparkles",
                        title: "AI Requests",
                        current: aiUsage.requestCount,
                        max: aiUsage.maxRequests
                    )
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper
    
    private func loadSubscriptionInfo() async {
        // Load usage info
        groupLimitInfo = await SubscriptionLimitService.shared.getGroupLimitInfo()
        
        if subscriptionManager.currentTier == .pro {
            aiUsageInfo = await SubscriptionLimitService.shared.getAIUsageInfo()
        } else {
            aiUsageInfo = nil
        }
    }
}

// MARK: - Usage Stat Row

private struct UsageStatRow: View {
    let icon: String
    let title: String
    let current: Int
    let max: Int
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.58, green: 0.41, blue: 0.87))
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(current) / \(max)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(current >= max ? .red : .secondary)
        }
    }
}

// MARK: - Grace Period Warning

private struct GracePeriodWarningView: View {
    @State private var daysRemaining: Int?
    
    var body: some View {
        Group {
            if let days = daysRemaining {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Grace period: \(days) day\(days == 1 ? "" : "s") remaining")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .task {
            self.daysRemaining = await GracePeriodManager.shared.getDaysRemaining()
        }
    }
}

// MARK: - Supporting Views

struct GroupCard: View {
    let group: ProfileViewModel.GroupMembership
    let onLeave: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if let role = group.role {
                    Text(role == "owner" ? "👑 Owner" : "✨ Member")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if group.role != "owner" {
                Button(action: onLeave) {
                    Text("Leave")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

struct BubblyProfileBackground: View {
    var body: some View {
        ZStack {
            // Large pink bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.15),
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -250)
                .blur(radius: 40)

            // Purple bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.15),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 250, height: 250)
                .offset(x: 120, y: 100)
                .blur(radius: 40)

            // Blue bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.12),
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.03)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 150
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: -80, y: 400)
                .blur(radius: 35)

            // Small decorative bubbles
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 60, height: 60)
                .offset(x: 140, y: -180)
                .blur(radius: 10)

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 40, height: 40)
                .offset(x: -130, y: 50)
                .blur(radius: 8)
        }
    }
}

// MARK: - Calendar Prefs IO
extension ProfileView {
    private func loadCalendarPrefs() async {
        guard !isLoadingPrefs else { return }
        isLoadingPrefs = true
        defer { isLoadingPrefs = false }
        if let uid = try? await SupabaseManager.shared.client.auth.session.user.id {
            if let prefs = try? await CalendarPreferencesManager.shared.load(for: uid) {
                calendarPrefs = prefs
            }
        }
    }

    private func saveCalendarPrefs() async {
        if let uid = try? await SupabaseManager.shared.client.auth.session.user.id {
            try? await CalendarPreferencesManager.shared.save(calendarPrefs, for: uid)
        }
    }
}
