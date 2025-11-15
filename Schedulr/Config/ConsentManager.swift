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
    private let thirdPartyServicesConsentKey = "ConsentManager.thirdPartyServicesConsent"
    
    private init() {
        loadConsentState()
    }
    
    // MARK: - Consent Status
    
    enum ConsentStatus {
        case notDetermined
        case accepted
        case rejected
    }
    
    struct ConsentPreferences {
        var thirdPartyServices: Bool
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
            return ConsentPreferences(thirdPartyServices: false)
        case .accepted:
            return ConsentPreferences(thirdPartyServices: true)
        case .rejected:
            return ConsentPreferences(thirdPartyServices: false)
        }
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
    func saveCustomized(thirdPartyServices: Bool) {
        if thirdPartyServices {
            consentStatus = .accepted
        } else {
            consentStatus = .rejected
        }
        saveConsentState()
        hasShownConsent = true
    }
    
    /// Reset consent (for testing or user preference changes)
    func reset() {
        hasShownConsent = false
        consentStatus = .notDetermined
        defaults.removeObject(forKey: hasShownConsentKey)
        defaults.removeObject(forKey: thirdPartyServicesConsentKey)
    }
    
    // MARK: - Private Methods
    
    private func loadConsentState() {
        hasShownConsent = defaults.bool(forKey: hasShownConsentKey)
        
        if hasShownConsent {
            let thirdPartyServices = defaults.bool(forKey: thirdPartyServicesConsentKey)
            
            if thirdPartyServices {
                consentStatus = .accepted
            } else {
                consentStatus = .rejected
            }
        } else {
            consentStatus = .notDetermined
        }
    }
    
    private func saveConsentState() {
        defaults.set(true, forKey: hasShownConsentKey)
        
        let prefs = preferences
        defaults.set(prefs.thirdPartyServices, forKey: thirdPartyServicesConsentKey)
    }
}

