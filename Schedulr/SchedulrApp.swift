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
    @State private var routingInProgress: Bool = false

    var body: some View {
        ZStack {
            // Ensure a full-screen background behind all content
            Color(.systemBackground).ignoresSafeArea()
            switch authVM.phase {
            case .authenticated:
                if routingInProgress {
                    // Hold a neutral background to prevent flashing main UI before onboarding decision
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .zIndex(0)
                } else {
                    ContentView()
                        .environmentObject(authVM)
                        .zIndex(0)
                }
            default:
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
            // Do not pre-check onboarding here to avoid race with async auth validation.
            // Keep splash until auth phase leaves .checking (with a safety timeout).
            var remainingChecks = 20 // ~2.0s max at 100ms intervals
            while authVM.phase == .checking && remainingChecks > 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                remainingChecks -= 1
            }
            withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
        }
        .onOpenURL { url in
            #if DEBUG
            print("[Auth] onOpenURL ->", url.absoluteString)
            #endif
            Task { await authVM.handleOpenURL(url) }
        }
        .onChange(of: authVM.phase) { _, phase in
            switch phase {
            case .authenticated:
                routingInProgress = true
                Task { @MainActor in
                    showOnboarding = await onboardingVM.needsOnboarding()
                    // If onboarding is needed, keep routingInProgress true so we don't flash main UI underneath.
                    routingInProgress = showOnboarding
                }
            default:
                routingInProgress = false
                showOnboarding = false
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView(viewModel: onboardingVM)
                .onAppear {
                    onboardingVM.onFinished = {
                        showOnboarding = false
                        routingInProgress = false
                    }
                }
        }
    }
}
