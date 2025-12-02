import SwiftUI
import Combine
import Supabase

// MARK: - ViewModel (Preserved - Same Logic)

@MainActor
final class DashboardViewModel: ObservableObject {
    struct GroupSummary: Identifiable, Equatable {
        let id: UUID
        let name: String
        let role: String
        let inviteSlug: String
        let createdAt: Date?
        let joinedAt: Date?
    }

    struct MemberSummary: Identifiable, Equatable {
        let id: UUID
        let displayName: String
        let role: String
        let avatarURL: URL?
        let joinedAt: Date?
    }

    @Published private(set) var memberships: [GroupSummary] = []
    @Published var selectedGroupID: UUID?
    @Published private(set) var members: [MemberSummary] = []
    @Published private(set) var isLoadingMemberships: Bool = false
    @Published private(set) var isLoadingMembers: Bool = false
    @Published var membershipsError: String?
    @Published var membersError: String?

    let client: SupabaseClient?
    private let calendarManager: CalendarSyncManager
    private let defaults = UserDefaults.standard
    private static let selectedGroupKeyPrefix = "LastSelectedGroup-"

    init(calendarManager: CalendarSyncManager, client: SupabaseClient? = nil) {
        self.calendarManager = calendarManager
        self.client = client ?? SupabaseManager.shared.client
    }

    func loadInitialData() async {
        await reloadMemberships()
        if let groupID = selectedGroupID {
            await fetchMembers(for: groupID)
        } else {
            members = []
        }
    }

    func reloadMemberships() async {
        guard !isLoadingMemberships else { return }
        guard let client else {
            memberships = []
            selectedGroupID = nil
            membershipsError = "Supabase client is unavailable."
            return
        }

        let previouslySelectedID = selectedGroupID
        isLoadingMemberships = true
        membershipsError = nil
        defer { isLoadingMemberships = false }

        do {
            let uid = try await currentUID()
            let rows: [GroupMembershipRow] = try await client.database
                .from("group_members")
                .select("group_id, role, joined_at, groups(id,name,invite_slug,created_at,created_by)")
                .eq("user_id", value: uid)
                .order("joined_at", ascending: true)
                .execute()
                .value

            let summaries = rows.compactMap { row -> GroupSummary? in
                guard let group = row.groups else { return nil }
                return GroupSummary(
                    id: group.id,
                    name: group.name,
                    role: row.role ?? "member",
                    inviteSlug: group.invite_slug,
                    createdAt: group.created_at,
                    joinedAt: row.joined_at
                )
            }

            memberships = summaries

            if let previouslySelectedID, summaries.contains(where: { $0.id == previouslySelectedID }) {
                selectedGroupID = previouslySelectedID
            } else {
                let stored = loadStoredGroupID(for: uid)
                if let stored, summaries.contains(where: { $0.id == stored }) {
                    selectedGroupID = stored
                } else {
                    selectedGroupID = summaries.first?.id
                    if let first = summaries.first {
                        storeSelectedGroup(id: first.id, for: uid)
                    }
                }
            }
        } catch is CancellationError {
            if selectedGroupID == nil, let previouslySelectedID {
                selectedGroupID = previouslySelectedID
            }
        } catch {
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membershipsError = error.localizedDescription
                memberships = []
                selectedGroupID = nil
            } else {
                if selectedGroupID == nil, let previouslySelectedID {
                    selectedGroupID = previouslySelectedID
                }
            }
        }
    }

    func fetchMembers(for groupID: UUID) async {
        guard !isLoadingMembers else { return }
        guard let client else {
            members = []
            membersError = "Supabase client is unavailable."
            return
        }

        let previousMembers = members
        isLoadingMembers = true
        membersError = nil
        defer { isLoadingMembers = false }

        do {
            let rows: [GroupMemberRow] = try await client.database
                .from("group_members")
                .select("user_id, role, joined_at, users(id,display_name,avatar_url)")
                .eq("group_id", value: groupID)
                .order("joined_at", ascending: true)
                .execute()
                .value

            members = rows.map { row in
                MemberSummary(
                    id: row.user_id,
                    displayName: row.users?.display_name ?? "Member",
                    role: row.role ?? "member",
                    avatarURL: row.users?.avatar_url.flatMap(URL.init(string:)),
                    joinedAt: row.joined_at
                )
            }
        } catch is CancellationError {
            if members.isEmpty && !previousMembers.isEmpty {
                members = previousMembers
            }
        } catch {
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membersError = error.localizedDescription
                members = []
            } else {
                if members.isEmpty && !previousMembers.isEmpty {
                    members = previousMembers
                }
            }
        }
    }

    func selectGroup(_ id: UUID) {
        guard selectedGroupID != id else { return }
        selectedGroupID = id
        Task { await fetchMembers(for: id) }
        Task {
            if let uid = try? await currentUID() {
                storeSelectedGroup(id: id, for: uid)
            }
        }
    }

    func refreshCalendarIfNeeded() async {
        if calendarManager.syncEnabled {
            await syncGroupCalendar()
        }
    }

    func syncGroupCalendar() async {
        guard let groupID = selectedGroupID, calendarManager.syncEnabled else { return }
        Task {
            if let userId = try? await currentUID() {
                await calendarManager.syncWithGroup(groupId: groupID, userId: userId)
            }
        }
    }

    private func loadStoredGroupID(for userID: UUID) -> UUID? {
        let key = Self.selectedGroupKeyPrefix + userID.uuidString
        guard let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) else { return nil }
        return id
    }

    private func storeSelectedGroup(id: UUID, for userID: UUID) {
        let key = Self.selectedGroupKeyPrefix + userID.uuidString
        defaults.set(id.uuidString, forKey: key)
    }

    private func currentUID() async throws -> UUID {
        guard let client else {
            throw NSError(domain: "Dashboard", code: -2, userInfo: [NSLocalizedDescriptionKey: "Supabase client is unavailable."])
        }
        let session = try await client.auth.session
        return session.user.id
    }
}

