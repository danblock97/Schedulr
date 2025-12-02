import Foundation
import Supabase

/// Service for managing group operations: ownership transfer, deletion, and member leave with cleanup
final class GroupService {
    static let shared = GroupService()
    
    private init() {}
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    /// Transfer group ownership from current owner to another member
    /// - Parameters:
    ///   - groupId: The group ID
    ///   - newOwnerId: The user ID of the new owner
    /// - Throws: Error if transfer fails (user not owner, new owner not member, only one member, etc.)
    nonisolated func transferOwnership(groupId: UUID, newOwnerId: UUID) async throws {
        let session = try await client.auth.session
        let currentUserId = session.user.id
        
        try await client.database.rpc(
            "transfer_group_ownership",
            params: ["p_group_id": groupId, "p_new_owner_id": newOwnerId]
        ).execute()
        
        // Notify the new owner about the ownership transfer
        NotificationService.shared.notifyGroupOwnershipTransfer(groupId: groupId, newOwnerUserId: newOwnerId, actorUserId: currentUserId)
    }
    
    /// Delete a group (only allowed if owner is the sole member)
    /// - Parameter groupId: The group ID
    /// - Throws: Error if deletion fails (user not owner, multiple members, etc.)
    nonisolated func deleteGroup(groupId: UUID) async throws {
        let session = try await client.auth.session
        let currentUserId = session.user.id
        
        // Verify user is owner and count members
        struct MemberRow: Decodable {
            let user_id: UUID
            let role: String?
        }
        
        let members: [MemberRow] = try await client.database
            .from("group_members")
            .select("user_id, role")
            .eq("group_id", value: groupId)
            .execute()
            .value
        
        guard let currentMember = members.first(where: { $0.user_id == currentUserId }),
              currentMember.role == "owner" else {
            throw NSError(
                domain: "GroupService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Only the group owner can delete the group"]
            )
        }
        
        guard members.count == 1 else {
            throw NSError(
                domain: "GroupService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot delete group with multiple members. Transfer ownership or remove members first."]
            )
        }
        
        // Delete the group (cascade will handle related records)
        try await client.database
            .from("groups")
            .delete()
            .eq("id", value: groupId)
            .execute()
    }
    
    /// Leave a group and clean up event attendees
    /// - Parameters:
    ///   - groupId: The group ID
    ///   - userId: The user ID leaving the group
    /// - Throws: Error if leave fails
    nonisolated func leaveGroupWithCleanup(groupId: UUID, userId: UUID) async throws {
        // Call cleanup function
        try await client.database.rpc(
            "cleanup_event_attendees_on_leave",
            params: ["p_group_id": groupId, "p_user_id": userId]
        ).execute()
        
        // Remove user's membership
        try await client.database
            .from("group_members")
            .delete()
            .eq("group_id", value: groupId)
            .eq("user_id", value: userId)
            .execute()
    }
    
    /// Get member count for a group
    /// - Parameter groupId: The group ID
    /// - Returns: The number of members in the group
    nonisolated func getMemberCount(groupId: UUID) async throws -> Int {
        let count = try await client.database
            .from("group_members")
            .select("*", head: true, count: .exact)
            .eq("group_id", value: groupId)
            .execute()
            .count
        
        return count ?? 0
    }
    
    /// Rename a group (only allowed by owner)
    /// - Parameters:
    ///   - groupId: The group ID
    ///   - newName: The new name for the group
    /// - Throws: Error if rename fails (user not owner, invalid name, etc.)
    nonisolated func renameGroup(groupId: UUID, newName: String) async throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw NSError(
                domain: "GroupService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Group name cannot be empty"]
            )
        }
        
        guard trimmedName.count <= 100 else {
            throw NSError(
                domain: "GroupService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Group name cannot exceed 100 characters"]
            )
        }
        
        let session = try await client.auth.session
        let currentUserId = session.user.id
        
        // Call the rename_group function using AnyJSON for mixed types
        struct RenameParams: Encodable {
            let p_group_id: UUID
            let p_new_name: String
        }
        
        try await client.database.rpc(
            "rename_group",
            params: RenameParams(p_group_id: groupId, p_new_name: trimmedName)
        ).execute()
        
        // Notify group members about the rename
        NotificationService.shared.notifyGroupRenamed(groupId: groupId, newName: trimmedName, renamedByUserId: currentUserId)
    }
    
    /// Delete a group and notify members (only allowed if owner is the sole member)
    /// Note: For groups with multiple members, use the regular deleteGroup method
    /// - Parameters:
    ///   - groupId: The group ID
    ///   - groupName: The group name (for notification)
    ///   - memberUserIds: List of member user IDs to notify (fetch before deletion)
    /// - Throws: Error if deletion fails
    nonisolated func deleteGroupWithNotification(groupId: UUID, groupName: String, memberUserIds: [UUID]) async throws {
        let session = try await client.auth.session
        let currentUserId = session.user.id
        
        // Notify members BEFORE deleting (they need to know the group name)
        NotificationService.shared.notifyGroupDeleted(groupName: groupName, memberUserIds: memberUserIds, deletedByUserId: currentUserId)
        
        // Now delete the group
        try await deleteGroup(groupId: groupId)
    }
}

