import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    enum AuthPhase: Equatable { case checking, unauthenticated, authenticated }

    // Input
    @Published var email: String = ""

    // UI State
    @Published var isLoadingGoogle: Bool = false
    @Published var isLoadingMagic: Bool = false
    @Published var magicSent: Bool = false
    @Published var errorMessage: String? = nil
    @Published var noticeMessage: String? = nil

    private func showNotice(_ text: String, duration: TimeInterval = 5.0) {
        noticeMessage = text
        Task { [weak self] in
            let ns = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            await MainActor.run { self?.noticeMessage = nil }
        }
    }

    // Session State
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var phase: AuthPhase = .checking

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    func loadInitialSession() {
        // Best-effort async check; session may be nil until OAuth completes.
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            await MainActor.run { self.phase = .checking }
            let session = try? await client.auth.session
            await MainActor.run { self.isAuthenticated = (session != nil) }
            await self.validateSession()
        }
    }

    func refreshAuthState() {
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            let session = try? await client.auth.session
            await MainActor.run { self.isAuthenticated = (session != nil) }
            await self.validateSession()
        }
    }

    private func validateSession() async {
        guard let client else { return }
        // Proactive validation: refresh if a session exists; on failure, sign out and clear state.
        if let session = try? await client.auth.session, session != nil {
            do {
                _ = try await client.auth.refreshSession()
                await MainActor.run {
                    self.isAuthenticated = true
                    self.phase = .authenticated
                }
                // Fetch subscription status after successful authentication
                await SubscriptionManager.shared.fetchSubscriptionStatus()
            } catch {
                #if DEBUG
                print("[Auth] refreshSession failed; signing out:", error.localizedDescription)
                #endif
                do { try await client.auth.signOut() } catch { }
                await MainActor.run {
                    self.isAuthenticated = false
                    self.phase = .unauthenticated
                }
                showNotice("Your session expired. Please sign in again.")
            }
        } else {
            await MainActor.run {
                self.isAuthenticated = false
                self.phase = .unauthenticated
            }
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard let client else { return }
        do {
            // If you use a specific callback path, ensure the URL matches what Supabase generated.
            // Example expected: schedulr://auth-callback#access_token=...
            #if DEBUG
            print("[Auth] handleOpenURL incoming:", url.absoluteString)
            #endif
            // First let the SDK try to handle PKCE or token fragments.
            try await client.auth.handle(url)
            #if DEBUG
            let session = try? await client.auth.session
            print("[Auth] handleOpenURL handled. Session present:", session != nil)
            #endif
            // If still no session, try PKCE exchange when we have a code, otherwise try implicit token set.
            if (try? await client.auth.session) == nil {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                   !code.isEmpty {
                    #if DEBUG
                    print("[Auth] No session after handle(url); attempting PKCE code exchange…")
                    #endif
                    do {
                        try await client.auth.exchangeCodeForSession(authCode: code)
                    } catch {
                        #if DEBUG
                        print("[Auth] PKCE exchange failed:", error.localizedDescription)
                        #endif
                        throw error
                    }
                } else if let fragment = url.fragment, !fragment.isEmpty {
                    // Attempt manual implicit token extraction and session set
                    let pairs = fragment.split(separator: "&").map { s -> (String, String) in
                        let parts = s.split(separator: "=", maxSplits: 1).map(String.init)
                        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
                    }
                    var dict: [String: String] = [:]
                    for (k, v) in pairs { dict[k] = v }
                    if let access = dict["access_token"], let refresh = dict["refresh_token"], !access.isEmpty, !refresh.isEmpty {
                        #if DEBUG
                        print("[Auth] No session after handle(url); setting session from fragment tokens…")
                        #endif
                        do {
                            try await client.auth.setSession(accessToken: access, refreshToken: refresh)
                        } catch {
                            #if DEBUG
                            print("[Auth] setSession from tokens failed:", error.localizedDescription)
                            #endif
                            throw error
                        }
                    }
                }
            }
            refreshAuthState()
            // Fetch subscription status after authentication
            await SubscriptionManager.shared.fetchSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
            if error.localizedDescription.localizedCaseInsensitiveContains("invalid flow state") {
                showNotice("Magic link expired or not initiated here. Request a new link in the app.")
            }
            #if DEBUG
            print("[Auth] handleOpenURL error:", error.localizedDescription)
            #endif
        }
    }

    func signInWithGoogle() async {
        guard !isLoadingGoogle else { return }
        isLoadingGoogle = true
        errorMessage = nil
        defer { isLoadingGoogle = false }

        guard let client else { return }
        do {
            // OAuth sign-in; redirect is handled via onOpenURL + client.auth.handle(url).
            try await client.auth.signInWithOAuth(provider: .google)
            // The session will be set after redirect returns and handleOpenURL is called.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMagicLink() async {
        guard !isLoadingMagic else { return }
        isLoadingMagic = true
        errorMessage = nil
        magicSent = false
        defer { isLoadingMagic = false }

        guard let client else { return }
        do {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "Please enter your email."
                return
            }
            // Enforce redirect to match app callback path to ensure handler receives PKCE result.
            // Adjust if your chosen path differs.
            let callback = URL(string: "schedulr://auth-callback")
            try await client.auth.signInWithOTP(email: trimmed, redirectTo: callback)
            magicSent = true
            showNotice("Magic link sent! Check your email.", duration: 4.0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
