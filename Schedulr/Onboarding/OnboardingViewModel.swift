import Foundation
import SwiftUI
import Supabase

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case avatar
        case name
        case group
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
    @Published var groupMode: GroupMode = .skip
    @Published var groupName: String = ""
    @Published var joinInput: String = ""
    @Published var isHandlingGroup: Bool = false

    // Errors
    @Published var errorMessage: String? = nil

    // Completion
    var onFinished: (() -> Void)?

    enum GroupMode: String, CaseIterable, Identifiable { case skip, create, join; var id: String { rawValue } }

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let avatarsBucket = "avatars"

    init(onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
    }

    // MARK: - Gating
    func needsOnboarding() async -> Bool {
        guard let session = client.auth.session else { return false }
        do {
            // Does users row exist?
            let user = try await fetchUser(uid: session.user.id)
            // If missing or missing display name, show onboarding
            return user == nil || (user?.display_name?.isEmpty ?? true)
        } catch {
            return true
        }
    }

    // MARK: - Flow
    func next() async {
        switch step {
        case .avatar:
            // Optional; upload if provided
            if pickedImageData != nil {
                await uploadAvatarAndSave()
            }
            step = .name
        case .name:
            await saveDisplayName()
            step = .group
        case .group:
            await handleGroup()
            step = .done
        case .done:
            onFinished?()
        }
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    // MARK: - DB helpers
    private func currentUID() throws -> UUID {
        guard let uid = client.auth.session?.user.id else { throw NSError(domain: "Onboarding", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing session"]) }
        return uid
    }

    private func fetchUser(uid: UUID) async throws -> DBUser? {
        let rows: [DBUser] = try await client.database
            .from("users")
            .select()
            .eq("id", uid)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func ensureUserRow() async throws -> DBUser {
        let uid = try currentUID()
        if let existing = try await fetchUser(uid: uid) { return existing }
        let insert = DBUser(id: uid, display_name: nil, avatar_url: nil, created_at: nil, updated_at: nil)
        _ = try await client.database.from("users").insert(values: insert).execute()
        return try await fetchUser(uid: uid) ?? insert
    }

    private func updateUser(displayName: String? = nil, avatarURL: URL? = nil) async throws {
        let uid = try currentUID()
        var update = DBUserUpdate()
        if let displayName { update.display_name = displayName }
        if let avatarURL { update.avatar_url = avatarURL.absoluteString }
        _ = try await client.database
            .from("users")
            .update(values: update)
            .eq("id", uid)
            .execute()
    }

    // MARK: - Avatar
    private func uploadAvatarAndSave() async {
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let uid = try currentUID()
            _ = try await ensureUserRow()
            guard let data = pickedImageData, !data.isEmpty else { return }
            let fileName = "\(uid.uuidString)/avatar_\(Int(Date().timeIntervalSince1970)).jpg"
            // Overwrite if exists
            _ = try await client.storage.from(avatarsBucket).upload(path: fileName, file: data, options: .init(upsert: true, contentType: "image/jpeg"))
            // Get a public URL (bucket should be public)
            if let url = client.storage.from(avatarsBucket).getPublicURL(path: fileName) {
                avatarPublicURL = url
                try await updateUser(avatarURL: url)
            }
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
            let uid = try currentUID()
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
            let uid = try currentUID()
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
                    .insert(values: payload)
                    .select()
                    .execute().value
                if let group = groups.first {
                    // Ensure membership as owner in case trigger wasn't installed
                    let member = DBGroupMember(group_id: group.id, user_id: uid, role: "owner", joined_at: nil)
                    _ = try? await client.database.from("group_members").insert(values: member).execute()
                }
            case .join:
                let slug = extractSlug(from: joinInput)
                guard !slug.isEmpty else { return }
                let found: [DBGroup] = try await client.database
                    .from("groups")
                    .select()
                    .eq("invite_slug", slug)
                    .limit(1)
                    .execute().value
                guard let group = found.first else { throw NSError(domain: "Onboarding", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid invite link"]) }
                let member = DBGroupMember(group_id: group.id, user_id: uid, role: "member", joined_at: nil)
                _ = try await client.database.from("group_members").insert(values: member).execute()
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
}
