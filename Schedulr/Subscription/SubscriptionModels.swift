//
//  SubscriptionModels.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import Foundation

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, CaseIterable {
    case free = "free"
    case pro = "pro"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
    
    var description: String {
        switch self {
        case .free: return "Basic scheduling features"
        case .pro: return "Advanced scheduling with AI assistance"
        }
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: String, Codable {
    case active = "active"
    case expired = "expired"
    case cancelled = "cancelled"
    case gracePeriod = "grace_period"
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        case .gracePeriod: return "Grace Period"
        }
    }
}

// MARK: - Subscription Limits

struct SubscriptionLimits {
    let maxGroups: Int
    let maxGroupMembers: Int
    let maxAIRequests: Int
    
    init(for tier: SubscriptionTier) {
        switch tier {
        case .free:
            self.maxGroups = 1
            self.maxGroupMembers = 5
            self.maxAIRequests = 0
        case .pro:
            self.maxGroups = 5
            self.maxGroupMembers = 10
            self.maxAIRequests = 100
        }
    }
}

// MARK: - User Subscription Info

struct UserSubscriptionInfo: Codable, Equatable {
    let tier: SubscriptionTier
    let status: SubscriptionStatus
    let revenuecatCustomerId: String?
    let subscriptionUpdatedAt: Date?
    let downgradeGracePeriodEnds: Date?
    
    enum CodingKeys: String, CodingKey {
        case tier = "subscription_tier"
        case status = "subscription_status"
        case revenuecatCustomerId = "revenuecat_customer_id"
        case subscriptionUpdatedAt = "subscription_updated_at"
        case downgradeGracePeriodEnds = "downgrade_grace_period_ends"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let tierString = try container.decode(String.self, forKey: .tier)
        self.tier = SubscriptionTier(rawValue: tierString) ?? .free
        
        let statusString = try container.decode(String.self, forKey: .status)
        self.status = SubscriptionStatus(rawValue: statusString) ?? .active
        
        self.revenuecatCustomerId = try container.decodeIfPresent(String.self, forKey: .revenuecatCustomerId)
        self.subscriptionUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionUpdatedAt)
        self.downgradeGracePeriodEnds = try container.decodeIfPresent(Date.self, forKey: .downgradeGracePeriodEnds)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier.rawValue, forKey: .tier)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(revenuecatCustomerId, forKey: .revenuecatCustomerId)
        try container.encodeIfPresent(subscriptionUpdatedAt, forKey: .subscriptionUpdatedAt)
        try container.encodeIfPresent(downgradeGracePeriodEnds, forKey: .downgradeGracePeriodEnds)
    }
    
    init(
        tier: SubscriptionTier,
        status: SubscriptionStatus,
        revenuecatCustomerId: String? = nil,
        subscriptionUpdatedAt: Date? = nil,
        downgradeGracePeriodEnds: Date? = nil
    ) {
        self.tier = tier
        self.status = status
        self.revenuecatCustomerId = revenuecatCustomerId
        self.subscriptionUpdatedAt = subscriptionUpdatedAt
        self.downgradeGracePeriodEnds = downgradeGracePeriodEnds
    }
    
    var limits: SubscriptionLimits {
        SubscriptionLimits(for: tier)
    }
    
    var isInGracePeriod: Bool {
        guard status == .gracePeriod,
              let gracePeriodEnds = downgradeGracePeriodEnds else {
            return false
        }
        return gracePeriodEnds > Date()
    }
    
    var daysRemainingInGracePeriod: Int? {
        guard let gracePeriodEnds = downgradeGracePeriodEnds else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnds).day ?? 0
        return max(0, days)
    }
}

// MARK: - Grace Period Info

struct GracePeriodInfo {
    let isInGracePeriod: Bool
    let daysRemaining: Int
    let gracePeriodEnds: Date?
    
    var hasEnded: Bool {
        guard let gracePeriodEnds = gracePeriodEnds else { return false }
        return gracePeriodEnds <= Date()
    }
}

// MARK: - Limit Check Results

struct LimitCheckResult {
    let canProceed: Bool
    let reason: String?
    
    var shouldShowUpgrade: Bool {
        !canProceed && reason != nil
    }
}

struct GroupLimitCheck: Decodable {
    let canJoin: Bool
    let currentCount: Int
    let maxAllowed: Int
    let reason: String?
    let currentTier: String?
    
    enum CodingKeys: String, CodingKey {
        case canJoin = "can_join"
        case currentCount = "current_count"
        case maxAllowed = "max_allowed"
        case reason
        case currentTier = "current_tier"
    }
}

struct MemberLimitCheck: Decodable {
    let canAdd: Bool
    let currentCount: Int
    let maxAllowed: Int
    let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case canAdd = "can_add"
        case currentCount = "current_count"
        case maxAllowed = "max_allowed"
        case reason
    }
}

struct AIUsageInfo: Decodable {
    let requestCount: Int
    let maxRequests: Int
    let periodStart: Date
    let periodEnd: Date
    
    enum CodingKeys: String, CodingKey {
        case requestCount = "request_count"
        case maxRequests = "max_requests"
        case periodStart = "period_start"
        case periodEnd = "period_end"
    }
    
    var remainingRequests: Int {
        max(0, maxRequests - requestCount)
    }
    
    var hasRemainingRequests: Bool {
        remainingRequests > 0
    }
    
    var usagePercentage: Double {
        guard maxRequests > 0 else { return 0 }
        return Double(requestCount) / Double(maxRequests)
    }
}

// MARK: - Subscription Product

enum SubscriptionProduct: String, CaseIterable {
    case proMonthly = "schedulr_pro_monthly"
    case proYearly = "schedulr_pro_yearly"
    
    var displayName: String {
        switch self {
        case .proMonthly: return "Monthly"
        case .proYearly: return "Yearly"
        }
    }
    
    var price: String {
        switch self {
        case .proMonthly: return "£4.99"
        case .proYearly: return "£44.99"
        }
    }
    
    var period: String {
        switch self {
        case .proMonthly: return "per month"
        case .proYearly: return "per year"
        }
    }
    
    var savings: String? {
        switch self {
        case .proMonthly: return nil
        case .proYearly: return "Save £15"
        }
    }
}

// MARK: - DB User Model Extension

extension DBUser {
    var subscriptionInfo: UserSubscriptionInfo? {
        // This will be populated from the users table query
        return nil
    }
}

