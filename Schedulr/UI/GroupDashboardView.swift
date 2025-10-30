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

    private let client: SupabaseClient?
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

            let stored = loadStoredGroupID(for: uid)
            if let stored, summaries.contains(where: { $0.id == stored }) {
                selectedGroupID = stored
            } else {
                selectedGroupID = summaries.first?.id
                if let first = summaries.first {
                    storeSelectedGroup(id: first.id, for: uid)
                }
            }
        } catch {
            membershipsError = error.localizedDescription
            memberships = []
            selectedGroupID = nil
        }
    }

    func fetchMembers(for groupID: UUID) async {
        guard !isLoadingMembers else { return }
        guard let client else {
            members = []
            membersError = "Supabase client is unavailable."
            return
        }
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
        } catch {
            membersError = error.localizedDescription
            members = []
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let onSignOut {
                            Button("Sign Out", action: onSignOut)
                                .font(.subheadline)
                        }
                    }
                }
        }
        .task {
            await viewModel.loadInitialData()
            await viewModel.refreshCalendarIfNeeded()
        }
        .refreshable {
            await viewModel.reloadMemberships()
            if let groupID = viewModel.selectedGroupID {
                await viewModel.fetchMembers(for: groupID)
            }
            await viewModel.refreshCalendarIfNeeded()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                groupSelectorSection
                availabilitySection
                membersSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var groupSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your groups")
                .font(.headline)

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
                                    .font(.title3.weight(.semibold))
                                Text(selected.role.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Text("Upcoming for you")
                    .font(.headline)
                Spacer()
                if calendarSync.syncEnabled {
                    Button {
                        Task { await calendarSync.refreshEvents() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            if !calendarSync.syncEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn on calendar sync to display your upcoming events here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Enable calendar sync") {
                        Task {
                            if await calendarSync.enableSyncFlow() {
                                await calendarSync.refreshEvents()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if calendarSync.isRefreshing {
                ProgressView("Syncing calendar…")
            } else if calendarSync.upcomingEvents.isEmpty {
                Text("No events in the next couple of weeks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(calendarSync.upcomingEvents.prefix(5)) { event in
                        CalendarEventCard(event: event)
                    }
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members")
                .font(.headline)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite others")
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(inviteSlug)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct CalendarEventCard: View {
    let event: CalendarSyncManager.SyncedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color(for: event))
                    .frame(width: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title.isEmpty ? "Busy" : event.title)
                        .font(.subheadline.weight(.semibold))
                    Text(dateSummary(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            opacity: event.calendarColor.opacity
        )
    }
}

private struct MemberRow: View {
    let member: DashboardViewModel.MemberSummary

    var body: some View {
        HStack(spacing: 12) {
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
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                AvatarView(initials: initials(for: member.displayName))
                    .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(member.role.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .fill(Color.accentColor.opacity(0.2))
            Text(initials.isEmpty ? ":)" : initials)
                .font(.caption.weight(.bold))
        }
    }
}
