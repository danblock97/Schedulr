import Foundation
import SwiftUI
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    // Input
    @Published var email: String = ""

    // UI State
    @Published var isLoadingGoogle: Bool = false
    @Published var isLoadingMagic: Bool = false
    @Published var magicSent: Bool = false
    @Published var errorMessage: String? = nil

    // Session State
    @Published private(set) var isAuthenticated: Bool = false

    private var client: SupabaseClient? { SupabaseManager.shared.client }

    func loadInitialSession() {
        // Best-effort check; session may be nil until OAuth completes.
        isAuthenticated = (client?.auth.session != nil)
    }

    func refreshAuthState() {
        isAuthenticated = (client?.auth.session != nil)
    }

    func handleOpenURL(_ url: URL) async {
        guard let client else { return }
        do {
            try await client.auth.handle(url)
            refreshAuthState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        guard !isLoadingGoogle else { return }
        isLoadingGoogle = true
        errorMessage = nil
        defer { isLoadingGoogle = false }

        guard let client else { return }
        do {
            // With urlScheme configured in SupabaseManager, redirect handling should work automatically.
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
            try await client.auth.signInWithOTP(email: trimmed)
            magicSent = true
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
