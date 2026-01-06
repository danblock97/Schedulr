import Foundation
import SwiftUI
import Combine
import Supabase
import EventKit

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case avatar
        case name
        case group
        case calendar
        case done
    }

    // Public state for the UI
    @Published var step: Step = .avatar

    // Avatar step
    @Published var pickedImageData: Data? = nil
    @Published var isUploadingAvatar: Bool = false
    @Published var avatarPublicURL: URL? = nil

    // Name step
    @Published var displayName: String = ""
    @Published var isSavingName: Bool = false

    // Group step
    @Published var groupMode: GroupMode = .create
    @Published var groupName: String = ""
    @Published var joinInput: String = ""
    @Published var isHandlingGroup: Bool = false

    // Calendar step
    @Published var wantsCalendarSync: Bool = false

    // Errors
    @Published var errorMessage: String? = nil

    // Completion
    var onFinished: (() -> Void)?

    enum GroupMode: String, CaseIterable, Identifiable { case skip, create, join; var id: String { rawValue } }

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let calendarManager: CalendarSyncManager?

    init(calendarManager: CalendarSyncManager? = nil, onFinished: (() -> Void)? = nil) {
        self.calendarManager = calendarManager
        self.onFinished = onFinished
        wantsCalendarSync = calendarManager?.syncEnabled ?? false
    }

    // MARK: - Reset
    
    /// Resets all onboarding state when user signs out
    func reset() {
        step = .avatar
        pickedImageData = nil
        isUploadingAvatar = false
        avatarPublicURL = nil
        displayName = ""
        isSavingName = false
        groupMode = .create
        groupName = ""
        joinInput = ""
        isHandlingGroup = false
        wantsCalendarSync = false
        errorMessage = nil
        onFinished = nil
    }
    
    // MARK: - Gating
    func needsOnboarding() async -> Bool {
        // Only consider onboarding when authenticated
        guard let session = try? await client.auth.session, session != nil else { return false }
        do {
            // Does users row exist?
            let user = try await fetchUser(uid: session.user.id)
            // If missing or missing display name, show onboarding
            return user == nil || (user?.display_name?.isEmpty ?? true)
        } catch {
            // If there is an auth session but the user row cannot be fetched, show onboarding
            return true
        }
    }

    // MARK: - Flow
    func next() async {
        errorMessage = nil
        switch step {
        case .avatar:
            // Optional; upload if provided
            if pickedImageData != nil {
                await uploadAvatarAndSave()
                // If upload failed (e.g., RLS), stay on this step to surface the error.
                if errorMessage != nil { return }
            }
            step = .name
        case .name:
            await saveDisplayName()
            step = .group
        case .group:
            await handleGroup()
            step = .calendar
        case .calendar:
            await handleCalendarPreference()
            if errorMessage == nil {
                step = .done
            }
        case .done:
            onFinished?()
        }
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    // MARK: - DB helpers
    private func currentUID() async throws -> UUID {
        guard let session = try? await client.auth.session else {
            throw NSError(domain: "Onboarding", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing session"]) }
        return session.user.id
    }

    private func fetchUser(uid: UUID) async throws -> DBUser? {
        let rows: [DBUser] = try await client.database
            .from("users")
            .select()
            .eq("id", value: uid)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func ensureUserRow() async throws -> DBUser {
        let uid = try await currentUID()
        if let existing = try await fetchUser(uid: uid) { return existing }
        let insert = DBUser(id: uid, display_name: nil, avatar_url: nil, created_at: nil, updated_at: nil)
        _ = try await client.database.from("users").insert(insert).execute()
        return try await fetchUser(uid: uid) ?? insert
    }

    private func updateUser(displayName: String? = nil, avatarURL: URL? = nil) async throws {
        let uid = try await currentUID()
        var update = DBUserUpdate()
        if let displayName { update.display_name = displayName }
        if let avatarURL { update.avatar_url = avatarURL.absoluteString }
        _ = try await client.database
            .from("users")
            .update(update)
            .eq("id", value: uid)
            .execute()
    }

    // MARK: - Avatar
    private func uploadAvatarAndSave() async {
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            _ = try await ensureUserRow()
            guard let data = pickedImageData, !data.isEmpty else { return }
            
            // Upload to R2 via pre-signed URL (user ID is determined server-side from the auth token)
            let filename = R2StorageService.avatarFilename()
            let url = try await R2StorageService.shared.upload(
                data: data,
                filename: filename,
                folder: .avatars,
                contentType: "image/jpeg"
            )
            
            avatarPublicURL = url
            try await updateUser(avatarURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Name
    private func saveDisplayName() async {
        errorMessage = nil
        isSavingName = true
        defer { isSavingName = false }
        do {
            _ = try await ensureUserRow()
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            // Update auth user metadata
            let attributes = UserAttributes(data: ["display_name": AnyJSON.string(name)])
            _ = try await client.auth.update(user: attributes)
            // Mirror into public.users
            try await updateUser(displayName: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Groups
    private func handleGroup() async {
        errorMessage = nil
        isHandlingGroup = true
        defer { isHandlingGroup = false }
        do {
            let uid = try await currentUID()
            _ = try await ensureUserRow()

            switch groupMode {
            case .skip:
                return
            case .create:
                let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let payload = DBGroupInsert(name: name, created_by: uid)
                let groups: [DBGroup] = try await client.database
                    .from("groups")
                    .insert(payload)
                    .select()
                    .execute().value
                if let group = groups.first {
                    // Ensure membership as owner in case trigger wasn't installed
                    let member = DBGroupMember(group_id: group.id, user_id: uid, role: "owner", joined_at: nil)
                    _ = try? await client.database.from("group_members").insert(member).execute()
                }
            case .join:
                let slug = extractSlug(from: joinInput)
                guard !slug.isEmpty else { return }
                let found: [DBGroup] = try await client.database
                    .from("groups")
                    .select()
                    .eq("invite_slug", value: slug)
                    .limit(1)
                    .execute().value
                guard let group = found.first else { throw NSError(domain: "Onboarding", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid invite link"]) }
                let member = DBGroupMember(group_id: group.id, user_id: uid, role: "member", joined_at: nil)
                _ = try await client.database.from("group_members").insert(member).execute()
            }
        } catch {
            errorMessage = error.localizedDescription
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

    private func handleCalendarPreference() async {
        guard let calendarManager else {
            return
        }

        if wantsCalendarSync {
            let granted = await calendarManager.enableSyncFlow()
            if !granted {
                if calendarManager.authorizationStatus == .denied {
                    errorMessage = "Calendar access is denied. Enable access in Settings to sync your availability."
                } else {
                    errorMessage = calendarManager.lastSyncError ?? "We couldn't enable calendar sync right now."
                }
            }
        } else {
            calendarManager.disableSync()
        }
    }
}
