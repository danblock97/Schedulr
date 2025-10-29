//
//  SchedulrApp.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI
import Foundation

@main
struct SchedulrApp: App {
    @SceneBuilder var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootContainer()
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        #else
        WindowGroup {
            RootContainer()
        }
        #endif
    }
}

private struct RootContainer: View {
    @State private var showSplash: Bool = true
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var onboardingVM = OnboardingViewModel()
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            // Ensure a full-screen background behind all content
            Color(.systemBackground).ignoresSafeArea()
            if authVM.isAuthenticated {
                ContentView()
                    .environmentObject(authVM)
                    .zIndex(0)
            } else {
                AuthView(viewModel: authVM)
                    .zIndex(0)
            }

            if showSplash {
                SplashView(isVisible: $showSplash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .ignoresSafeArea()
        .task {
            // Initialize services and then dismiss the splash.
            do {
                try SupabaseManager.shared.startFromInfoPlist()
            } catch {
                #if DEBUG
                print("Supabase init error:", error.localizedDescription)
                #endif
            }
            // Determine initial auth state before splash hides
            authVM.loadInitialSession()
            // Pre-check onboarding if already signed in
            if authVM.isAuthenticated {
                showOnboarding = await onboardingVM.needsOnboarding()
            }
            // Simulate small delay so the splash is visible; remove if undesired.
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                showSplash = false
            }
        }
        .onOpenURL { url in
            Task { await authVM.handleOpenURL(url) }
        }
        .onChange(of: authVM.isAuthenticated) { _, isAuthed in
            guard isAuthed else { showOnboarding = false; return }
            Task { @MainActor in
                showOnboarding = await onboardingVM.needsOnboarding()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView(viewModel: onboardingVM)
                .onAppear {
                    onboardingVM.onFinished = { showOnboarding = false }
                }
        }
    }
}
