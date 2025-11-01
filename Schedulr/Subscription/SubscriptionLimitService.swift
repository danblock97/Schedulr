//
//  SubscriptionLimitService.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import Foundation
import Supabase

@MainActor
final class SubscriptionLimitService {
    static let shared = SubscriptionLimitService()
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    private init() {}
    
    // MARK: - Group Limits
    
    /// Check if user can join a new group
    func canJoinGroup() async -> LimitCheckResult {
        guard let client else {
            return LimitCheckResult(canProceed: false, reason: "Service unavailable")
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [GroupLimitCheck] = try await client.database.rpc(
                "can_user_join_group",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            guard let check = result.first else {
                return LimitCheckResult(canProceed: false, reason: "Unable to check limits")
            }
            
            if check.canJoin {
                return LimitCheckResult(canProceed: true, reason: nil)
            } else {
                return LimitCheckResult(
                    canProceed: false,
                    reason: check.reason ?? "Group limit reached"
                )
            }
            
        } catch {
            print("[SubscriptionLimitService] Error checking group limit: \(error.localizedDescription)")
            return LimitCheckResult(canProceed: false, reason: "Unable to check limits")
        }
    }
    
    /// Check if user can join a new group and return full limit check details
    func canJoinGroupWithDetails() async -> GroupLimitCheck? {
        guard let client else {
            return nil
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [GroupLimitCheck] = try await client.database.rpc(
                "can_user_join_group",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            return result.first
            
        } catch {
            print("[SubscriptionLimitService] Error checking group limit: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get current group count and limit
    func getGroupLimitInfo() async -> (current: Int, max: Int)? {
        guard let client else { return nil }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [GroupLimitCheck] = try await client.database.rpc(
                "can_user_join_group",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            guard let check = result.first else { return nil }
            return (check.currentCount, check.maxAllowed)
            
        } catch {
            print("[SubscriptionLimitService] Error getting group limit info: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Member Limits
    
    /// Check if a group can add a new member
    func canGroupAddMember(groupId: UUID) async -> LimitCheckResult {
        guard let client else {
            return LimitCheckResult(canProceed: false, reason: "Service unavailable")
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [MemberLimitCheck] = try await client.database.rpc(
                "can_group_add_member",
                params: ["p_group_id": groupId, "p_user_adding": userId]
            )
            .execute()
            .value
            
            guard let check = result.first else {
                return LimitCheckResult(canProceed: false, reason: "Unable to check limits")
            }
            
            if check.canAdd {
                return LimitCheckResult(canProceed: true, reason: nil)
            } else {
                return LimitCheckResult(
                    canProceed: false,
                    reason: check.reason ?? "Member limit reached"
                )
            }
            
        } catch {
            print("[SubscriptionLimitService] Error checking member limit: \(error.localizedDescription)")
            return LimitCheckResult(canProceed: false, reason: "Unable to check limits")
        }
    }
    
    /// Get current member count and limit for a group
    func getMemberLimitInfo(groupId: UUID) async -> (current: Int, max: Int)? {
        guard let client else { return nil }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [MemberLimitCheck] = try await client.database.rpc(
                "can_group_add_member",
                params: ["p_group_id": groupId, "p_user_adding": userId]
            )
            .execute()
            .value
            
            guard let check = result.first else { return nil }
            return (check.currentCount, check.maxAllowed)
            
        } catch {
            print("[SubscriptionLimitService] Error getting member limit info: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - AI Limits
    
    /// Check if user can use AI
    func canUseAI() async -> (canUse: Bool, remaining: Int?) {
        guard let client else {
            return (false, nil)
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [AIUsageInfo] = try await client.database.rpc(
                "get_current_ai_usage",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            guard let usage = result.first else {
                return (false, nil)
            }
            
            let canUse = usage.hasRemainingRequests
            let remaining = usage.remainingRequests
            
            return (canUse, remaining)
            
        } catch {
            print("[SubscriptionLimitService] Error checking AI limit: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    /// Get detailed AI usage information
    func getAIUsageInfo() async -> AIUsageInfo? {
        guard let client else { return nil }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [AIUsageInfo] = try await client.database.rpc(
                "get_current_ai_usage",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            return result.first
            
        } catch {
            print("[SubscriptionLimitService] Error getting AI usage info: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Track AI request
    func trackAIRequest() async {
        guard let client else {
            print("[SubscriptionLimitService] No client available to track AI request")
            return
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            _ = try await client.database.rpc(
                "increment_ai_usage",
                params: ["p_user_id": userId]
            )
            .execute()
            
            print("[SubscriptionLimitService] Tracked AI request")
            
        } catch {
            print("[SubscriptionLimitService] Error tracking AI request: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Grace Period
    
    /// Check grace period status
    func getGracePeriodInfo() async -> GracePeriodInfo? {
        let subscriptionInfo = SubscriptionManager.shared.subscriptionInfo
        
        guard let info = subscriptionInfo,
              let daysRemaining = info.daysRemainingInGracePeriod else {
            return nil
        }
        
        return GracePeriodInfo(
            isInGracePeriod: info.isInGracePeriod,
            daysRemaining: daysRemaining,
            gracePeriodEnds: info.downgradeGracePeriodEnds
        )
    }
    
    // MARK: - Helper
    
    private func getCurrentUserId() async throws -> UUID {
        guard let client else { throw LimitServiceError.noClient }
        let session = try await client.auth.session
        return session.user.id
    }
}

// MARK: - Errors

enum LimitServiceError: Error, LocalizedError {
    case noClient
    case limitExceeded
    case gracePeriodActive
    
    var errorDescription: String? {
        switch self {
        case .noClient:
            return "Subscription service is not available"
        case .limitExceeded:
            return "You've reached your plan's limit"
        case .gracePeriodActive:
            return "You're in a grace period"
        }
    }
}

