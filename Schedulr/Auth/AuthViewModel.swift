import Foundation
import SwiftUI
import Combine
import Supabase
#if os(iOS)
import AuthenticationServices
#endif

@MainActor
final class AuthViewModel: ObservableObject {
    enum AuthPhase: Equatable { case checking, unauthenticated, authenticated }
    enum AuthMode: Equatable { case signIn, signUp }

    // Input
    @Published var email: String = ""
    @Published var password: String = ""

    // UI State
    @Published var isLoadingApple: Bool = false
    @Published var isLoadingEmail: Bool = false
    @Published var authMode: AuthMode = .signIn
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
                // Identify user with RevenueCat and fetch subscription status after successful authentication
                await SubscriptionManager.shared.identifyUser()
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
            // Identify user with RevenueCat and fetch subscription status after authentication
            await SubscriptionManager.shared.identifyUser()
            await SubscriptionManager.shared.fetchSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[Auth] handleOpenURL error:", error.localizedDescription)
            #endif
        }
    }

    #if os(iOS)
    func signInWithApple(authorization: ASAuthorization) async {
        guard !isLoadingApple else { return }
        isLoadingApple = true
        errorMessage = nil
        defer { isLoadingApple = false }
        
        guard let client else {
            errorMessage = "Authentication service unavailable"
            return
        }
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = "Invalid Apple ID credential"
            #if DEBUG
            print("[Auth] Failed to cast credential to ASAuthorizationAppleIDCredential")
            #endif
            return
        }
        
        guard let identityTokenData = appleIDCredential.identityToken else {
            errorMessage = "Failed to get identity token from Apple"
            #if DEBUG
            print("[Auth] identityToken is nil")
            #endif
            return
        }
        
        guard let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            errorMessage = "Failed to encode identity token"
            #if DEBUG
            print("[Auth] Failed to convert identityToken data to string")
            #endif
            return
        }
        
        #if DEBUG
        print("[Auth] Attempting to sign in with Apple ID token, user: \(appleIDCredential.user)")
        #endif
        
        do {
            // Sign in with Supabase using the Apple ID token
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken
                )
            )
            
            #if DEBUG
            print("[Auth] Apple Sign In successful, session user ID: \(session.user.id)")
            #endif
            
            // Session is set, refresh auth state
            refreshAuthState()
            // Identify user with RevenueCat and fetch subscription status after authentication
            await SubscriptionManager.shared.identifyUser()
            await SubscriptionManager.shared.fetchSubscriptionStatus()
        } catch {
            #if DEBUG
            print("[Auth] Apple Sign In error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("[Auth] Error domain: \(nsError.domain), code: \(nsError.code), userInfo: \(nsError.userInfo)")
            }
            #endif
            errorMessage = "Failed to sign in with Apple: \(error.localizedDescription)"
        }
    }
    #endif

    func signInWithEmail() async {
        guard !isLoadingEmail else { return }
        isLoadingEmail = true
        errorMessage = nil
        defer { isLoadingEmail = false }

        guard let client else { return }
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedEmail.isEmpty else {
                errorMessage = "Please enter your email."
                return
            }
            guard !trimmedPassword.isEmpty else {
                errorMessage = "Please enter your password."
                return
            }
            guard trimmedPassword.count >= 6 else {
                errorMessage = "Password must be at least 6 characters."
                return
            }
            
            _ = try await client.auth.signIn(email: trimmedEmail, password: trimmedPassword)
            refreshAuthState()
            // Identify user with RevenueCat and fetch subscription status
            await SubscriptionManager.shared.identifyUser()
            await SubscriptionManager.shared.fetchSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUpWithEmail() async {
        guard !isLoadingEmail else { return }
        isLoadingEmail = true
        errorMessage = nil
        defer { isLoadingEmail = false }

        guard let client else { return }
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedEmail.isEmpty else {
                errorMessage = "Please enter your email."
                return
            }
            guard !trimmedPassword.isEmpty else {
                errorMessage = "Please enter your password."
                return
            }
            guard trimmedPassword.count >= 6 else {
                errorMessage = "Password must be at least 6 characters."
                return
            }
            
            _ = try await client.auth.signUp(email: trimmedEmail, password: trimmedPassword)
            refreshAuthState()
            // Identify user with RevenueCat and fetch subscription status
            await SubscriptionManager.shared.identifyUser()
            await SubscriptionManager.shared.fetchSubscriptionStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetPassword() async {
        guard !isLoadingEmail else { return }
        isLoadingEmail = true
        errorMessage = nil
        defer { isLoadingEmail = false }

        guard let client else { return }
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEmail.isEmpty else {
                errorMessage = "Please enter your email."
                return
            }
            
            let callback = URL(string: "schedulr://auth-callback")
            try await client.auth.resetPasswordForEmail(trimmedEmail, redirectTo: callback)
            showNotice("Password reset email sent! Check your inbox.", duration: 5.0)
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
