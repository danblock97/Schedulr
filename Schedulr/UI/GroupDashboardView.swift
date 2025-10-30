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
            print("⚠️ Memberships already loading, skipping...")
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

            print("🔄 Fetching memberships for user: \(uid)")

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

            print("✅ Loaded \(summaries.count) groups")

            memberships = summaries

            // Try to restore previous selection first, then stored, then first group
            if let previouslySelectedID, summaries.contains(where: { $0.id == previouslySelectedID }) {
                selectedGroupID = previouslySelectedID
                print("✅ Restored previously selected group")
            } else {
                let stored = loadStoredGroupID(for: uid)
                if let stored, summaries.contains(where: { $0.id == stored }) {
                    selectedGroupID = stored
                    print("✅ Restored stored group selection")
                } else {
                    selectedGroupID = summaries.first?.id
                    if let first = summaries.first {
                        storeSelectedGroup(id: first.id, for: uid)
                        print("✅ Selected first group as default")
                    }
                }
            }
        } catch is CancellationError {
            print("⚠️ Membership reload was cancelled - keeping existing data")
            // Restore previous selection if it was cleared
            if selectedGroupID == nil, let previouslySelectedID {
                selectedGroupID = previouslySelectedID
            }
            // Don't show error to user - cancellation is normal behavior
        } catch {
            print("❌ Error loading memberships: \(error)")
            // Only show error if it's not a cancellation
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membershipsError = error.localizedDescription
                memberships = []
                selectedGroupID = nil
            } else {
                print("⚠️ Detected cancellation in error message, ignoring...")
                // Restore previous selection
                if selectedGroupID == nil, let previouslySelectedID {
                    selectedGroupID = previouslySelectedID
                }
            }
        }
    }

    func fetchMembers(for groupID: UUID) async {
        guard !isLoadingMembers else {
            print("⚠️ Members already loading, skipping...")
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
            print("🔄 Fetching members for group: \(groupID)")

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

            print("✅ Loaded \(members.count) members")
        } catch is CancellationError {
            print("⚠️ Members fetch was cancelled - keeping existing data")
            // Restore previous members if they were cleared
            if members.isEmpty && !previousMembers.isEmpty {
                members = previousMembers
            }
            // Don't show error to user
        } catch {
            print("❌ Error loading members: \(error)")
            // Check if error message contains "cancel"
            let errorString = error.localizedDescription.lowercased()
            if !errorString.contains("cancel") {
                membersError = error.localizedDescription
                members = []
            } else {
                print("⚠️ Detected cancellation in error message, keeping existing data...")
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
            await calendarManager.refreshEvents()
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

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedulr")
        }
        .task {
            await viewModel.loadInitialData()
            await viewModel.refreshCalendarIfNeeded()
        }
        .refreshable {
            // Reload memberships first
            await viewModel.reloadMemberships()

            // Only fetch members if we have a selected group after reload
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
            }

            // Refresh calendar - don't let this fail the whole refresh
            await viewModel.refreshCalendarIfNeeded()
        }
    }

    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            BubblyDashboardBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Quick stats cards
                    quickStatsSection

                    groupSelectorSection
                    availabilitySection
                    membersSection
                }
                .padding()
                .padding(.bottom, 100) // Space for floating tab bar
            }
        }
    }

    private var quickStatsSection: some View {
        HStack(spacing: 12) {
            // Groups count
            QuickStatCard(
                icon: "person.3.fill",
                count: "\(viewModel.memberships.count)",
                label: "Groups",
                gradient: [Color(red: 0.98, green: 0.29, blue: 0.55), Color(red: 0.58, green: 0.41, blue: 0.87)]
            )

            // Events count
            QuickStatCard(
                icon: "calendar.badge.clock",
                count: "\(calendarSync.upcomingEvents.count)",
                label: "Events",
                gradient: [Color(red: 0.27, green: 0.63, blue: 0.98), Color(red: 0.20, green: 0.78, blue: 0.74)]
            )

            // Members count
            QuickStatCard(
                icon: "person.2.fill",
                count: "\(viewModel.members.count)",
                label: "Members",
                gradient: [Color(red: 0.59, green: 0.85, blue: 0.34), Color(red: 1.00, green: 0.78, blue: 0.16)]
            )
        }
    }

    private var groupSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("👥 Your Groups")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            if viewModel.isLoadingMemberships {
                ProgressView("Loading groups…")
            } else if let error = viewModel.membershipsError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("We couldn’t load your groups.")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.memberships.isEmpty {
                Text("Create or join a group to start planning together.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(viewModel.memberships) { membership in
                        Button {
                            viewModel.selectGroup(membership.id)
                        } label: {
                            Label(membership.name, systemImage: membershipIcon(for: membership.role))
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let selected = currentGroup {
                                Text(selected.name)
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                HStack(spacing: 4) {
                                    Text(selected.role == "owner" ? "👑" : "✨")
                                    Text(selected.role.capitalized)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 22))
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
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                }

                if let selected = currentGroup {
                    GroupInviteView(inviteSlug: selected.inviteSlug)
                }
            }
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📅 Group Calendar")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.27, green: 0.63, blue: 0.98),
                                        Color(red: 0.20, green: 0.78, blue: 0.74)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(calendarSync.isRefreshing)
                }
            }

            if viewModel.selectedGroupID == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select a group to view the shared calendar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if !calendarSync.syncEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn on calendar sync to share your calendar with the group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Enable calendar sync") {
                        Task {
                            if await calendarSync.enableSyncFlow() {
                                if let groupId = viewModel.selectedGroupID,
                                   let userId = try? await viewModel.client?.auth.session.user.id {
                                    await calendarSync.syncWithGroup(groupId: groupId, userId: userId)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if calendarSync.isRefreshing {
                ProgressView("Syncing calendar…")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if calendarSync.groupEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No events in the next couple of weeks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tap the refresh button to sync your calendar with the group.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Calendar block view
                CalendarBlockView(
                    events: calendarSync.groupEvents,
                    members: memberColorMapping
                )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("✨ Members")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            if viewModel.selectedGroupID == nil {
                Text("Pick a group to view its members.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.isLoadingMembers {
                ProgressView("Loading members…")
            } else if let error = viewModel.membersError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("We couldn’t load member details.")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.members.isEmpty {
                Text("No members found yet. Share the invite link to get people in!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.members) { member in
                        MemberRow(member: member)
                    }
                }
            }
        }
    }

    private var currentGroup: DashboardViewModel.GroupSummary? {
        guard let id = viewModel.selectedGroupID else { return nil }
        return viewModel.memberships.first(where: { $0.id == id })
    }

    private func membershipIcon(for role: String) -> String {
        switch role.lowercased() {
        case "owner": return "star.fill"
        default: return "person.2.fill"
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

// MARK: - Quick Stat Card

private struct QuickStatCard: View {
    let icon: String
    let count: String
    let label: String
    let gradient: [Color]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            Text(count)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Bubbly Background

private struct BubblyDashboardBackground: View {
    var body: some View {
        ZStack {
            // Large pink bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.12),
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.03)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 180
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: -120, y: -200)
                .blur(radius: 50)

            // Purple bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.12),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.03)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: 140, y: 150)
                .blur(radius: 50)

            // Blue bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.10),
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 140
                    )
                )
                .frame(width: 220, height: 220)
                .offset(x: -100, y: 500)
                .blur(radius: 40)

            // Teal bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.20, green: 0.78, blue: 0.74).opacity(0.08),
                            Color(red: 0.20, green: 0.78, blue: 0.74).opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 120
                    )
                )
                .frame(width: 180, height: 180)
                .offset(x: 130, y: -100)
                .blur(radius: 35)

            // Small decorative bubbles
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 50, height: 50)
                .offset(x: 150, y: -150)
                .blur(radius: 8)

            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 35, height: 35)
                .offset(x: -140, y: 80)
                .blur(radius: 6)

            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 40)
                .offset(x: 100, y: 350)
                .blur(radius: 7)
        }
    }
}
