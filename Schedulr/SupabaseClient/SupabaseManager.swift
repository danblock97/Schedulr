import Foundation
import Supabase

// Central access point for Supabase across iOS/iPadOS/watchOS.
// Reads configuration from Info.plist (recommended for Apple platforms)
// with keys: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (optional on-device).
// Do not embed the service role key in production apps; prefer server-side usage.
enum SupabaseConfigError: Error, LocalizedError {
    case missingValue(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let k): return "Missing config value: \(k)"
        case .invalidURL(let u): return "Invalid Supabase URL: \(u)"
        }
    }
}

struct SupabaseConfiguration {
    let url: URL
    let anonKey: String
    // Not for client use in production; present for completeness/testing.
    let serviceRoleKey: String?
    // URL scheme used for OAuth / magic-link redirects (must exist in Info.plist URL Types)
    let oauthCallbackScheme: String?

    // Loads from the app bundle's Info.plist.
    // Provide these via Build Settings -> Info.plist Preprocessor or .xcconfig.
    static func fromInfoPlist(bundle: Bundle = .main) throws -> SupabaseConfiguration {
        func value(_ key: String) -> String? {
            if let v = bundle.object(forInfoDictionaryKey: key) as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
            return nil
        }

        guard let urlString = value("SUPABASE_URL") else { throw SupabaseConfigError.missingValue("SUPABASE_URL") }
        guard let anon = value("SUPABASE_ANON_KEY") else { throw SupabaseConfigError.missingValue("SUPABASE_ANON_KEY") }
        let service = value("SUPABASE_SERVICE_ROLE_KEY")
        let scheme = value("SUPABASE_OAUTH_CALLBACK_SCHEME")

        guard let url = URL(string: urlString) else { throw SupabaseConfigError.invalidURL(urlString) }
        return SupabaseConfiguration(url: url, anonKey: anon, serviceRoleKey: service, oauthCallbackScheme: scheme)
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    private(set) var client: SupabaseClient!
    private(set) var configuration: SupabaseConfiguration!

    private init() {}

    func start(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        // Configure Auth with PKCE and our custom URL scheme to support OAuth and magic links.
        let authConfig = AuthClient.Configuration(
            flowType: .pkce,
            urlScheme: configuration.oauthCallbackScheme ?? "schedulr"
        )
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey,
            options: .init(auth: authConfig)
        )
    }

    func startFromInfoPlist() throws {
        let config = try SupabaseConfiguration.fromInfoPlist()
        start(configuration: config)
    }
}
