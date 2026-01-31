import SwiftUI
import PhotosUI
import Supabase
import Auth
#if os(iOS)
import UIKit
import SafariServices
#endif

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var calendarManager: CalendarSyncManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isEditingName = false
    @State private var tempDisplayName = ""
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingSettings = false
    @State private var showPaywall = false
    @State private var aiUsageInfo: AIUsageInfo?
    @State private var groupLimitInfo: (current: Int, max: Int)?
    @Environment(\.colorScheme) var colorScheme
    @State private var pendingAvatarImage: SelectedUIImage? = nil
    
    // Animation states
    @State private var headerAppeared = false
    @State private var sectionsAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Animated background
                ProfileAnimatedBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Profile Header Card
                        profileHeaderCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .offset(y: headerAppeared ? 0 : -30)
                            .opacity(headerAppeared ? 1 : 0)
                        
                        // Content sections
                        VStack(spacing: 16) {
                            subscriptionSection
                            groupsSection
                            settingsButtonSection
                            feedbackSection
                            actionButtonsSection
                            errorMessageView
                            versionInfoView
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 120)
                        .offset(y: sectionsAppeared ? 0 : 20)
                        .opacity(sectionsAppeared ? 1 : 0)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProfileLoadingOverlay()
                }
            }
            .alert("Leave Group", isPresented: $viewModel.showingLeaveGroupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    if let group = viewModel.groupToLeave {
                        Task {
                            await viewModel.leaveGroup(group)
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
                await loadSubscriptionInfo()
                
                // Trigger animations
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    headerAppeared = true
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15)) {
                    sectionsAppeared = true
                }
            }
            .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    await MainActor.run {
                        pendingAvatarImage = SelectedUIImage(image: image)
                    }
                }
            }
            .sheet(item: $pendingAvatarImage) { item in
                ImageRepositionerView(
                    image: item.image,
                    aspectRatio: 1,
                    cropShape: .circle,
                    outputSize: CGSize(width: 512, height: 512),
                    onCancel: {
                        pendingAvatarImage = nil
                        viewModel.selectedPhotoItem = nil
                    },
                    onConfirm: { cropped in
                        guard let data = cropped.jpegData(compressionQuality: 0.85) else { return }
                        pendingAvatarImage = nil
                        viewModel.selectedPhotoItem = nil
                        Task {
                            await viewModel.uploadAvatar(imageData: data)
                        }
                    }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $viewModel.showingRenameGroupSheet) {
                RenameGroupSheet(
                    groupName: $viewModel.newGroupName,
                    isLoading: viewModel.isLoading,
                    onCancel: {
                        viewModel.showingRenameGroupSheet = false
                        viewModel.groupToRename = nil
                        viewModel.newGroupName = ""
                    },
                    onSave: {
                        if let group = viewModel.groupToRename {
                            Task {
                                await viewModel.renameGroup(group, newName: viewModel.newGroupName)
                            }
                        }
                    }
                )
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
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
        .tabBarSafeAreaInset()
    }
    
    // MARK: - Profile Header Card
    
    private var profileHeaderCard: some View {
        VStack(spacing: 24) {
            // Avatar with edit button
            ZStack {
                // Glow ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                themeManager.primaryColor.opacity(0.4),
                                themeManager.secondaryColor.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 130, height: 130)
                    .blur(radius: 4)
                
                if let avatarURL = viewModel.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(themeManager.primaryColor)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            // Show initials fallback on error
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Text(viewModel.displayName.prefix(1).uppercased())
                                        .font(.system(size: 44, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .overlay(
                            Text(viewModel.displayName.prefix(1).uppercased())
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                }
                
                // Camera button
                PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color(hex: "1a1a2e") : .white)
                            .frame(width: 38, height: 38)
                        
                        Circle()
                            .stroke(themeManager.primaryColor.opacity(0.5), lineWidth: 2)
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                }
                .offset(x: 42, y: 42)
            }
            
            // Name section
            if isEditingName {
                nameEditView
            } else {
                nameDisplayView
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
    
    private var nameDisplayView: some View {
        Button {
            tempDisplayName = viewModel.displayName
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isEditingName = true
            }
        } label: {
            HStack(spacing: 10) {
                Text(viewModel.displayName.isEmpty ? "Set your name" : viewModel.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
    
    private var nameEditView: some View {
        VStack(spacing: 14) {
            TextField("Display Name", text: $tempDisplayName)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isEditingName = false
                        tempDisplayName = viewModel.displayName
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                Button {
                    viewModel.displayName = tempDisplayName
                    Task {
                        await viewModel.updateDisplayName()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isEditingName = false
                        }
                    }
                } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
    
    // MARK: - Subscription Section
    
    private var subscriptionSection: some View {
        ProfileSectionCard(title: "Subscription", icon: "sparkles") {
            VStack(spacing: 14) {
                HStack {
                    SubscriptionBadge(tier: subscriptionManager.currentTier)
                    
                    Spacer()
                    
                    if subscriptionManager.currentTier == .free {
                        Button(action: { showPaywall = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 14))
                                Text("Upgrade")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // Grace period warning
                if subscriptionManager.isInGracePeriod {
                    GracePeriodWarningView()
                }
                
                // Usage stats
                if let groupLimitInfo = groupLimitInfo {
                    ProfileUsageRow(
                        icon: "person.3.fill",
                        title: "Groups",
                        current: groupLimitInfo.current,
                        max: groupLimitInfo.max
                    )
                }
                
                if subscriptionManager.currentTier == .pro,
                   let aiUsage = aiUsageInfo {
                    ProfileUsageRow(
                        icon: "sparkles",
                        title: "AI Requests",
                        current: aiUsage.requestCount,
                        max: aiUsage.maxRequests
                    )
                }
            }
        }
    }
    
    // MARK: - Groups Section
    
    private var groupsSection: some View {
        Group {
            if !viewModel.userGroups.isEmpty {
                ProfileSectionCard(title: "Your Groups", icon: "person.2.fill") {
                    VStack(spacing: 10) {
                        ForEach(viewModel.userGroups) { group in
                            ProfileGroupRow(
                                group: group,
                                onLeave: {
                                    viewModel.groupToLeave = group
                                    viewModel.showingLeaveGroupConfirmation = true
                                },
                                onRename: {
                                    viewModel.groupToRename = group
                                    viewModel.newGroupName = group.name
                                    viewModel.showingRenameGroupSheet = true
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Settings Button Section
    
    private var settingsButtonSection: some View {
        ProfileSectionCard(title: "Settings", icon: "gearshape.fill") {
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Settings")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Notifications, calendar, appearance")
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
    
    // MARK: - Feedback Section

    private var feedbackSection: some View {
        ProfileSectionCard(title: "Feedback & Support", icon: "message.fill") {
            SupportRow(
                title: "Support",
                subtitle: "Get help, report bugs, or request features",
                icon: "questionmark.circle.fill",
                action: {
                    Task {
                        await openURL(urlString: "https://schedulr.co.uk/support")
                    }
                }
            )
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            // Sign Out Button
            ProfileActionButton(
                title: "Sign Out",
                icon: "rectangle.portrait.and.arrow.right",
                style: .standard
            ) {
                Task {
                    await authViewModel.signOut()
                }
            }
            
            // Delete Account Button
            ProfileActionButton(
                title: "Delete Account",
                icon: "trash.fill",
                style: .destructive
            ) {
                viewModel.showingDeleteAccountConfirmation = true
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Error Message View
    
    private var errorMessageView: some View {
        Group {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.red)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Version Info View
    
    private var versionInfoView: some View {
        VStack(spacing: 4) {
            Text("Version \(appVersion)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            
            Text("Build \(appBuildNumber)")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Helpers
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var appBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private func loadSubscriptionInfo() async {
        groupLimitInfo = await SubscriptionLimitService.shared.getGroupLimitInfo()
        
        if subscriptionManager.currentTier == .pro {
            aiUsageInfo = await SubscriptionLimitService.shared.getAIUsageInfo()
        } else {
            aiUsageInfo = nil
        }
    }
}

// MARK: - Profile Section Card

private struct ProfileSectionCard<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(18)
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

// MARK: - Profile Usage Row

private struct ProfileUsageRow: View {
    let icon: String
    let title: String
    let current: Int
    let max: Int
    @EnvironmentObject var themeManager: ThemeManager
    
    /// Threshold for unlimited (matches SubscriptionLimits.unlimited)
    private let unlimitedThreshold = 999999
    
    private var isUnlimited: Bool {
        max >= unlimitedThreshold
    }
    
    private var progress: Double {
        guard max > 0, !isUnlimited else { return 0 }
        return Double(current) / Double(max)
    }
    
    private var isAtLimit: Bool {
        guard !isUnlimited else { return false }
        return current >= max
    }
    
    private var displayMax: String {
        isUnlimited ? "∞" : "\(max)"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 20)
                    
                    Text(title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isUnlimited {
                    HStack(spacing: 4) {
                        Text("\(current)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("/ ∞")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                } else {
                    Text("\(current) / \(max)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isAtLimit ? .red : .secondary)
                }
            }
            
            // Progress bar (hidden for unlimited)
            if !isUnlimited {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isAtLimit
                                ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                : themeManager.gradient
                            )
                            .frame(width: geometry.size.width * min(progress, 1.0), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Profile Toggle Row

private struct ProfileToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .tint(Color(hex: "ff4d8d"))
        }
    }
}

// MARK: - Profile Group Row

private struct ProfileGroupRow: View {
    let group: ProfileViewModel.GroupMembership
    let onLeave: () -> Void
    let onRename: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Group icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [themeManager.primaryColor.opacity(0.2), themeManager.secondaryColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.gradient)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                if let role = group.role {
                    HStack(spacing: 4) {
                        Image(systemName: role == "owner" ? "crown.fill" : "star.fill")
                            .font(.system(size: 10))
                        Text(role == "owner" ? "Owner" : "Member")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(role == "owner" ? Color(hex: "f59e0b") : .secondary)
                }
            }
            
            Spacer()
            
            // Owner actions: Edit button
            if group.role == "owner" {
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(8)
                        .background(themeManager.primaryColor.opacity(0.1))
                        .clipShape(Circle())
                }
            } else {
                // Member action: Leave button
                Button(action: onLeave) {
                    Text("Leave")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Support Row

private struct SupportRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeManager.gradient.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(themeManager.gradient)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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

// MARK: - Profile Action Button

private struct ProfileActionButton: View {
    enum Style {
        case standard
        case destructive
    }
    
    let title: String
    let icon: String
    let style: Style
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(style == .destructive ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if style == .destructive {
                        LinearGradient(
                            colors: [Color(hex: "ef4444"), Color(hex: "dc2626")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        colorScheme == .dark
                        ? Color(hex: "1a1a2e").opacity(0.7)
                        : Color.white.opacity(0.85)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        style == .destructive
                        ? Color.clear
                        : Color.primary.opacity(0.05),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: style == .destructive
                ? Color.red.opacity(0.2)
                : Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05),
                radius: style == .destructive ? 10 : 8,
                x: 0,
                y: 4
            )
        }
    }
}

// MARK: - Rename Group Sheet

private struct RenameGroupSheet: View {
    @Binding var groupName: String
    let isLoading: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    @FocusState private var isNameFocused: Bool
    
    private var isValid: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Text field
                TextField("Group name", text: $groupName)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .focused($isNameFocused)
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isLoading)
                    
                    Button(action: onSave) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Text("Save")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: isValid ? [themeManager.primaryColor, themeManager.secondaryColor] : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!isValid || isLoading)
                }
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("Rename Group")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isNameFocused = true
            }
        }
    }
}

// MARK: - Loading Overlay

private struct ProfileLoadingOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(themeManager.primaryColor)
                
                Text("Loading...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Grace Period Warning

private struct GracePeriodWarningView: View {
    @State private var daysRemaining: Int?
    
    var body: some View {
        Group {
            if let days = daysRemaining {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    
                    Text("Grace period: \(days) day\(days == 1 ? "" : "s") remaining")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .task {
            self.daysRemaining = await GracePeriodManager.shared.getDaysRemaining()
        }
    }
}

// MARK: - Animated Background

private struct ProfileAnimatedBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            
            TimelineView(.animation(minimumInterval: 1/20)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                Canvas { context, size in
                    let blobs: [(Color, CGFloat, CGFloat, CGFloat)] = [
                        (themeManager.primaryColor.opacity(colorScheme == .dark ? 0.08 : 0.06), 0.15, 0.08, 0.32),
                        (themeManager.secondaryColor.opacity(colorScheme == .dark ? 0.06 : 0.05), 0.85, 0.18, 0.28),
                        (Color(hex: "06b6d4").opacity(colorScheme == .dark ? 0.05 : 0.04), 0.5, 0.55, 0.22)
                    ]
                    
                    for (index, (color, baseX, baseY, baseRadius)) in blobs.enumerated() {
                        let phase = time * 0.15 + Double(index) * 2.1
                        let x = baseX + CGFloat(sin(phase)) * 0.06
                        let y = baseY + CGFloat(cos(phase * 0.8)) * 0.04
                        
                        let center = CGPoint(x: size.width * x, y: size.height * y)
                        let radius = size.width * baseRadius
                        
                        let gradient = Gradient(colors: [color, color.opacity(0)])
                        let shading = GraphicsContext.Shading.radialGradient(
                            gradient,
                            center: center,
                            startRadius: 0,
                            endRadius: radius
                        )
                        
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )),
                            with: shading
                        )
                    }
                }
            }
        }
    }
}

// MARK: - URL Handling

extension ProfileView {
    /// Opens a URL in SFSafariViewController
    private func openURL(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        #if os(iOS)
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = UIColor(red: 0.98, green: 0.29, blue: 0.55, alpha: 1.0)
        safariVC.preferredBarTintColor = .systemBackground
        if #available(iOS 11.0, *) {
            safariVC.dismissButtonStyle = .close
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(safariVC, animated: true)
        }
        #else
        await UIApplication.shared.open(url)
        #endif
    }
}