private struct GroupMembershipRow: Decodable {
    let group_id: UUID
    let role: String?
    let joined_at: Date?
    let groups: DBGroup?
}

private struct GroupMemberRow: Decodable {
    let user_id: UUID
    let role: String?
    let joined_at: Date?
    let users: DBUser?
}

// MARK: - Main Dashboard View

struct GroupDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    
    var onSignOut: (() -> Void)?
    
    @State private var currentUserId: UUID?
    @State private var calendarPrefs = CalendarPreferences(hideHolidays: true, dedupAllDay: true)
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var showUpgradePrompt = false
    @State private var upgradePromptType: UpgradePromptModal.LimitType?
    @State private var showGroupManagement = false
    @State private var showTransferOwnershipConfirmation = false
    @State private var showDeleteGroupConfirmation = false
    @State private var showDeleteGroupInfo = false
    @State private var memberToTransfer: DashboardViewModel.MemberSummary?
    @State private var memberCount: Int = 0
    @State private var isOwner: Bool = false
    @StateObject private var notificationViewModel = NotificationViewModel()
    @State private var animateIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Animated background
                DashboardBackground()
                    .ignoresSafeArea()
                
                // Main scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Hero section
                        heroSection
                        
                        // Main content sections
                        VStack(spacing: 24) {
                            welcomeSection
                            groupSelectorSection
                            upcomingEventsSection
                            membersSection
                            inviteSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NotificationBellButton(viewModel: notificationViewModel)
                        .environmentObject(themeManager)
                    
                    Menu {
                        Button {
                            showGroupManagement = true
                        } label: {
                            Label("Create New Group", systemImage: "plus.circle.fill")
                        }
                        
                        if let _ = currentGroup, isOwner {
                            Divider()
                            if memberCount == 1 {
                                Button(role: .destructive) {
                                    showDeleteGroupConfirmation = true
                                } label: {
                                    Label("Delete Group", systemImage: "trash.fill")
                                }
                            } else {
                                Button(role: .destructive) {
                                    showDeleteGroupInfo = true
                                } label: {
                                    Label("Delete Group", systemImage: "trash.fill")
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .semibold))
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
            }
        }
        .task {
            await viewModel.loadInitialData()
            await viewModel.refreshCalendarIfNeeded()
            await loadCalendarPrefs()
            await updateOwnerStatusAndMemberCount()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animateIn = true
            }
        }
        .refreshable {
            await viewModel.reloadMemberships()
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
                await updateOwnerStatusAndMemberCount()
            }
            await viewModel.syncGroupCalendar()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarSyncManager.calendarDidChangeNotification)) { _ in
            Task { await viewModel.syncGroupCalendar() }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showGroupManagement) { GroupManagementView(dashboardVM: viewModel) }
        .alert("Upgrade Required", isPresented: $showUpgradePrompt, presenting: upgradePromptType) { type in
            Button("Upgrade") { showPaywall = true }
            Button("Maybe Later", role: .cancel) {}
        } message: { type in
            Text(type.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUpgradePaywall"))) { notification in
            if let reason = notification.userInfo?["reason"] as? String {
                switch reason {
                case "ai_limit": upgradePromptType = .ai
                case "group_limit": upgradePromptType = .groups
                case "member_limit": upgradePromptType = .members
                default: return
                }
                showUpgradePrompt = true
            }
        }
        .alert("Transfer Ownership", isPresented: $showTransferOwnershipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Transfer", role: .destructive) {
                if let member = memberToTransfer, let groupId = viewModel.selectedGroupID {
                    Task { await transferOwnership(groupId: groupId, newOwnerId: member.id) }
                }
            }
        } message: {
            if let member = memberToTransfer {
                Text("Are you sure you want to transfer ownership of this group to \(member.displayName)? You will become a regular member.")
            }
        }
        .alert("Delete Group", isPresented: $showDeleteGroupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let groupId = viewModel.selectedGroupID {
                    Task {
                        do {
                            let count = try await GroupService.shared.getMemberCount(groupId: groupId)
                            if count == 1 { await deleteGroup(groupId: groupId) }
                        } catch { }
                    }
                }
            }
        } message: {
            if let group = currentGroup {
                Text("Are you sure you want to delete \"\(group.name)\"? This action cannot be undone.")
            }
        }
        .alert("Cannot Delete Group", isPresented: $showDeleteGroupInfo) {
            Button("Transfer Ownership", role: .none) { }
            Button("OK", role: .cancel) { }
        } message: {
            if let group = currentGroup {
                Text("To delete \"\(group.name)\", you must first transfer ownership to another member or remove all other members.")
            }
        }
        .onChange(of: viewModel.selectedGroupID) { _, newGroupID in
            if let groupId = newGroupID, calendarSync.syncEnabled {
                Task {
                    if let userId = try? await viewModel.client?.auth.session.user.id {
                        await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                    }
                }
            }
            Task { await updateOwnerStatusAndMemberCount() }
        }
        .task {
            currentUserId = try? await viewModel.client?.auth.session.user.id
            await updateOwnerStatusAndMemberCount()
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            Image("dashboard-hero")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                    }
                )
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : -20)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Welcome Section
    
    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            Text("Here's what's happening with your groups")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
    
    // MARK: - Group Selector Section
    
    private var groupSelectorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "Your Groups", icon: "person.3.fill")
                .opacity(animateIn ? 1 : 0)
            
            if viewModel.isLoadingMemberships {
                DashboardCard {
                    HStack {
                        ProgressView()
                        Text("Loading groups...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else if let error = viewModel.membershipsError {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load groups")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if viewModel.memberships.isEmpty {
                DashboardCard {
                    VStack(spacing: 16) {
                        Text("Create or join a group to start planning together")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Button {
                            showGroupManagement = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Create or Join Group")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                    }
                }
            } else {
                Menu {
                    ForEach(viewModel.memberships) { membership in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.selectGroup(membership.id)
                            }
                        } label: {
                            HStack {
                                Text(membership.name)
                                if viewModel.selectedGroupID == membership.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    GroupSelectorCard(groupName: currentGroup?.name ?? "Select a group")
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
    
    // MARK: - Upcoming Events Section
    
    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DashboardSectionHeader(title: "Upcoming", icon: "calendar.badge.clock")
                Spacer()
                if calendarSync.syncEnabled && viewModel.selectedGroupID != nil {
                    Button {
                        Task {
                            if let groupId = viewModel.selectedGroupID,
                               let userId = try? await viewModel.client?.auth.session.user.id {
                                await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(calendarSync.isRefreshing ? 360 : 0))
                            .animation(calendarSync.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: calendarSync.isRefreshing)
                    }
                    .disabled(calendarSync.isRefreshing)
                }
            }
            
            // Filter badges
            if calendarPrefs.hideHolidays || calendarPrefs.dedupAllDay {
                HStack(spacing: 8) {
                    if calendarPrefs.hideHolidays {
                        FilterPill(text: "Holidays hidden")
                    }
                    if calendarPrefs.dedupAllDay {
                        FilterPill(text: "Deduped all-day")
                    }
                }
            }
            
            if viewModel.selectedGroupID == nil {
                DashboardCard {
                    Text("Select a group to view upcoming events")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else if !calendarSync.syncEnabled {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enable calendar sync to share availability with your group")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Button {
                            Task {
                                if await calendarSync.enableSyncFlow() {
                                    if let groupId = viewModel.selectedGroupID,
                                       let userId = try? await viewModel.client?.auth.session.user.id {
                                        await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                                    }
                                }
                            }
                        } label: {
                            Text("Enable Calendar Sync")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "8b5cf6"), Color(hex: "06b6d4")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                        }
                    }
                }
            } else if calendarSync.isRefreshing {
                DashboardCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing calendar...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if calendarSync.groupEvents.isEmpty {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No events in the next couple of weeks")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Tap refresh to sync your calendar")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(upcomingMonthEvents) { event in
                        NavigationLink(destination: EventDetailView(event: event.base, member: memberColorMapping[event.base.user_id], currentUserId: currentUserId)) {
                            EventCard(
                                event: event.base,
                                memberName: memberColorMapping[event.base.user_id]?.name,
                                sharedCount: event.sharedCount,
                                currentUserId: currentUserId
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if let error = calendarSync.lastSyncError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(title: "Members", icon: "person.2.fill")
            
            if viewModel.selectedGroupID == nil {
                DashboardCard {
                    Text("Select a group to view members")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else if viewModel.isLoadingMembers {
                DashboardCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading members...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if let error = viewModel.membersError {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load members")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if viewModel.members.isEmpty {
                DashboardCard {
                    Text("No members yet. Share the invite link!")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.members) { member in
                        MemberCard(
                            member: member,
                            isOwner: isOwner,
                            onTransferOwnership: {
                                memberToTransfer = member
                                showTransferOwnershipConfirmation = true
                            }
                        )
                    }
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
    
    // MARK: - Invite Section
    
    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selected = currentGroup {
                DashboardSectionHeader(title: "Invite Friends", icon: "link.circle.fill")
                InviteCard(inviteSlug: selected.inviteSlug, groupName: selected.name)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 20)
    }
    
    // MARK: - Computed Properties
    
    // MARK: - Display Event Model
    
    private struct DashboardDisplayEvent: Identifiable {
        let base: CalendarEventWithUser
        let sharedCount: Int
        var id: UUID { base.id }
    }
    
    private var currentGroup: DashboardViewModel.GroupSummary? {
        guard let id = viewModel.selectedGroupID else { return nil }
        return viewModel.memberships.first(where: { $0.id == id })
    }
    
    private var filteredEvents: [CalendarEventWithUser] {
        let now = Date()
        guard let currentGroupId = viewModel.selectedGroupID else { return [] }
        var list = calendarSync.groupEvents.filter { event in
            event.end_date >= now && event.event_type == "group" && event.group_id == currentGroupId
        }
        if calendarPrefs.hideHolidays {
            list = list.filter { ev in
                let name = (ev.calendar_name ?? ev.title).lowercased()
                let cal = (ev.calendar_name ?? "").lowercased()
                let isHoliday = name.contains("holiday") || cal.contains("holiday")
                let isBirthday = name.contains("birthday") || cal.contains("birthday")
                return !(isHoliday || isBirthday)
            }
        }
        return list.sorted { lhs, rhs in
            if lhs.start_date == rhs.start_date { return lhs.end_date < rhs.end_date }
            return lhs.start_date < rhs.start_date
        }
    }
    
    private var upcomingDashboardDisplayEvents: [DashboardDisplayEvent] {
        var result: [DashboardDisplayEvent] = []
        let calendar = Calendar.current
        let idGroups = Dictionary(grouping: filteredEvents) { $0.id }
        for (_, events) in idGroups {
            if let first = events.first {
                result.append(DashboardDisplayEvent(base: first, sharedCount: 1))
            }
        }
        let alreadyIncludedIds = Set(result.map { $0.base.id })
        let remainingEvents = filteredEvents.filter { !alreadyIncludedIds.contains($0.id) }
        let groups = Dictionary(grouping: remainingEvents) { ev -> String in
            let title = ev.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ev.is_all_day {
                let day = calendar.startOfDay(for: ev.start_date)
                return "allday:\(day.timeIntervalSince1970):\(title)"
            } else {
                let startRounded = round(ev.start_date.timeIntervalSince1970 / 60) * 60
                let endRounded = round(ev.end_date.timeIntervalSince1970 / 60) * 60
                return "timed:\(startRounded):\(endRounded):\(title)"
            }
        }
        for (_, arr) in groups {
            if let first = arr.first {
                let uniqueIds = Set(arr.map { $0.id })
                let uniqueUsers = Set(arr.map { $0.user_id })
                if uniqueIds.count > 1 && uniqueUsers.count > 1 {
                    result.append(DashboardDisplayEvent(base: first, sharedCount: uniqueIds.count))
                } else {
                    result.append(DashboardDisplayEvent(base: first, sharedCount: 1))
                }
            }
        }
        return result.sorted { a, b in
            if a.base.start_date == b.base.start_date { return a.base.end_date < b.base.end_date }
            return a.base.start_date < b.base.start_date
        }
    }
    
    private var upcomingMonthEvents: [DashboardDisplayEvent] {
        guard let firstEvent = upcomingDashboardDisplayEvents.first else { return [] }
        let calendar = Calendar.current
        let firstEventMonth = calendar.component(.month, from: firstEvent.base.start_date)
        let firstEventYear = calendar.component(.year, from: firstEvent.base.start_date)
        let filtered = upcomingDashboardDisplayEvents.filter { event in
            let eventMonth = calendar.component(.month, from: event.base.start_date)
            let eventYear = calendar.component(.year, from: event.base.start_date)
            return eventMonth == firstEventMonth && eventYear == firstEventYear
        }
        return Array(filtered.prefix(10))
    }
    
    private var memberColorMapping: [UUID: (name: String, color: Color)] {
        var mapping: [UUID: (name: String, color: Color)] = [:]
        for member in viewModel.members {
            mapping[member.id] = (name: member.displayName, color: calendarSync.userColor(for: member.id))
        }
        return mapping
    }
    
    // MARK: - Helper Methods
    
    private func loadCalendarPrefs() async {
        if let uid = try? await viewModel.client?.auth.session.user.id {
            if let prefs = try? await CalendarPreferencesManager.shared.load(for: uid) {
                calendarPrefs = prefs
            }
        }
    }
    
    private func updateOwnerStatusAndMemberCount() async {
        guard let groupId = viewModel.selectedGroupID else {
            isOwner = false
            memberCount = 0
            return
        }
        guard viewModel.memberships.contains(where: { $0.id == groupId }) else {
            isOwner = false
            memberCount = 0
            return
        }
        do {
            if let currentGroup = currentGroup {
                isOwner = currentGroup.role == "owner"
            } else {
                isOwner = false
            }
            memberCount = try await GroupService.shared.getMemberCount(groupId: groupId)
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return }
            isOwner = false
            memberCount = 0
        }
    }
    
    private func transferOwnership(groupId: UUID, newOwnerId: UUID) async {
        do {
            try await GroupService.shared.transferOwnership(groupId: groupId, newOwnerId: newOwnerId)
            await viewModel.reloadMemberships()
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
            }
            await updateOwnerStatusAndMemberCount()
        } catch { }
    }
    
    private func deleteGroup(groupId: UUID) async {
        do {
            // Deletion only works when owner is the sole member, so there's no one else to notify
            // Use deleteGroup directly - deleteGroupWithNotification would just filter out the owner
            try await GroupService.shared.deleteGroup(groupId: groupId)
            
            if viewModel.selectedGroupID == groupId {
                viewModel.selectedGroupID = nil
            }
            await viewModel.reloadMemberships()
            isOwner = false
            memberCount = 0
            if !viewModel.memberships.isEmpty {
                viewModel.selectedGroupID = viewModel.memberships.first?.id
                if let _ = viewModel.selectedGroupID {
                    await updateOwnerStatusAndMemberCount()
                }
            }
        } catch { }
    }
}


// MARK: - Background

private struct DashboardBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            
            // Animated gradient orbs
            TimelineView(.animation(minimumInterval: 1/20)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                Canvas { context, size in
                    let blobs: [(Color, CGFloat, CGFloat, CGFloat)] = [
                        (Color(hex: "ff4d8d").opacity(colorScheme == .dark ? 0.08 : 0.06), 0.1, 0.1, 0.35),
                        (Color(hex: "8b5cf6").opacity(colorScheme == .dark ? 0.06 : 0.05), 0.9, 0.2, 0.3),
                        (Color(hex: "06b6d4").opacity(colorScheme == .dark ? 0.05 : 0.04), 0.5, 0.6, 0.25)
                    ]
                    
                    for (index, (color, baseX, baseY, baseRadius)) in blobs.enumerated() {
                        let offset = Double(index) * 0.8
                        let x = size.width * (baseX + 0.05 * sin(time * 0.15 + offset))
                        let y = size.height * (baseY + 0.04 * cos(time * 0.12 + offset))
                        let radius = min(size.width, size.height) * baseRadius
                        
                        let gradient = Gradient(colors: [color, color.opacity(0)])
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius)
                        )
                    }
                }
            }
            .blur(radius: 60)
        }
    }
}

// MARK: - Section Header

private struct DashboardSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Dashboard Card

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

// MARK: - Group Selector Card

private struct GroupSelectorCard: View {
    let groupName: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "ff4d8d").opacity(0.15), Color(hex: "8b5cf6").opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text(groupName)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: "ff4d8d").opacity(0.2), Color(hex: "8b5cf6").opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: CalendarEventWithUser
    var memberName: String?
    var sharedCount: Int = 1
    let currentUserId: UUID?
    @Environment(\.colorScheme) var colorScheme
    
    private var isPrivate: Bool {
        event.event_type == "personal" && event.user_id != currentUserId
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Color bar
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 50)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(isPrivate ? "Busy" : (event.title.isEmpty ? "Busy" : event.title))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                    Text(formatTime(event))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
                
                if sharedCount > 1 && !isPrivate {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .medium))
                        Text("\(sharedCount) attending")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "8b5cf6"))
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func formatTime(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: e.start_date)
        }
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .short
        dayFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return "\(dayFormatter.string(from: e.start_date)) • \(timeFormatter.string(from: e.start_date))"
    }
}

