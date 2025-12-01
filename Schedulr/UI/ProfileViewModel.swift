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
    @Published var showingTransferOwnershipConfirmation: Bool = false
    @Published var showingDeleteGroupConfirmation: Bool = false
    @Published var groupToLeave: GroupMembership?
    @Published var groupToTransfer: GroupMembership?
    @Published var groupToDelete: GroupMembership?
    @Published var groupToRename: GroupMembership?
    @Published var newOwnerId: UUID?
    @Published var showingRenameGroupSheet: Bool = false
    @Published var newGroupName: String = ""

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    struct GroupMembership: Identifiable {
        let id: UUID
        var name: String
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

            // Upload to Supabase Storage using same path format as onboarding
            // This matches the pattern: {uid}/avatar_{timestamp}.jpg
            let fileName = "\(uid.uuidString)/avatar_\(Int(Date().timeIntervalSince1970)).jpg"

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
            // Provide more helpful error messages for RLS issues
            let errorString = String(describing: error)
            if errorString.contains("403") || errorString.contains("row-level security") {
                errorMessage = "Failed to upload avatar: Permission denied. Please ensure your storage bucket policies allow avatar uploads."
            } else {
                errorMessage = "Failed to upload avatar: \(error.localizedDescription)"
            }
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

            // Use GroupService to leave with proper cleanup
            try await GroupService.shared.leaveGroupWithCleanup(groupId: group.id, userId: uid)

            // Reload groups
            await loadUserProfile()

        } catch {
            errorMessage = "Failed to leave group: \(error.localizedDescription)"
            print("Error leaving group: \(error)")
        }

        isLoading = false
    }
    
    func transferOwnership(groupId: UUID, newOwnerId: UUID) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await GroupService.shared.transferOwnership(groupId: groupId, newOwnerId: newOwnerId)
            
            // Reload groups to reflect ownership change
            await loadUserProfile()
        } catch {
            errorMessage = "Failed to transfer ownership: \(error.localizedDescription)"
            print("Error transferring ownership: \(error)")
        }
        
        isLoading = false
    }
    
    func deleteGroup(_ group: GroupMembership) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await GroupService.shared.deleteGroup(groupId: group.id)
            
            // Reload groups to remove deleted group
            await loadUserProfile()
        } catch {
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
            print("Error deleting group: \(error)")
        }
        
        isLoading = false
    }
    
    func renameGroup(_ group: GroupMembership, newName: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await GroupService.shared.renameGroup(groupId: group.id, newName: newName)
            
            // Update local state immediately
            if let index = userGroups.firstIndex(where: { $0.id == group.id }) {
                userGroups[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            print("✅ Group renamed successfully")
        } catch {
            errorMessage = "Failed to rename group: \(error.localizedDescription)"
            print("Error renaming group: \(error)")
        }
        
        isLoading = false
        showingRenameGroupSheet = false
        groupToRename = nil
        newGroupName = ""
    }

    func deleteAccount() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let session = try await client.auth.session
            let accessToken = session.accessToken
            
            // Get Supabase URL from configuration
            guard let supabaseURL = SupabaseManager.shared.configuration?.url else {
                throw NSError(domain: "DeleteAccount", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get Supabase URL"])
            }
            
            // Call the Edge Function to delete the user account
            let url = supabaseURL.appendingPathComponent("functions/v1/delete-user-account")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeleteAccount", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if httpResponse.statusCode == 200 {
                print("✅ Account deleted successfully")
                isLoading = false
                return true
            } else {
                // Try to parse error message
                let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMsg = errorDict?["error"] as? String ?? "Failed to delete account"
                throw NSError(domain: "DeleteAccount", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }

        } catch {
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            print("❌ Error deleting account: \(error)")
            isLoading = false
            return false
        }
    }
    
    func saveTheme(_ theme: ColorTheme) async {
        do {
            let session = try await client.auth.session
            let uid = session.user.id
            
            try await ThemePreferencesManager.shared.save(theme, for: uid)
            print("✅ Theme saved successfully")
        } catch {
            print("❌ Error saving theme: \(error)")
            // Note: We don't set errorMessage here since theme picker handles its own errors
        }
    }
}
