import Foundation
import Supabase
import Auth

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
    // URL scheme used for OAuth redirects and password reset (must exist in Info.plist URL Types)
    let oauthCallbackScheme: String?
    // OpenAI API key for AI features
    let openAIAPIKey: String?

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
        let openAIKey = value("OPENAI_API_KEY")

        guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
            throw SupabaseConfigError.invalidURL(urlString)
        }
        return SupabaseConfiguration(url: url, anonKey: anon, serviceRoleKey: service, oauthCallbackScheme: scheme, openAIAPIKey: openAIKey)
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    private(set) var client: SupabaseClient!
    private(set) var configuration: SupabaseConfiguration!

    private init() {}

    func start(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        // Initialize client with Keychain storage for session persistence.
        // Redirect handling is performed via onOpenURL -> client.auth.handle(url).
        // Implicit flow is used for OAuth and password reset redirects.
        // PKCE remains supported for OAuth via handle(url).
        
        // Build redirect URL from configuration or use default
        let redirectURL: URL
        if let scheme = configuration.oauthCallbackScheme, !scheme.isEmpty {
            redirectURL = URL(string: "\(scheme)://auth-callback") ?? URL(string: "schedulr://auth-callback")!
        } else {
            redirectURL = URL(string: "schedulr://auth-callback")!
        }
        
        let authOptions = SupabaseClientOptions.AuthOptions(
            redirectToURL: redirectURL,
            flowType: .implicit
        )
        
        var options = SupabaseClientOptions()
        // Note: auth property is let, so we need to initialize it in the options initializer
        // However, since we can't modify it, we'll use the default initialization
        // and configure the auth client separately if needed
        
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey,
            options: .init(auth: authOptions)
        )
        
        // Configure storage separately on the auth client if needed
        // The redirectToURL is already set in authOptions above
    }

    func startFromInfoPlist() throws {
        let config = try SupabaseConfiguration.fromInfoPlist()
        start(configuration: config)
    }
}
