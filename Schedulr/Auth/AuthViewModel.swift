import Foundation
import SwiftUI
import Combine
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
        // Best-effort async check; session may be nil until OAuth completes.
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            let session = try? await client.auth.session
            await MainActor.run { self.isAuthenticated = (session != nil) }
        }
    }

    func refreshAuthState() {
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            let session = try? await client.auth.session
            await MainActor.run { self.isAuthenticated = (session != nil) }
        }
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
