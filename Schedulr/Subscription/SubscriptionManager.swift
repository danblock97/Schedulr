//
//  SubscriptionManager.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import Foundation
import RevenueCat
import Combine
import Supabase

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // Published state
    @Published private(set) var subscriptionInfo: UserSubscriptionInfo?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentOffering: Offering?
    
    private let defaultProEntitlementId = "pro"
    private var proEntitlementId: String = "pro"
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    private var configureTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Configuration
    
    func configure() async {
        guard configureTask == nil else { return }
        
        configureTask = Task {
            do {
                guard let apiKey = getRevenueCatAPIKey() else {
                    print("[SubscriptionManager] RevenueCat API key not found in Info.plist")
                    return
                }
                if let configuredEntitlement = getRevenueCatProEntitlementId() {
                    proEntitlementId = configuredEntitlement
                } else {
                    proEntitlementId = defaultProEntitlementId
                    #if DEBUG
                    print("[SubscriptionManager] Pro entitlement identifier not found in Info.plist, defaulting to '\(defaultProEntitlementId)'")
                    #endif
                }
                
                // Configure RevenueCat with your API key
                Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey).build())
                
                // Fetch initial subscription status
                await fetchSubscriptionStatus()
                
                // Load available offerings
                await loadOfferings()
            } catch {
                print("[SubscriptionManager] Configuration error: \(error.localizedDescription)")
                errorMessage = "Failed to configure subscriptions: \(error.localizedDescription)"
            }
        }
        
        await configureTask?.value
    }
    
    private func getRevenueCatAPIKey() -> String? {
        getInfoPlistString(for: "REVENUECAT_API_KEY")
    }
    
    private func getRevenueCatProEntitlementId() -> String? {
        getInfoPlistString(for: "REVENUECAT_PRO_ENTITLEMENT")
    }
    
    private func getInfoPlistString(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let value = plist[key] as? String else {
            return nil
        }
        
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        
        trimmed = trimmed.replacingOccurrences(of: "\\ ", with: " ")
        return trimmed
    }
    
    // MARK: - User Identification
    
    /// Identifies the current user with RevenueCat using their Supabase user ID
    /// This should be called after successful authentication to link RevenueCat customer ID with Supabase user ID
    /// Skips identification for manual pro users (revenuecat_customer_id is NULL or 'manual')
    func identifyUser() async {
        guard getRevenueCatAPIKey() != nil else { return }
        
        guard let client else {
            print("[SubscriptionManager] No Supabase client available for user identification")
            return
        }
        
        do {
            let session = try await client.auth.session
            let userId = session.user.id
            
            // Fetch current user info to check if they're a manual pro user
            let user: DBUser = try await client.database
                .from("users")
                .select("revenuecat_customer_id,subscription_tier")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            // Skip RevenueCat identification for manual pro users only
            // (users who are pro tier with NULL or 'manual' customer ID)
            // New users with free tier and NULL customer ID should still go through RevenueCat
            if isManualProUser(revenuecatCustomerId: user.revenuecat_customer_id, subscriptionTier: user.subscription_tier) {
                print("[SubscriptionManager] Skipping RevenueCat identification for manual pro user")
                return
            }
            
            // Identify user with RevenueCat
            let (customerInfo, _) = try await Purchases.shared.logIn(userId.uuidString)
            print("[SubscriptionManager] Identified user with RevenueCat: \(userId.uuidString)")
            
            // Update subscription info from RevenueCat
            await updateFromCustomerInfo(customerInfo)
            
            // Sync to Supabase to ensure database is up to date
            try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
        } catch {
            print("[SubscriptionManager] Failed to identify user with RevenueCat: \(error.localizedDescription)")
            // Don't throw - allow app to continue
        }
    }
    
    // MARK: - Fetch Subscription Status
    
    func fetchSubscriptionStatus() async {
        // Guard against concurrent fetches
        guard fetchTask == nil else {
            await fetchTask?.value
            return
        }
        
        guard let client else {
            print("[SubscriptionManager] No Supabase client available")
            return
        }
        
        fetchTask = Task {
            isLoading = true
            errorMessage = nil
            defer { 
                isLoading = false
                fetchTask = nil
            }
            
            do {
                // Get current user ID
                let session = try await client.auth.session
                let userId = session.user.id
                
                // Fetch user subscription info from Supabase
                let user: DBUser = try await client.database
                    .from("users")
                    .select("id,subscription_tier,subscription_status,revenuecat_customer_id,subscription_updated_at,downgrade_grace_period_ends")
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                
                // Convert to UserSubscriptionInfo
                if let tierString = user.subscription_tier,
                   let tier = SubscriptionTier(rawValue: tierString),
                   let statusString = user.subscription_status,
                   let status = SubscriptionStatus(rawValue: statusString) {
                    subscriptionInfo = UserSubscriptionInfo(
                        tier: tier,
                        status: status,
                        revenuecatCustomerId: user.revenuecat_customer_id,
                        subscriptionUpdatedAt: user.subscription_updated_at,
                        downgradeGracePeriodEnds: user.downgrade_grace_period_ends
                    )
                } else {
                    subscriptionInfo = UserSubscriptionInfo(
                        tier: .free,
                        status: .active,
                        revenuecatCustomerId: nil,
                        subscriptionUpdatedAt: nil,
                        downgradeGracePeriodEnds: nil
                    )
                }
                
                // Only sync with RevenueCat if it's configured and user is not a manual pro user
                // Check using the tier from the database to distinguish manual pro from new users
                if getRevenueCatAPIKey() != nil, !isManualProUser(revenuecatCustomerId: subscriptionInfo?.revenuecatCustomerId, subscriptionTier: user.subscription_tier) {
                    do {
                        try await syncWithRevenueCat(userId: userId)
                    } catch {
                        // If RevenueCat sync fails, continue with Supabase data
                        print("[SubscriptionManager] RevenueCat sync failed, using Supabase data only: \(error.localizedDescription)")
                    }
                } else if isManualProUser(revenuecatCustomerId: subscriptionInfo?.revenuecatCustomerId, subscriptionTier: user.subscription_tier) {
                    print("[SubscriptionManager] Skipping RevenueCat sync for manual pro user")
                }
                
            } catch {
                print("[SubscriptionManager] Failed to fetch subscription status: \(error.localizedDescription)")
                errorMessage = "Failed to load subscription status"
            }
        }
        
        await fetchTask?.value
    }
    
    // MARK: - Load Offerings
    
    private func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
            
            print("[SubscriptionManager] Loaded \(offerings.current?.availablePackages.count ?? 0) packages")
        } catch {
            print("[SubscriptionManager] Failed to load offerings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Purchase Subscription
    
    func purchaseSubscription(_ package: Package) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Ensure user is identified with RevenueCat before purchase
            await identifyUser()
            
            // Attempt purchase - RevenueCat will handle sandbox receipt validation automatically
            // If production app gets sandbox receipt, RevenueCat's server will validate against sandbox environment
            let (transaction, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
            
            if userCancelled {
                print("[SubscriptionManager] Purchase cancelled by user")
                return false
            }
            
            print("[SubscriptionManager] Purchase completed successfully")
            
            // Update subscription info from RevenueCat response
            await updateFromCustomerInfo(customerInfo)
            
            // Sync with Supabase - ensure this completes successfully
            do {
                let userId = try await getCurrentUserId()
                try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
                print("[SubscriptionManager] Successfully synced purchase to Supabase")
            } catch {
                // Retry sync once after a short delay
                print("[SubscriptionManager] Initial sync failed, retrying: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                do {
                    let userId = try await getCurrentUserId()
                    try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
                    print("[SubscriptionManager] Retry sync successful")
                } catch {
                    print("[SubscriptionManager] Retry sync failed: \(error.localizedDescription)")
                    // Even if sync fails, purchase was successful, so we continue
                    // The sync will be retried on next app launch or when fetchSubscriptionStatus is called
                }
            }
            
            // Refresh subscription status to ensure local state is up to date
            await fetchSubscriptionStatus()
            
            print("[SubscriptionManager] Purchase flow completed successfully")
            return true
            
        } catch {
            print("[SubscriptionManager] Purchase error: \(error.localizedDescription)")
            print("[SubscriptionManager] Error type: \(type(of: error))")
            
            // Provide more specific error messages based on error description
            let errorString = error.localizedDescription.lowercased()
            let errorDescription = error.localizedDescription
            
            // Check for user cancellation (don't show error)
            if errorString.contains("cancelled") || errorString.contains("canceled") {
                errorMessage = nil
                return false
            }
            
            // Check for sandbox receipt errors (common during App Review)
            if errorString.contains("sandbox") || 
               errorDescription.contains("Sandbox receipt used in production") ||
               errorString.contains("test environment") {
                errorMessage = "Please ensure you're signed in with a test account. If this persists, try restoring purchases."
                return false
            }
            
            // Check for network errors
            if errorString.contains("network") || 
               errorString.contains("internet") ||
               errorString.contains("connection") ||
               errorString.contains("timeout") {
                errorMessage = "Network error. Please check your internet connection and try again."
                return false
            }
            
            // Check for product availability errors
            if errorString.contains("not available") || 
               errorString.contains("unavailable") ||
               errorString.contains("product not found") {
                errorMessage = "This subscription is not available. Please try again later."
                return false
            }
            
            // Check for purchase not allowed errors
            if errorString.contains("not allowed") || 
               errorString.contains("purchases disabled") ||
               errorString.contains("restrictions") {
                errorMessage = "Purchases are not allowed on this device. Please check your device settings."
                return false
            }
            
            // Check for receipt errors
            if errorString.contains("receipt") && 
               (errorString.contains("invalid") || errorString.contains("error")) {
                errorMessage = "There was an issue validating your purchase. Please try again or contact support."
                return false
            }
            
            // Generic error message for unknown errors
            errorMessage = "Purchase failed. Please try again or contact support if the problem persists."
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Ensure user is identified with RevenueCat before restore
            await identifyUser()
            
            let customerInfo = try await Purchases.shared.restorePurchases()
            
            // Update subscription info
            await updateFromCustomerInfo(customerInfo)
            
            // Sync with Supabase - ensure this completes successfully
            do {
                let userId = try await getCurrentUserId()
                try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
                print("[SubscriptionManager] Successfully synced restored purchases to Supabase")
            } catch {
                // Retry sync once after a short delay
                print("[SubscriptionManager] Initial restore sync failed, retrying: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                do {
                    let userId = try await getCurrentUserId()
                    try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
                    print("[SubscriptionManager] Retry restore sync successful")
                } catch {
                    print("[SubscriptionManager] Retry restore sync failed: \(error.localizedDescription)")
                    // Even if sync fails, restore was successful, so we continue
                }
            }
            
            // Refresh subscription status to ensure local state is up to date
            await fetchSubscriptionStatus()
            
            print("[SubscriptionManager] Restored purchases")
            return true
            
        } catch {
            print("[SubscriptionManager] Restore error: \(error.localizedDescription)")
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    /// Checks if a user has manual pro override
    /// A user is a manual pro if:
    /// 1. revenuecat_customer_id is 'manual', OR
    /// 2. revenuecat_customer_id is NULL AND subscription_tier is 'pro'
    /// This distinguishes manual pro users (pro tier with NULL customer ID) from new users (free tier with NULL customer ID)
    private func isManualProUser(revenuecatCustomerId: String?, subscriptionTier: String? = nil) -> Bool {
        // 'manual' marker always means manual pro
        if let customerId = revenuecatCustomerId, customerId == "manual" {
            return true
        }
        
        // NULL customer ID + pro tier = manual pro
        // NULL customer ID + free tier = new user (not manual pro)
        if revenuecatCustomerId == nil {
            // If tier is provided, check it; otherwise assume manual pro for safety (preserves existing behavior)
            if let tier = subscriptionTier {
                return tier == "pro"
            }
            // If tier not provided, we can't determine - default to false to allow normal flow
            // This is safer for purchases
            return false
        }
        
        return false
    }
    
    private func syncWithRevenueCat(userId: UUID) async throws {
        guard let client else { return }
        
        // Skip sync for manual pro users
        // Note: subscriptionInfo might be stale, so we check it but syncSubscriptionToSupabase will do a fresh DB check
        if let info = subscriptionInfo, isManualProUser(revenuecatCustomerId: info.revenuecatCustomerId, subscriptionTier: info.tier.rawValue) {
            print("[SubscriptionManager] Skipping RevenueCat sync for manual pro user")
            return
        }
        
        do {
            // Identify user with RevenueCat first
            let (customerInfo, _) = try await Purchases.shared.logIn(userId.uuidString)
            
            // Sync to Supabase
            try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
            
        } catch {
            print("[SubscriptionManager] RevenueCat sync error: \(error.localizedDescription)")
            // Don't throw - allow app to continue with local data
        }
    }
    
    private func updateFromCustomerInfo(_ customerInfo: CustomerInfo) async {
        // Determine tier from entitlements
        let hasProEntitlement = hasActiveProEntitlement(customerInfo)
        
        let tier: SubscriptionTier = hasProEntitlement ? .pro : .free
        let status: SubscriptionStatus = hasProEntitlement ? .active : .expired
        
        subscriptionInfo = UserSubscriptionInfo(
            tier: tier,
            status: status,
            revenuecatCustomerId: customerInfo.originalAppUserId,
            subscriptionUpdatedAt: Date(),
            downgradeGracePeriodEnds: nil
        )
    }
    
    private func syncSubscriptionToSupabase(userId: UUID, customerInfo: CustomerInfo) async throws {
        guard let client else { 
            print("[SubscriptionManager] Cannot sync: No Supabase client available")
            throw SubscriptionError.noClient 
        }
        
        // Check database directly to see if user has manual pro override
        // This ensures we check the current database state, not stale cached data
        let currentUser: DBUser = try await client.database
            .from("users")
            .select("revenuecat_customer_id,subscription_tier")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        
        // If user is a manual pro user, preserve their current tier and skip RevenueCat sync
        if isManualProUser(revenuecatCustomerId: currentUser.revenuecat_customer_id, subscriptionTier: currentUser.subscription_tier) {
            print("[SubscriptionManager] Preserving manual pro tier (tier: \(currentUser.subscription_tier ?? "unknown")), skipping RevenueCat sync")
            return
        }
        
        // Determine subscription state from RevenueCat
        let hasProEntitlement = hasActiveProEntitlement(customerInfo)
        let tier = hasProEntitlement ? "pro" : "free"
        let status = hasProEntitlement ? "active" : "expired"
        
        print("[SubscriptionManager] Syncing subscription to Supabase - User: \(userId), Tier: \(tier), Status: \(status)")
        
        // Create an encodable struct for the update
        struct SubscriptionUpdate: Encodable {
            let subscription_tier: String
            let subscription_status: String
            let revenuecat_customer_id: String
            let subscription_updated_at: String
        }
        
        let update = SubscriptionUpdate(
            subscription_tier: tier,
            subscription_status: status,
            revenuecat_customer_id: customerInfo.originalAppUserId,
            subscription_updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            try await client.database
                .from("users")
                .update(update)
                .eq("id", value: userId)
                .execute()
            
            print("[SubscriptionManager] Successfully synced subscription to Supabase - User: \(userId), Tier: \(tier), Status: \(status)")
        } catch {
            print("[SubscriptionManager] Failed to sync subscription to Supabase: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func getCurrentUserId() async throws -> UUID {
        guard let client else { throw SubscriptionError.noClient }
        let session = try await client.auth.session
        return session.user.id
    }
    
    private func hasActiveProEntitlement(_ customerInfo: CustomerInfo) -> Bool {
        if customerInfo.entitlements.all[proEntitlementId]?.isActive == true {
            return true
        }
        if proEntitlementId != defaultProEntitlementId,
           customerInfo.entitlements.all[defaultProEntitlementId]?.isActive == true {
            return true
        }
        return false
    }
    
    // MARK: - Convenience Properties
    
    var currentTier: SubscriptionTier {
        subscriptionInfo?.tier ?? .free
    }
    
    var currentLimits: SubscriptionLimits {
        SubscriptionLimits(for: currentTier)
    }
    
    var isPro: Bool {
        currentTier == .pro
    }
    
    var isInGracePeriod: Bool {
        subscriptionInfo?.isInGracePeriod ?? false
    }
}

// MARK: - Note on Subscription Updates
// RevenueCat subscription updates are handled via polling when:
// 1. App launches (via SchedulrApp)
// 2. User authenticates (via AuthViewModel)
// 3. After purchase/restore operations
// No delegate needed since we're using @MainActor class

// MARK: - Errors

enum SubscriptionError: Error, LocalizedError {
    case noClient
    case noSubscription
    case purchaseFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noClient:
            return "Subscription service is not available"
        case .noSubscription:
            return "No active subscription found"
        case .purchaseFailed(let message):
            return "Purchase failed: \(message)"
        }
    }
}

