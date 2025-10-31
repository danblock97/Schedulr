//
//  AIUsageTracker.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import Foundation
import Supabase

@MainActor
final class AIUsageTracker {
    static let shared = AIUsageTracker()
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    private var cachedUsage: AIUsageInfo?
    private var lastFetchDate: Date?
    
    private init() {}
    
    // MARK: - Fetch Usage
    
    /// Get current AI usage for the billing period
    func getCurrentUsage() async -> AIUsageInfo? {
        // Return cached if fresh (within 30 seconds)
        if let cached = cachedUsage,
           let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < 30 {
            return cached
        }
        
        guard let client else {
            print("[AIUsageTracker] No client available")
            return nil
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            let result: [AIUsageInfo] = try await client.database.rpc(
                "get_current_ai_usage",
                params: ["p_user_id": userId]
            )
            .execute()
            .value
            
            if let usage = result.first {
                cachedUsage = usage
                lastFetchDate = Date()
                return usage
            }
            
        } catch {
            print("[AIUsageTracker] Error fetching usage: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Track an AI request
    func trackRequest() async {
        guard let client else {
            print("[AIUsageTracker] No client available to track request")
            return
        }
        
        do {
            let userId = try await getCurrentUserId()
            
            // Increment in database
            _ = try await client.database.rpc(
                "increment_ai_usage",
                params: ["p_user_id": userId]
            )
            .execute()
            
            // Update cache
            if var cached = cachedUsage {
                cached = AIUsageInfo(
                    requestCount: cached.requestCount + 1,
                    maxRequests: cached.maxRequests,
                    periodStart: cached.periodStart,
                    periodEnd: cached.periodEnd
                )
                cachedUsage = cached
            } else {
                // Fetch fresh data
                cachedUsage = await getCurrentUsage()
            }
            
            print("[AIUsageTracker] Tracked AI request")
            
        } catch {
            print("[AIUsageTracker] Error tracking request: \(error.localizedDescription)")
        }
    }
    
    /// Check if user can make an AI request
    func canMakeRequest() async -> Bool {
        guard let usage = await getCurrentUsage() else {
            // If we can't fetch usage, default to allowing for free tier
            return SubscriptionManager.shared.isPro
        }
        
        return usage.hasRemainingRequests
    }
    
    /// Get remaining requests
    func getRemainingRequests() async -> Int? {
        guard let usage = await getCurrentUsage() else { return nil }
        return usage.remainingRequests
    }
    
    /// Clear cache (useful after period change or user logout)
    func clearCache() {
        cachedUsage = nil
        lastFetchDate = nil
    }
    
    // MARK: - Helper
    
    private func getCurrentUserId() async throws -> UUID {
        guard let client else { throw AIUsageError.noClient }
        let session = try await client.auth.session
        return session.user.id
    }
}

// MARK: - AI Usage Error

enum AIUsageError: Error, LocalizedError {
    case noClient
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .noClient:
            return "Service unavailable"
        case .fetchFailed:
            return "Failed to fetch usage information"
        }
    }
}

