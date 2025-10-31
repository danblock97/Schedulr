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
        
        return plist["REVENUECAT_API_KEY"] as? String
    }
    
    // MARK: - Fetch Subscription Status
    
    func fetchSubscriptionStatus() async {
        guard let client else {
            print("[SubscriptionManager] No Supabase client available")
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Get current user ID
            let session = try await client.auth.session
            let userId = session.user.id
            
            // Fetch user subscription info from Supabase
            let user: DBUser = try await client.database
                .from("users")
                .select("subscription_tier,subscription_status,revenuecat_customer_id,subscription_updated_at,downgrade_grace_period_ends")
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
            
            // Also fetch from RevenueCat to sync
            try await syncWithRevenueCat(userId: userId)
            
        } catch {
            print("[SubscriptionManager] Failed to fetch subscription status: \(error.localizedDescription)")
            errorMessage = "Failed to load subscription status"
        }
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
            let (transaction, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
            
            if userCancelled {
                return false
            }
            
            // Update subscription info from RevenueCat response
            await updateFromCustomerInfo(customerInfo)
            
            // Sync with Supabase
            if let userId = try? await getCurrentUserId() {
                try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
            }
            
            print("[SubscriptionManager] Purchase successful")
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
            let customerInfo = try await Purchases.shared.restorePurchases()
            
            // Update subscription info
            await updateFromCustomerInfo(customerInfo)
            
            // Sync with Supabase
            if let userId = try? await getCurrentUserId() {
                try await syncSubscriptionToSupabase(userId: userId, customerInfo: customerInfo)
            }
            
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
            // Get customer info from RevenueCat
            let customerInfo = try await Purchases.shared.customerInfo()
            
            // Identify user if we have their user ID
            try await Purchases.shared.logIn(userId.uuidString)
            
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
        guard let client else { throw SubscriptionError.noClient }
        
        // Determine subscription state from RevenueCat
        let hasProEntitlement = customerInfo.entitlements.all["pro"]?.isActive == true
        let tier = hasProEntitlement ? "pro" : "free"
        let status = hasProEntitlement ? "active" : "expired"
        
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
        
        try await client.database
            .from("users")
            .update(update)
            .eq("id", value: userId)
            .execute()
        
        print("[SubscriptionManager] Synced subscription to Supabase")
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

