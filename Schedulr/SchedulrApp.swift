//
//  SchedulrApp.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI
import Foundation
import UIKit

@main
struct SchedulrApp: App {
    @UIApplicationDelegateAdaptor(PushManager.self) var appDelegate
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
    @StateObject private var calendarManager: CalendarSyncManager
    @StateObject private var onboardingVM: OnboardingViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showOnboarding: Bool = false
    @State private var routingInProgress: Bool = false

    init() {
        let calendarManager = CalendarSyncManager()
        _calendarManager = StateObject(wrappedValue: calendarManager)
        _onboardingVM = StateObject(wrappedValue: OnboardingViewModel(calendarManager: calendarManager))
    }

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
                    ContentView(calendarManager: calendarManager)
                        .environmentObject(authVM)
                        .environmentObject(calendarManager)
                        .environmentObject(ThemeManager.shared)
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
        .preferredColorScheme(themeManager.preferredColorScheme)
        .task {
            // Small delay to ensure splash animation completes before showing permission prompts
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
            
            // Initialize Supabase
            do {
                try SupabaseManager.shared.startFromInfoPlist()
            } catch {
                #if DEBUG
                print("Supabase init error:", error.localizedDescription)
                #endif
            }
            
            // Determine initial auth state before splash hides
            authVM.loadInitialSession()
            // Initialize subscription manager
            await SubscriptionManager.shared.configure()
            // Check and enforce grace periods if needed
            await GracePeriodManager.shared.checkAndEnforceIfNeeded()
            // Initialize rating manager (tracks launches automatically)
            _ = RatingManager.shared
            // Do not pre-check onboarding here to avoid race with async auth validation.
            // Keep splash until auth phase leaves .checking (with a safety timeout).
            var remainingChecks = 20 // ~2.0s max at 100ms intervals
            while authVM.phase == .checking && remainingChecks > 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                remainingChecks -= 1
            }
            withAnimation(.easeInOut(duration: 0.35)) { showSplash = false }
            
            // Request push notification permission
            PushManager.shared.registerForPush()
        }
        .onOpenURL { url in
            #if DEBUG
            print("[App] onOpenURL ->", url.absoluteString)
            #endif
            
            // Handle AI chat deep link (schedulr://ai-chat or schedulr://ai-chat?voice=true)
            if url.host == "ai-chat" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let withVoice = components?.queryItems?.first(where: { $0.name == "voice" })?.value == "true"
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToAIChat"),
                    object: nil,
                    userInfo: ["voice": withVoice]
                )
                return
            }
            
            // Handle auth callbacks
            Task { await authVM.handleOpenURL(url) }
        }
        .onChange(of: authVM.phase) { _, phase in
            switch phase {
            case .authenticated:
                routingInProgress = true
                calendarManager.resetAuthorizationStatus()
                Task { @MainActor in
                    showOnboarding = await onboardingVM.needsOnboarding()
                    // If onboarding is needed, keep routingInProgress true so we don't flash main UI underneath.
                    routingInProgress = showOnboarding
                    if !showOnboarding {
                        await calendarManager.refreshEvents()
                    }
                }
            default:
                // Reset onboarding state when user signs out to prevent data from previous session
                onboardingVM.reset()
                routingInProgress = false
                showOnboarding = false
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView(viewModel: onboardingVM)
                .environmentObject(calendarManager)
                .onAppear {
                    onboardingVM.onFinished = {
                        showOnboarding = false
                        routingInProgress = false
                        // Record onboarding completion for rating prompt
                        RatingManager.shared.recordOnboardingCompleted()
                        Task { await calendarManager.refreshEvents() }
                    }
                }
        }
    }
}
