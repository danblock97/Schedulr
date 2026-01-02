import Foundation
import Supabase

/// Manages user locale preferences for date formatting
/// Automatically detects and stores the device locale to ensure proper date formatting in notifications
final class LocalePreferencesManager {
    static let shared = LocalePreferencesManager()
    private init() {}
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    /// Detects the current device locale identifier
    /// Returns a BCP 47 locale identifier (e.g., "en_GB", "en_US", "fr_FR")
    var deviceLocaleIdentifier: String {
        // Use Locale.current.identifier which gives us the full locale (e.g., "en_GB")
        // Fallback to preferredLanguages if needed
        if let identifier = Locale.current.identifier, !identifier.isEmpty {
            return identifier
        }
        
        // Fallback to first preferred language
        if let preferredLanguage = Locale.preferredLanguages.first {
            // Convert language code to locale identifier
            // e.g., "en" -> "en_US" (default), but we'll use what we have
            return preferredLanguage
        }
        
        // Final fallback
        return "en_US"
    }
    
    /// Loads the stored locale for a user, or returns device locale if not stored
    func load(for userId: UUID) async throws -> String {
        guard let client else {
            throw NSError(
                domain: "LocalePrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        struct Row: Decodable {
            let user_id: UUID
            let locale: String?
        }
        
        let rows: [Row] = try await client
            .from("user_settings")
            .select("user_id, locale")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        
        if let row = rows.first, let storedLocale = row.locale, !storedLocale.isEmpty {
            return storedLocale
        }
        
        // No locale stored, use device locale and save it
        let deviceLocale = deviceLocaleIdentifier
        try await save(deviceLocale, for: userId)
        return deviceLocale
    }
    
    /// Saves the locale for a user
    func save(_ locale: String, for userId: UUID) async throws {
        guard let client else {
            throw NSError(
                domain: "LocalePrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        struct UpsertRow: Encodable {
            let user_id: UUID
            let locale: String
        }
        
        let row = UpsertRow(user_id: userId, locale: locale)
        
        // Use upsert to update or insert
        _ = try await client
            .from("user_settings")
            .upsert(row, onConflict: "user_id")
            .execute()
    }
    
    /// Updates the locale if the device locale has changed
    /// Call this periodically (e.g., on app launch) to keep locale in sync
    func updateIfNeeded(for userId: UUID) async throws {
        let currentDeviceLocale = deviceLocaleIdentifier
        
        // Load stored locale
        let storedLocale = try await load(for: userId)
        
        // If device locale has changed, update it
        if storedLocale != currentDeviceLocale {
            try await save(currentDeviceLocale, for: userId)
        }
    }
}

