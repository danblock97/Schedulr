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
    var body: some Scene {
        WindowGroup {
            RootContainer()
        }
    }
}

private struct RootContainer: View {
    @State private var showSplash: Bool = true

    var body: some View {
        ZStack {
            ContentView()
                .zIndex(0)

            if showSplash {
                SplashView(isVisible: $showSplash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            // Initialize services and then dismiss the splash.
            do {
                try SupabaseManager.shared.startFromInfoPlist()
            } catch {
                #if DEBUG
                print("Supabase init error:", error.localizedDescription)
                #endif
            }
            // Simulate small delay so the splash is visible; remove if undesired.
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                showSplash = false
            }
        }
    }
}
