import Foundation
import StoreKit
import UIKit

/// Manages App Store rating prompts with smart timing to avoid popup fatigue
@MainActor
final class RatingManager {
    static let shared = RatingManager()
    
    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "RatingManager.firstLaunchDate"
    private let launchCountKey = "RatingManager.launchCount"
    private let significantActionCountKey = "RatingManager.significantActionCount"
    private let lastRatingPromptKey = "RatingManager.lastRatingPromptDate"
    private let ratingPromptCountKey = "RatingManager.ratingPromptCount"
    private let onboardingCompletedKey = "RatingManager.onboardingCompletedDate"
    
    // Minimum requirements before showing rating prompt
    private let minDaysSinceFirstLaunch = 3
    private let minSignificantActions = 3
    private let daysBetweenPrompts = 90
    private let maxPromptsPerYear = 3
    private let daysAfterOnboarding = 2 // Wait at least 2 days after onboarding
    
    private init() {
        initializeTracking()
    }
    
    // MARK: - Initialization
    
    private func initializeTracking() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
            defaults.set(0, forKey: launchCountKey)
            defaults.set(0, forKey: significantActionCountKey)
            defaults.set(0, forKey: ratingPromptCountKey)
        }
        
        // Increment launch count
        let currentCount = defaults.integer(forKey: launchCountKey)
        defaults.set(currentCount + 1, forKey: launchCountKey)
    }
    
    // MARK: - Public Methods
    
    /// Record that onboarding was completed
    func recordOnboardingCompleted() {
        defaults.set(Date(), forKey: onboardingCompletedKey)
    }
    
    /// Record a significant positive action (e.g., creating event, joining group)
    func recordSignificantAction() {
        let currentCount = defaults.integer(forKey: significantActionCountKey)
        defaults.set(currentCount + 1, forKey: significantActionCountKey)
    }
    
    /// Check if rating prompt should be shown and request it if appropriate
    /// Returns true if the prompt was shown, false otherwise
    func requestReviewIfAppropriate() -> Bool {
        guard shouldShowRatingPrompt() else {
            return false
        }
        
        // Request the rating prompt
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            
            // Record that we showed the prompt
            defaults.set(Date(), forKey: lastRatingPromptKey)
            let currentPromptCount = defaults.integer(forKey: ratingPromptCountKey)
            defaults.set(currentPromptCount + 1, forKey: ratingPromptCountKey)
            
            return true
        }
        
        return false
    }
    
    /// Check if rating prompt should be shown (without actually showing it)
    func shouldShowRatingPrompt() -> Bool {
        // Check minimum days since first launch
        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date else {
            return false
        }
        
        let daysSinceFirstLaunch = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        guard daysSinceFirstLaunch >= minDaysSinceFirstLaunch else {
            return false
        }
        
        // Check minimum significant actions
        let significantActions = defaults.integer(forKey: significantActionCountKey)
        guard significantActions >= minSignificantActions else {
            return false
        }
        
        // Check if enough time has passed since last prompt
        if let lastPrompt = defaults.object(forKey: lastRatingPromptKey) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            guard daysSinceLastPrompt >= daysBetweenPrompts else {
                return false
            }
        }
        
        // Check if we've exceeded max prompts per year
        let promptCount = defaults.integer(forKey: ratingPromptCountKey)
        guard promptCount < maxPromptsPerYear else {
            return false
        }
        
        // Check if enough time has passed since onboarding
        if let onboardingDate = defaults.object(forKey: onboardingCompletedKey) as? Date {
            let daysSinceOnboarding = Calendar.current.dateComponents([.day], from: onboardingDate, to: Date()).day ?? 0
            guard daysSinceOnboarding >= daysAfterOnboarding else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Testing/Reset (for development)
    
    /// Reset all rating tracking (useful for testing)
    func reset() {
        defaults.removeObject(forKey: firstLaunchKey)
        defaults.removeObject(forKey: launchCountKey)
        defaults.removeObject(forKey: significantActionCountKey)
        defaults.removeObject(forKey: lastRatingPromptKey)
        defaults.removeObject(forKey: ratingPromptCountKey)
        defaults.removeObject(forKey: onboardingCompletedKey)
        initializeTracking()
    }
}

