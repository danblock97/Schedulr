import Foundation
import SwiftUI

/// Manages user consent for data collection and third-party services
/// GDPR-compliant consent management
@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()
    
    @Published var hasShownConsent: Bool = false
    @Published var consentStatus: ConsentStatus = .notDetermined
    
    private let defaults = UserDefaults.standard
    private let hasShownConsentKey = "ConsentManager.hasShownConsent"
    private let analyticsConsentKey = "ConsentManager.analyticsConsent"
    private let thirdPartyServicesConsentKey = "ConsentManager.thirdPartyServicesConsent"
    
    private init() {
        loadConsentState()
    }
    
    // MARK: - Consent Status
    
    enum ConsentStatus {
        case notDetermined
        case accepted
        case rejected
        case customized(analytics: Bool, thirdPartyServices: Bool)
    }
    
    struct ConsentPreferences {
        var analytics: Bool
        var thirdPartyServices: Bool
        
        var allAccepted: Bool {
            analytics && thirdPartyServices
        }
        
        var allRejected: Bool {
            !analytics && !thirdPartyServices
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if consent banner should be shown
    var shouldShowConsent: Bool {
        !hasShownConsent
    }
    
    /// Get current consent preferences
    var preferences: ConsentPreferences {
        switch consentStatus {
        case .notDetermined:
            return ConsentPreferences(analytics: false, thirdPartyServices: false)
        case .accepted:
            return ConsentPreferences(analytics: true, thirdPartyServices: true)
        case .rejected:
            return ConsentPreferences(analytics: false, thirdPartyServices: false)
        case .customized(let analytics, let thirdPartyServices):
            return ConsentPreferences(analytics: analytics, thirdPartyServices: thirdPartyServices)
        }
    }
    
    /// Check if analytics are allowed
    var isAnalyticsAllowed: Bool {
        preferences.analytics
    }
    
    /// Check if third-party services are allowed
    var isThirdPartyServicesAllowed: Bool {
        preferences.thirdPartyServices
    }
    
    /// Accept all consents
    func acceptAll() {
        consentStatus = .accepted
        saveConsentState()
        hasShownConsent = true
    }
    
    /// Reject all consents
    func rejectAll() {
        consentStatus = .rejected
        saveConsentState()
        hasShownConsent = true
    }
    
    /// Save customized consent preferences
    func saveCustomized(analytics: Bool, thirdPartyServices: Bool) {
        if analytics && thirdPartyServices {
            consentStatus = .accepted
        } else if !analytics && !thirdPartyServices {
            consentStatus = .rejected
        } else {
            consentStatus = .customized(analytics: analytics, thirdPartyServices: thirdPartyServices)
        }
        saveConsentState()
        hasShownConsent = true
    }
    
    /// Reset consent (for testing or user preference changes)
    func reset() {
        hasShownConsent = false
        consentStatus = .notDetermined
        defaults.removeObject(forKey: hasShownConsentKey)
        defaults.removeObject(forKey: analyticsConsentKey)
        defaults.removeObject(forKey: thirdPartyServicesConsentKey)
    }
    
    // MARK: - Private Methods
    
    private func loadConsentState() {
        hasShownConsent = defaults.bool(forKey: hasShownConsentKey)
        
        if hasShownConsent {
            let analytics = defaults.bool(forKey: analyticsConsentKey)
            let thirdPartyServices = defaults.bool(forKey: thirdPartyServicesConsentKey)
            
            if analytics && thirdPartyServices {
                consentStatus = .accepted
            } else if !analytics && !thirdPartyServices {
                consentStatus = .rejected
            } else {
                consentStatus = .customized(analytics: analytics, thirdPartyServices: thirdPartyServices)
            }
        } else {
            consentStatus = .notDetermined
        }
    }
    
    private func saveConsentState() {
        defaults.set(true, forKey: hasShownConsentKey)
        
        let prefs = preferences
        defaults.set(prefs.analytics, forKey: analyticsConsentKey)
        defaults.set(prefs.thirdPartyServices, forKey: thirdPartyServicesConsentKey)
    }
}

