import Foundation
import Supabase
#if canImport(UIKit)
import UIKit
#endif

final class ThemePreferencesManager {
    static let shared = ThemePreferencesManager()
    private init() {}
    
    private var client: SupabaseClient? { SupabaseManager.shared.client }
    
    func load(for userId: UUID) async throws -> ColorTheme {
        guard let client else {
            throw NSError(
                domain: "ThemePrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        struct Row: Decodable {
            let user_id: UUID
            let color_theme: ColorTheme
        }
        
        let rows: [Row] = try await client
            .from("user_settings")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        
        if let row = rows.first {
            return row.color_theme
        }
        
        // Insert defaults if not found - check system dark mode preference
        let defaultThemeName: String
        #if canImport(UIKit)
        if UITraitCollection.current.userInterfaceStyle == .dark {
            // Use dark theme if system is in dark mode
            defaultThemeName = "dark"
        } else {
            // Use pink_purple as default for light mode
            defaultThemeName = "pink_purple"
        }
        #else
        // Fallback for non-UIKit platforms
        defaultThemeName = "pink_purple"
        #endif
        let defaultTheme = ColorTheme(type: .preset, name: defaultThemeName, colors: nil)
        try await save(defaultTheme, for: userId)
        return defaultTheme
    }
    
    func save(_ theme: ColorTheme, for userId: UUID) async throws {
        guard let client else {
            throw NSError(
                domain: "ThemePrefs",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Supabase client unavailable"]
            )
        }
        
        // Supabase Swift client can handle Codable types directly for JSONB
        struct UpsertRow: Encodable {
            let user_id: UUID
            let color_theme: ColorTheme
        }
        
        let row = UpsertRow(user_id: userId, color_theme: theme)
        _ = try await client
            .from("user_settings")
            .upsert(row, onConflict: "user_id")
            .execute()
    }
}

