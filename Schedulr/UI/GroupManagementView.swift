import SwiftUI
import Supabase

struct GroupManagementView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var groupName: String = ""
    @State private var inviteCode: String = ""
    @State private var isCreating: Bool = false
    @State private var isJoining: Bool = false
    @State private var errorMessage: String?
    @State private var showUpgradePrompt: Bool = false
    @State private var showPaywall: Bool = false
    @State private var groupLimitInfo: (current: Int, max: Int)?
    @State private var limitCheckDetails: GroupLimitCheck?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        headerSection
                        limitInfoSection
                        createGroupSection
                        joinGroupSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Upgrade Required", isPresented: $showUpgradePrompt) {
                if let details = limitCheckDetails, details.currentTier == "pro" {
                    Button("OK", role: .cancel) {}
                } else {
                    Button("Upgrade") {
                        showPaywall = true
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                if let details = limitCheckDetails, details.currentTier == "pro" {
                    Text("You've reached the maximum number of groups (\(details.maxAllowed)). Pro is the highest subscription tier.")
                } else {
                    Text("You've reached your group limit. Upgrade to Pro to create or join more groups!")
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                await loadLimitInfo()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48, weight: .medium))
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
            
            Text("Create or Join a Group")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Connect with friends and family to coordinate your schedules")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    private var limitInfoSection: some View {
        Group {
            if let info = groupLimitInfo {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(red: 0.58, green: 0.41, blue: 0.87))
                    Text("\(info.current) / \(info.max) groups")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private var createGroupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Group")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            
            VStack(spacing: 12) {
                TextField("e.g. Weekend Warriors", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                
                Button {
                    Task { await createGroup() }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Create Group")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
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
                    .cornerRadius(16)
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
    }
    
    private var joinGroupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Join Existing Group")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
            }
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite Code or Link")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Paste code or link", text: $inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .autocorrectionDisabled()
                }
                
                Button {
                    Task { await joinGroup() }
                } label: {
                    HStack {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.plus.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Join Group")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.41, blue: 0.87),
                                Color(red: 0.27, green: 0.63, blue: 0.98)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadLimitInfo() async {
        groupLimitInfo = await SubscriptionLimitService.shared.getGroupLimitInfo()
    }
    
    private func createGroup() async {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Check limits first
        let limitCheck = await SubscriptionLimitService.shared.canJoinGroup()
        if !limitCheck.canProceed {
            errorMessage = nil
            // Get detailed limit check to determine if user is Pro
            limitCheckDetails = await SubscriptionLimitService.shared.canJoinGroupWithDetails()
            showUpgradePrompt = true
            return
        }
        
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            guard let client = dashboardVM.client ?? SupabaseManager.shared.client else {
                errorMessage = "Service unavailable. Please try again."
                return
            }
            let session = try await client.auth.session
            let uid = session.user.id
            
            let payload = DBGroupInsert(name: trimmedName, created_by: uid)
            let groups: [DBGroup] = try await client.database
                .from("groups")
                .insert(payload)
                .select()
                .execute()
                .value
            
            if let group = groups.first {
                // Ensure membership as owner in case trigger wasn't installed
                let member = DBGroupMember(group_id: group.id, user_id: uid, role: "owner", joined_at: nil)
                _ = try? await client.database.from("group_members").insert(member).execute()
                
                // Refresh dashboard
                await dashboardVM.reloadMemberships()
                
                // Clear and dismiss
                groupName = ""
                dismiss()
            }
        } catch {
            errorMessage = "Failed to create group: \(error.localizedDescription)"
        }
    }
    
    private func joinGroup() async {
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }
        
        // Check limits first
        let limitCheck = await SubscriptionLimitService.shared.canJoinGroup()
        if !limitCheck.canProceed {
            errorMessage = nil
            // Get detailed limit check to determine if user is Pro
            limitCheckDetails = await SubscriptionLimitService.shared.canJoinGroupWithDetails()
            showUpgradePrompt = true
            return
        }
        
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }
        
        do {
            guard let client = dashboardVM.client ?? SupabaseManager.shared.client else {
                errorMessage = "Service unavailable. Please try again."
                return
            }
            let session = try await client.auth.session
            let uid = session.user.id
            
            let slug = extractSlug(from: trimmedCode)
            guard !slug.isEmpty else {
                errorMessage = "Invalid invite code"
                return
            }
            
            let found: [DBGroup] = try await client.database
                .from("groups")
                .select()
                .eq("invite_slug", value: slug)
                .limit(1)
                .execute()
                .value
            
            guard let group = found.first else {
                errorMessage = "Invalid invite code or link"
                return
            }
            
            // Check if already a member
            let existingMemberships: [DBGroupMember] = try await client.database
                .from("group_members")
                .select()
                .eq("group_id", value: group.id)
                .eq("user_id", value: uid)
                .execute()
                .value
            
            if !existingMemberships.isEmpty {
                errorMessage = "You're already a member of this group"
                return
            }
            
            let member = DBGroupMember(group_id: group.id, user_id: uid, role: "member", joined_at: nil)
            _ = try await client.database.from("group_members").insert(member).execute()
            
            // Refresh dashboard
            await dashboardVM.reloadMemberships()
            
            // Clear and dismiss
            inviteCode = ""
            dismiss()
        } catch {
            errorMessage = "Failed to join group: \(error.localizedDescription)"
        }
    }
    
    private func extractSlug(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let last = url.pathComponents.last, last.count >= 4 {
            return last
        }
        // Fallback: accept raw code
        return trimmed
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    let viewModel = DashboardViewModel(calendarManager: calendarManager)
    return GroupManagementView(dashboardVM: viewModel)
}