// MARK: - Member Card

private struct MemberCard: View {
    let member: DashboardViewModel.MemberSummary
    let isOwner: Bool
    let onTransferOwnership: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                if let url = member.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            AvatarPlaceholder(initials: initials)
                        @unknown default:
                            AvatarPlaceholder(initials: initials)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    AvatarPlaceholder(initials: initials)
                        .frame(width: 44, height: 44)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(hex: "ff4d8d").opacity(0.4), Color(hex: "8b5cf6").opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if member.role == "owner" {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "f59e0b"))
                    }
                }
                
                Text(member.role.capitalized)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isOwner && member.role != "owner" {
                Menu {
                    Button(role: .destructive) {
                        onTransferOwnership()
                    } label: {
                        Label("Transfer Ownership", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
    
    private var initials: String {
        let parts = member.displayName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
}

// MARK: - Avatar Placeholder

private struct AvatarPlaceholder: View {
    let initials: String
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "ff4d8d").opacity(0.2), Color(hex: "8b5cf6").opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(initials.isEmpty ? "?" : initials.uppercased())
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Invite Card

private struct InviteCard: View {
    let inviteSlug: String
    let groupName: String
    @State private var showCopied = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share \(groupName)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Tap to copy invite link")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if showCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Copied!")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(hex: "10b981"))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            Button {
                UIPasteboard.general.string = inviteSlug
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showCopied = false }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "8b5cf6"))
                    
                    Text(inviteSlug)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: "ff4d8d").opacity(0.15), Color(hex: "8b5cf6").opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
