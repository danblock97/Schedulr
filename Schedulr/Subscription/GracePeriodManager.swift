//
//  GracePeriodManager.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import Foundation
import Supabase

@MainActor
final class GracePeriodManager {
    static let shared = GracePeriodManager()
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    private init() {}
    
    // MARK: - Check and Enforce
    
    /// Check if user is in grace period
    func isInGracePeriod() async -> Bool {
        return await SubscriptionManager.shared.isInGracePeriod
    }
    
    /// Get grace period information
    func getGracePeriodInfo() async -> GracePeriodInfo? {
        return await SubscriptionLimitService.shared.getGracePeriodInfo()
    }
    
    /// Enforce subscription limits after grace period ends
    func enforceLimits() async throws {
        guard let client else {
            throw GracePeriodError.noClient
        }
        
        do {
            // Call database function to enforce limits
            _ = try await client.database.rpc("enforce_subscription_limits_after_grace_period")
                .execute()
            
            // Refresh subscription status
            await SubscriptionManager.shared.fetchSubscriptionStatus()
            
            print("[GracePeriodManager] Enforced subscription limits")
            
        } catch {
            print("[GracePeriodManager] Error enforcing limits: \(error.localizedDescription)")
            throw GracePeriodError.enforcementFailed
        }
    }
    
    /// Check and enforce if needed on app launch
    func checkAndEnforceIfNeeded() async {
        // First check grace period status
        guard await isInGracePeriod() else {
            return
        }
        
        guard let info = await getGracePeriodInfo() else {
            return
        }
        
        // If grace period has ended, enforce limits
        if info.hasEnded {
            do {
                try await enforceLimits()
            } catch {
                print("[GracePeriodManager] Failed to enforce limits: \(error.localizedDescription)")
            }
        }
    }
    
    /// Get remaining days in grace period
    func getDaysRemaining() async -> Int? {
        guard let info = await getGracePeriodInfo() else {
            return nil
        }
        
        return info.daysRemaining
    }
    
    /// Get notification message about grace period
    func getGracePeriodMessage() async -> String? {
        guard await isInGracePeriod(),
              let daysRemaining = await getDaysRemaining() else {
            return nil
        }
        
        if daysRemaining == 0 {
            return "Your grace period ends today. Please reduce your groups or members to comply with your plan limits."
        } else if daysRemaining == 1 {
            return "Your grace period ends tomorrow. Please take action to comply with your plan limits."
        } else {
            return "You have \(daysRemaining) days remaining to comply with your plan limits."
        }
    }
}

// MARK: - Grace Period Error

enum GracePeriodError: Error, LocalizedError {
    case noClient
    case enforcementFailed
    case notInGracePeriod
    
    var errorDescription: String? {
        switch self {
        case .noClient:
            return "Service unavailable"
        case .enforcementFailed:
            return "Failed to enforce subscription limits"
        case .notInGracePeriod:
            return "Not currently in grace period"
        }
    }
}

