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
        try await client.database.rpc(
            "transfer_group_ownership",
            params: ["p_group_id": groupId, "p_new_owner_id": newOwnerId]
        ).execute()
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
}

