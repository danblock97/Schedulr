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
    @StateObject private var consentManager = ConsentManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showOnboarding: Bool = false
    @State private var routingInProgress: Bool = false
    @State private var hasRequestedTracking: Bool = false

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
            
            // Consent banner - show after splash and tracking permission request, before auth/onboarding
            if !showSplash && hasRequestedTracking && consentManager.shouldShowConsent {
                VStack {
                    Spacer()
                    ConsentBannerView(consentManager: consentManager)
                        .environmentObject(ThemeManager.shared)
                        .zIndex(2)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(themeManager.preferredColorScheme)
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
            
            // Small delay to ensure splash animation completes before showing permission prompts
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
            
            // Request App Tracking Transparency permission FIRST, before any other permissions or data collection
            // This must happen before push notifications, consent banner, auth, etc.
            if #available(iOS 14, *) {
                if TrackingPermissionManager.shared.isTrackingAvailable {
                    let status = TrackingPermissionManager.shared.trackingAuthorizationStatus
                    // Always request if status is not determined (both new devices and reset devices)
                    if status == .notDetermined {
                        // Request tracking permission - this shows the system prompt
                        _ = await TrackingPermissionManager.shared.requestTrackingAuthorization()
                    }
                }
                // Mark tracking as requested (whether newly requested, already determined, or not available)
                hasRequestedTracking = true
            } else {
                // iOS < 14, tracking not available - proceed without requesting
                hasRequestedTracking = true
            }
            
            // Now request push notification permission AFTER tracking permission
            PushManager.shared.registerForPush()
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
