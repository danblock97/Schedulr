import SwiftUI
import Combine
import Supabase

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
        guard !isLoadingMemberships else {
            return
        }
        guard let client else {
            memberships = []
            selectedGroupID = nil
            membershipsError = "Supabase client is unavailable."
            return
        }

        // Store current selection before reload
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

            // Try to restore previous selection first, then stored, then first group
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
            // Restore previous selection if it was cleared
            if selectedGroupID == nil, let previouslySelectedID {
                selectedGroupID = previouslySelectedID
            }
            // Don't show error to user - cancellation is normal behavior
        } catch {
            // Only show error if it's not a cancellation
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membershipsError = error.localizedDescription
                memberships = []
                selectedGroupID = nil
            } else {
                // Restore previous selection
                if selectedGroupID == nil, let previouslySelectedID {
                    selectedGroupID = previouslySelectedID
                }
            }
        }
    }

    func fetchMembers(for groupID: UUID) async {
        guard !isLoadingMembers else {
            return
        }
        guard let client else {
            members = []
            membersError = "Supabase client is unavailable."
            return
        }

        // Store existing members in case of cancellation
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
            // Restore previous members if they were cleared
            if members.isEmpty && !previousMembers.isEmpty {
                members = previousMembers
            }
            // Don't show error to user
        } catch {
            // Check if error message contains "cancel"
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membersError = error.localizedDescription
                members = []
            } else {
                // Restore previous members
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

struct GroupDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    var onSignOut: (() -> Void)?
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

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showGroupManagement = true
                            } label: {
                                Label("Create New Group", systemImage: "plus.circle.fill")
                            }
                            
                            // Show delete option for owners (with different behavior based on member count)
                            if let selectedGroup = currentGroup, isOwner {
                                Divider()
                                
                                if memberCount == 1 {
                                    // Can delete if sole member
                                    Button(role: .destructive) {
                                        showDeleteGroupConfirmation = true
                                    } label: {
                                        Label("Delete Group", systemImage: "trash.fill")
                                    }
                                } else {
                                    // Show option that explains need to transfer ownership when multiple members
                                    Button(role: .destructive) {
                                        showDeleteGroupInfo = true
                                    } label: {
                                        Label("Delete Group", systemImage: "trash.fill")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
                        }
                    }
                }
        }
        .task {
            await viewModel.loadInitialData()
            await viewModel.refreshCalendarIfNeeded()
            await loadCalendarPrefs()
            await updateOwnerStatusAndMemberCount()
        }
        .refreshable {
            // Reload memberships first
            await viewModel.reloadMemberships()

            // Only fetch members if we have a selected group after reload
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
                await updateOwnerStatusAndMemberCount()
            }

            // Refresh calendar - don't let this fail the whole refresh
            await viewModel.syncGroupCalendar()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarSyncManager.calendarDidChangeNotification)) { _ in
            Task {
                await viewModel.syncGroupCalendar()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showGroupManagement) {
            GroupManagementView(dashboardVM: viewModel)
        }
        .alert("Upgrade Required", isPresented: $showUpgradePrompt, presenting: upgradePromptType) { type in
            Button("Upgrade") {
                showPaywall = true
            }
            Button("Maybe Later", role: .cancel) {}
        } message: { type in
            Text(type.message)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUpgradePaywall"))) { notification in
            if let reason = notification.userInfo?["reason"] as? String {
                switch reason {
                case "ai_limit":
                    upgradePromptType = .ai
                case "group_limit":
                    upgradePromptType = .groups
                case "member_limit":
                    upgradePromptType = .members
                default:
                    return
                }
                showUpgradePrompt = true
            }
        }
    }

    private var content: some View {
        ZStack {
            // Soft background color
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            // Subtle soft color overlay
            ZStack {
                // Base soft tint
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.08),
                        Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Additional soft radial gradients for depth
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.06),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
                    .offset(x: -150, y: -200)
                    .blur(radius: 80)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 350
                        )
                    )
                    .offset(x: 180, y: 400)
                    .blur(radius: 100)
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Quick stats cards
                    quickStatsSection

                    groupSelectorSection
                    availabilitySection
                    membersSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100) // Space for floating tab bar
            }
        }
    }

    private var quickStatsSection: some View {
        HStack(spacing: 16) {
            // Groups count
            EnhancedQuickStatCard(
                icon: "person.3.fill",
                count: "\(viewModel.memberships.count)",
                label: "Groups",
                gradient: [],
                accentColor: Color(red: 0.98, green: 0.29, blue: 0.55)
            )

            // Events count
            EnhancedQuickStatCard(
                icon: "calendar.badge.clock",
                count: "\(upcomingDisplayEvents.count)",
                label: "Events",
                gradient: [],
                accentColor: Color(red: 0.58, green: 0.41, blue: 0.87)
            )

            // Members count
            EnhancedQuickStatCard(
                icon: "person.2.fill",
                count: "\(viewModel.members.count)",
                label: "Members",
                gradient: [],
                accentColor: Color(red: 0.59, green: 0.85, blue: 0.34)
            )
        }
    }

    private var groupSelectorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "person.3.fill", title: "Your Groups", color: Color(red: 0.98, green: 0.29, blue: 0.55))

            if viewModel.isLoadingMemberships {
                BubblyCard {
                ProgressView("Loading groups…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else if let error = viewModel.membershipsError {
                BubblyCard {
                VStack(alignment: .leading, spacing: 6) {
                        Text("We couldn't load your groups.")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if viewModel.memberships.isEmpty {
                BubblyCard {
                    VStack(spacing: 16) {
                        Text("Create or join a group to start planning together.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button {
                            showGroupManagement = true
                        } label: {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Create or Join Group")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
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
                            .cornerRadius(12)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.memberships) { membership in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewModel.selectGroup(membership.id)
                            }
                        } label: {
                            BubblyCard {
                                HStack {
                                    Text(membership.name)
                                        .font(.system(size: 17, weight: .regular, design: .default))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    if viewModel.selectedGroupID == membership.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selected = currentGroup {
                    EnhancedGroupInviteView(inviteSlug: selected.inviteSlug)
                }
            }
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(icon: "calendar.badge.clock", title: "Upcoming", color: Color(red: 0.58, green: 0.41, blue: 0.87))
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
                        Image(systemName: calendarSync.isRefreshing ? "arrow.clockwise" : "arrow.clockwise.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color(red: 0.58, green: 0.41, blue: 0.87))
                            .symbolRenderingMode(.hierarchical)
                            .rotationEffect(.degrees(calendarSync.isRefreshing ? 360 : 0))
                            .animation(calendarSync.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: calendarSync.isRefreshing)
                    }
                    .disabled(calendarSync.isRefreshing)
                }
            }

            // Active filter indicators
            if calendarPrefs.hideHolidays || calendarPrefs.dedupAllDay {
                HStack(spacing: 10) {
                    if calendarPrefs.hideHolidays {
                        FilterBadge(text: "Holidays hidden", color: Color(red: 0.58, green: 0.41, blue: 0.87))
                    }
                    if calendarPrefs.dedupAllDay {
                        FilterBadge(text: "Deduped all‑day", color: Color(red: 0.98, green: 0.29, blue: 0.55))
                    }
                }
            }

            if viewModel.selectedGroupID == nil {
                BubblyCard {
                    Text("Select a group to view upcoming events.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            } else if !calendarSync.syncEnabled {
                BubblyCard {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("Turn on calendar sync to share your calendar with the group.")
                        .font(.footnote)
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
                            Text("Enable calendar sync")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Color(red: 0.58, green: 0.41, blue: 0.87),
                                    in: Capsule()
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else if calendarSync.isRefreshing {
                BubblyCard {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Syncing calendar…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else if calendarSync.groupEvents.isEmpty {
                BubblyCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No events in the next couple of weeks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tap the refresh button to sync your calendar with the group.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                }
            } else {
                // Upcoming list (next 10 events)
                VStack(spacing: 14) {
                    ForEach(upcomingDisplayEvents.prefix(10)) { devent in
                        NavigationLink(destination: EventDetailView(event: devent.base, member: memberColorMapping[devent.base.user_id])) {
                            EnhancedUpcomingEventRow(
                                event: devent.base,
                                memberColor: memberColorMapping[devent.base.user_id]?.color,
                                memberName: memberColorMapping[devent.base.user_id]?.name,
                                sharedCount: devent.sharedCount
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Show any sync errors
            if let error = calendarSync.lastSyncError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onChange(of: viewModel.selectedGroupID) { _, newGroupID in
            // Sync calendar when group changes
            if let groupId = newGroupID, calendarSync.syncEnabled {
                Task {
                    if let userId = try? await viewModel.client?.auth.session.user.id {
                        await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                    }
                }
            }
            // Update owner status and member count
            Task {
                await updateOwnerStatusAndMemberCount()
            }
        }
        .task {
            await updateOwnerStatusAndMemberCount()
        }
        .alert("Transfer Ownership", isPresented: $showTransferOwnershipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Transfer", role: .destructive) {
                if let member = memberToTransfer,
                   let groupId = viewModel.selectedGroupID {
                    Task {
                        await transferOwnership(groupId: groupId, newOwnerId: member.id)
                    }
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
                    // Double-check member count before deleting
                    Task {
                        do {
                            let count = try await GroupService.shared.getMemberCount(groupId: groupId)
                            if count == 1 {
                                await deleteGroup(groupId: groupId)
                            } else {
                                // This shouldn't happen, but show error if it does
                                print("❌ Cannot delete group: has \(count) members")
                            }
                        } catch {
                            print("❌ Error checking member count: \(error)")
                        }
                    }
                }
            }
        } message: {
            if let group = currentGroup {
                Text("Are you sure you want to delete \"\(group.name)\"? This action cannot be undone. All events and members will be removed.")
            }
        }
        .alert("Cannot Delete Group", isPresented: $showDeleteGroupInfo) {
            Button("Transfer Ownership", role: .none) {
                // Optionally could scroll to members section or highlight transfer option
                // For now, just dismiss and let user use the member menu
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let group = currentGroup {
                Text("To delete \"\(group.name)\", you must first transfer ownership to another member or remove all other members. The group currently has \(memberCount) member\(memberCount == 1 ? "" : "s").\n\nYou can transfer ownership by tapping the menu (⋯) next to any member's name.")
            }
        }
    }

    private var filteredEvents: [CalendarEventWithUser] {
        let now = Date()
        var list = calendarSync.groupEvents.filter { $0.end_date >= now }
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

    private var upcomingDisplayEvents: [DisplayEvent] {
        // Always deduplicate events: group identical events by normalized title + time range
        var result: [DisplayEvent] = []
        let calendar = Calendar.current
        
        let groups = Dictionary(grouping: filteredEvents) { ev -> String in
            let title = ev.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ev.is_all_day {
                // For all-day events, group by day + title
                let day = calendar.startOfDay(for: ev.start_date)
                return "allday:\(day.timeIntervalSince1970):\(title)"
            } else {
                // For timed events, group by start/end time (within 1 minute tolerance) + title
                let startRounded = round(ev.start_date.timeIntervalSince1970 / 60) * 60
                let endRounded = round(ev.end_date.timeIntervalSince1970 / 60) * 60
                return "timed:\(startRounded):\(endRounded):\(title)"
            }
        }
        
        for (_, arr) in groups {
            if let first = arr.first {
                // Always show with shared count if multiple users have the same event
                result.append(DisplayEvent(base: first, sharedCount: arr.count))
            }
        }
        
        return result.sorted { a, b in
            if a.base.start_date == b.base.start_date { return a.base.end_date < b.base.end_date }
            return a.base.start_date < b.base.start_date
        }
    }

    private var memberColorMapping: [UUID: (name: String, color: Color)] {
        var mapping: [UUID: (name: String, color: Color)] = [:]
        for member in viewModel.members {
            mapping[member.id] = (
                name: member.displayName,
                color: calendarSync.userColor(for: member.id)
            )
        }
        return mapping
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "person.2.fill", title: "Members", color: Color(red: 0.59, green: 0.85, blue: 0.34))

            if viewModel.selectedGroupID == nil {
                BubblyCard {
                Text("Pick a group to view its members.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            } else if viewModel.isLoadingMembers {
                BubblyCard {
                ProgressView("Loading members…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else if let error = viewModel.membersError {
                BubblyCard {
                VStack(alignment: .leading, spacing: 6) {
                        Text("We couldn't load member details.")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if viewModel.members.isEmpty {
                BubblyCard {
                Text("No members found yet. Share the invite link to get people in!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.members) { member in
                        EnhancedMemberRow(
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
    }

    private var currentGroup: DashboardViewModel.GroupSummary? {
        guard let id = viewModel.selectedGroupID else { return nil }
        return viewModel.memberships.first(where: { $0.id == id })
    }
    
    private func updateOwnerStatusAndMemberCount() async {
        guard let groupId = viewModel.selectedGroupID else {
            isOwner = false
            memberCount = 0
            return
        }
        
        // Verify group still exists in memberships before querying
        guard viewModel.memberships.contains(where: { $0.id == groupId }) else {
            isOwner = false
            memberCount = 0
            return
        }
        
        do {
            // Check if current user is owner
            if let currentGroup = currentGroup {
                isOwner = currentGroup.role == "owner"
            } else {
                isOwner = false
            }
            
            // Get member count
            memberCount = try await GroupService.shared.getMemberCount(groupId: groupId)
        } catch {
            // Ignore cancellation errors (happens when group is deleted mid-query)
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            print("Error updating owner status: \(error)")
            isOwner = false
            memberCount = 0
        }
    }
    
    private func transferOwnership(groupId: UUID, newOwnerId: UUID) async {
        do {
            try await GroupService.shared.transferOwnership(groupId: groupId, newOwnerId: newOwnerId)
            // Refresh members and memberships
            await viewModel.reloadMemberships()
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
            }
            await updateOwnerStatusAndMemberCount()
        } catch {
            // Handle error - could show alert
            print("Error transferring ownership: \(error)")
        }
    }
    
    private func deleteGroup(groupId: UUID) async {
        do {
            print("🗑️ Attempting to delete group: \(groupId)")
            try await GroupService.shared.deleteGroup(groupId: groupId)
            print("✅ Group deleted successfully")
            
            // Clear selection first before reload to avoid querying deleted group
            if viewModel.selectedGroupID == groupId {
                viewModel.selectedGroupID = nil
            }
            
            // Refresh memberships (group will be removed)
            await viewModel.reloadMemberships()
            
            // Reset owner status and member count since we're no longer viewing a group
            isOwner = false
            memberCount = 0
            
            // Select first available group if any remain
            if !viewModel.memberships.isEmpty {
                viewModel.selectedGroupID = viewModel.memberships.first?.id
                if let newGroupId = viewModel.selectedGroupID {
                    await updateOwnerStatusAndMemberCount()
                }
            }
        } catch {
            print("❌ Error deleting group: \(error)")
            // Show error alert
            await MainActor.run {
                // Could show an alert here if we add error state
            }
        }
    }

    private func membershipIcon(for role: String) -> String {
        switch role.lowercased() {
        case "owner": return "star.fill"
        default: return "person.2.fill"
        }
    }
}

private struct UpcomingEventRow: View {
    let event: CalendarEventWithUser
    var memberColor: Color?
    var memberName: String?
    var sharedCount: Int = 1

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(dotColor.opacity(0.9))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .fill(dotColor.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .blur(radius: 4)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if sharedCount > 1 {
                    Text("shared by \(sharedCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(timeSummary(event))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let memberName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(dotColor)
                        Text(memberName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(dotColor)
                    }
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var defaultColor: Color { Color(red: 0.27, green: 0.63, blue: 0.98) }

    private var dotColor: Color {
        if let c = event.effectiveColor {
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
        return memberColor ?? defaultColor
    }

    private func timeSummary(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day { return "All day" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if Calendar.current.isDate(e.start_date, inSameDayAs: e.end_date) {
            return "\(dayFormatter.string(from: e.start_date)) • \(timeFormatter.string(from: e.start_date)) – \(timeFormatter.string(from: e.end_date))"
        } else {
            return "\(dayFormatter.string(from: e.start_date)) \(timeFormatter.string(from: e.start_date)) → \(dayFormatter.string(from: e.end_date)) \(timeFormatter.string(from: e.end_date))"
        }
    }
}

// MARK: - Prefs IO
extension GroupDashboardView {
    private func loadCalendarPrefs() async {
        if let uid = try? await viewModel.client?.auth.session.user.id {
            if let prefs = try? await CalendarPreferencesManager.shared.load(for: uid) {
                calendarPrefs = prefs
            }
        }
    }
}

private struct GroupInviteView: View {
    let inviteSlug: String
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🎉 Invite Link")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                if showCopied {
                    Text("Copied!")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.59, green: 0.85, blue: 0.34))
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Button {
                UIPasteboard.general.string = inviteSlug
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCopied = false
                    }
                }
            } label: {
                HStack {
                    Text(inviteSlug)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "doc.on.doc.fill")
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
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
}

private struct CalendarEventCard: View {
    let event: CalendarSyncManager.SyncedEvent
    var userColor: Color?
    var showUserAttribution: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            // Color accent circle - use user color if provided, otherwise calendar color
            Circle()
                .fill(userColor ?? color(for: event))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .fill((userColor ?? color(for: event)).opacity(0.3))
                        .frame(width: 24, height: 24)
                        .blur(radius: 4)
                )

            VStack(alignment: .leading, spacing: 6) {
                // Event title
                Text(event.title.isEmpty ? "🔒 Busy" : event.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                // Show user name if attribution is enabled
                if showUserAttribution, let userName = event.userName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(userColor ?? .secondary)
                        Text(userName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(userColor ?? .secondary)
                    }
                }

                // Time info
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(dateSummary(event))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Location
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((userColor ?? Color.white).opacity(0.2), lineWidth: 1)
        )
    }

    private func dateSummary(_ event: CalendarSyncManager.SyncedEvent) -> String {
        if event.isAllDay {
            return "All day • \(event.calendarTitle)"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            return "\(dayFormatter.string(from: event.startDate)) • \(timeFormatter.string(from: event.startDate)) – \(timeFormatter.string(from: event.endDate))"
        } else {
            return "\(dayFormatter.string(from: event.startDate)) \(timeFormatter.string(from: event.startDate)) → \(dayFormatter.string(from: event.endDate)) \(timeFormatter.string(from: event.endDate))"
        }
    }

    private func color(for event: CalendarSyncManager.SyncedEvent) -> Color {
        Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.alpha
        )
    }
}

private struct MemberRow: View {
    let member: DashboardViewModel.MemberSummary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let url = member.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            AvatarView(initials: initials(for: member.displayName))
                        @unknown default:
                            AvatarView(initials: initials(for: member.displayName))
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    AvatarView(initials: initials(for: member.displayName))
                        .frame(width: 50, height: 50)
                }
            }
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4),
                                Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(member.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text(member.role == "owner" ? "👑" : "✨")
                        .font(.system(size: 12))
                    Text(member.role.capitalized)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).map { part in
            part.first.map(String.init) ?? ""
        }
        return initials.joined()
    }
}

private struct AvatarView: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials.isEmpty ? "✨" : initials)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Enhanced Quick Stat Card

private struct EnhancedQuickStatCard: View {
    let icon: String
    let count: String
    let label: String
    let gradient: [Color]
    let accentColor: Color
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium, design: .default))
                .foregroundColor(accentColor)
                .symbolRenderingMode(.monochrome)

            Text(count)
                .font(.system(size: 32, weight: .semibold, design: .default))
                .foregroundColor(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}


// MARK: - Section Header

private struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold, design: .default))
            .foregroundStyle(.primary)
    }
}

// MARK: - Bubbly Card

private struct BubblyCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
    }
}

// MARK: - Filter Badge

private struct FilterBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular, design: .default))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.1))
            )
            .foregroundStyle(color)
    }
}

// MARK: - Enhanced Upcoming Event Row

private struct EnhancedUpcomingEventRow: View {
    let event: CalendarEventWithUser
    var memberColor: Color?
    var memberName: String?
    var sharedCount: Int = 1
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if sharedCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(sharedCount) members")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(dotColor.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(dotColor.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(dotColor)
                }
                
                HStack(spacing: 8) {
                    Label {
                        Text(timeSummary(event))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let memberName {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(dotColor)
                        Text(memberName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(dotColor)
                    }
                }
                
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
    
    private var defaultColor: Color { Color(red: 0.58, green: 0.41, blue: 0.87) }
    
    private var dotColor: Color {
        if let c = event.effectiveColor {
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
        return memberColor ?? defaultColor
    }
    
    private func timeSummary(_ e: CalendarEventWithUser) -> String {
        if e.is_all_day { return "All day" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        if Calendar.current.isDate(e.start_date, inSameDayAs: e.end_date) {
            return "\(dayFormatter.string(from: e.start_date)) • \(timeFormatter.string(from: e.start_date)) – \(timeFormatter.string(from: e.end_date))"
        } else {
            return "\(dayFormatter.string(from: e.start_date)) \(timeFormatter.string(from: e.start_date)) → \(dayFormatter.string(from: e.end_date)) \(timeFormatter.string(from: e.end_date))"
        }
    }
}

// MARK: - Enhanced Member Row

private struct EnhancedMemberRow: View {
    let member: DashboardViewModel.MemberSummary
    let isOwner: Bool
    let onTransferOwnership: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if let url = member.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            EnhancedAvatarView(initials: initials(for: member.displayName))
                        @unknown default:
                            EnhancedAvatarView(initials: initials(for: member.displayName))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                } else {
                    EnhancedAvatarView(initials: initials(for: member.displayName))
                        .frame(width: 56, height: 56)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(member.displayName)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(.primary)
                
                Text(member.role.capitalized)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            // Show transfer ownership button for owners (not on themselves)
            if isOwner && member.role != "owner" {
                Menu {
                    Button(role: .destructive) {
                        onTransferOwnership()
                    } label: {
                        Label("Transfer Ownership", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
    
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).map { part in
            part.first.map(String.init) ?? ""
        }
        return initials.joined()
    }
}

// MARK: - Enhanced Avatar View

private struct EnhancedAvatarView: View {
    let initials: String
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Enhanced Group Invite View

private struct EnhancedGroupInviteView: View {
    let inviteSlug: String
    @State private var showCopied = false
    
    var body: some View {
        BubblyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 8) {
                        Text("Invite Link")
                            .font(.system(size: 17, weight: .regular, design: .default))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if showCopied {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Copied!")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(Color(red: 0.59, green: 0.85, blue: 0.34))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Button {
                    UIPasteboard.general.string = inviteSlug
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopied = false
                        }
                    }
                } label: {
                    HStack {
                        Text(inviteSlug)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}
