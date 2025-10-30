import SwiftUI
import PhotosUI
import Supabase
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var avatarURL: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showingPhotoPicker: Bool = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var userGroups: [GroupMembership] = []
    @Published var showingLeaveGroupConfirmation: Bool = false
    @Published var showingDeleteAccountConfirmation: Bool = false
    @Published var groupToLeave: GroupMembership?

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    struct GroupMembership: Identifiable {
        let id: UUID
        let name: String
        let role: String?
    }

    func loadUserProfile() async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let uid = session.user.id

            // Fetch user data - this is the critical part
            do {
                let user: DBUser = try await client.database
                    .from("users")
                    .select()
                    .eq("id", value: uid)
                    .single()
                    .execute()
                    .value

                displayName = user.display_name ?? ""
                avatarURL = user.avatar_url
                print("✅ Profile loaded successfully: \(displayName)")
            } catch {
                print("❌ Error loading user profile: \(error)")
                throw error
            }

            // Fetch user's groups - not critical, can fail gracefully
            do {
                struct GroupMemberRow: Decodable {
                    let group_id: UUID
                    let role: String?
                    let joined_at: Date?
                    let groups: DBGroup?
                }

                let groupRows: [GroupMemberRow] = try await client.database
                    .from("group_members")
                    .select("group_id, role, joined_at, groups(id,name,invite_slug,created_at,created_by)")
                    .eq("user_id", value: uid)
                    .execute()
                    .value

                userGroups = groupRows.compactMap { row in
                    guard let group = row.groups else { return nil }
                    return GroupMembership(id: group.id, name: group.name, role: row.role)
                }
                print("✅ Loaded \(userGroups.count) groups")
            } catch {
                print("⚠️ Could not load groups: \(error)")
                userGroups = []
                // Don't throw - this is not critical
            }

        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
            print("❌ Profile load failed: \(error)")
        }

        isLoading = false
    }

    func updateDisplayName() async {
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name cannot be empty"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let uid = session.user.id

            let update = DBUserUpdate(display_name: displayName, avatar_url: nil)

            _ = try await client.database
                .from("users")
                .update(update)
                .eq("id", value: uid)
                .execute()

        } catch {
            errorMessage = "Failed to update name: \(error.localizedDescription)"
            print("Error updating name: \(error)")
        }

        isLoading = false
    }

    func uploadAvatar() async {
        guard let item = selectedPhotoItem else { return }

        isLoading = true
        errorMessage = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Failed to load image data"
                isLoading = false
                return
            }

            let session = try await client.auth.session
            let uid = session.user.id

            // Upload to Supabase Storage
            let fileName = "\(uid).jpg"

            _ = try await client.storage
                .from("avatars")
                .upload(
                    path: fileName,
                    file: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            // Get public URL
            let url = try client.storage.from("avatars").getPublicURL(path: fileName)

            // Update user record
            let update = DBUserUpdate(display_name: nil, avatar_url: url.absoluteString)

            _ = try await client.database
                .from("users")
                .update(update)
                .eq("id", value: uid)
                .execute()

            avatarURL = url.absoluteString

        } catch {
            errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
            print("Error uploading avatar: \(error)")
        }

        isLoading = false
        selectedPhotoItem = nil
    }

    func leaveGroup(_ group: GroupMembership) async {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let uid = session.user.id

            // Check if user is the owner
            if group.role == "owner" {
                errorMessage = "You cannot leave a group you created. Please delete the group or transfer ownership first."
                isLoading = false
                return
            }

            // Remove from group_members
            _ = try await client.database
                .from("group_members")
                .delete()
                .eq("user_id", value: uid)
                .eq("group_id", value: group.id)
                .execute()

            // Reload groups
            await loadUserProfile()

        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            print("Error leaving group: \(error)")
        }

        isLoading = false
    }

    func deleteAccount() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let uid = session.user.id

            // Delete user record (should cascade to group_members if DB is set up correctly)
            _ = try await client.database
                .from("users")
                .delete()
                .eq("id", value: uid)
                .execute()

            // Delete from auth
            // Note: Supabase client doesn't have a direct deleteUser method for self-deletion
            // This typically needs to be handled via a server-side function or admin API
            // For now, we'll sign out the user after deleting their data

            isLoading = false
            return true

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            print("Error deleting account: \(error)")
            isLoading = false
            return false
        }
    }
}
