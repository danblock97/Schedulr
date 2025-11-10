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
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            return nil
        }
        
        guard let apiKey = plist["REVENUECAT_API_KEY"] as? String,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        return apiKey
    }
    
    // MARK: - User Identification
    
    /// Identifies the current user with RevenueCat using their Supabase user ID
    /// This should be called after successful authentication to link RevenueCat customer ID with Supabase user ID
    func identifyUser() async {
        guard getRevenueCatAPIKey() != nil else { return }
        
        guard let client else {
            print("[SubscriptionManager] No Supabase client available for user identification")
            return
        }
        
        do {
            let session = try await client.auth.session
            let userId = session.user.id.uuidString
            
            // Identify user with RevenueCat
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            print("[SubscriptionManager] Identified user with RevenueCat: \(userId)")
            
            // Update subscription info from RevenueCat
            await updateFromCustomerInfo(customerInfo)
            
            // Sync to Supabase to ensure database is up to date
            try await syncSubscriptionToSupabase(userId: session.user.id, customerInfo: customerInfo)
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
                
                // Only sync with RevenueCat if it's configured
                if getRevenueCatAPIKey() != nil {
                    do {
                        try await syncWithRevenueCat(userId: userId)
                    } catch {
                        // If RevenueCat sync fails, continue with Supabase data
                        print("[SubscriptionManager] RevenueCat sync failed, using Supabase data only: \(error.localizedDescription)")
                    }
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
            errorMessage = "Purchase failed: \(error.localizedDescription)"
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
    
    private func syncWithRevenueCat(userId: UUID) async throws {
        guard let client else { return }
        
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
        let hasProEntitlement = customerInfo.entitlements.all["pro"]?.isActive == true
        
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
        
        // Determine subscription state from RevenueCat
        let hasProEntitlement = customerInfo.entitlements.all["pro"]?.isActive == true
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

