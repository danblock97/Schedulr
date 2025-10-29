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
            ContentView()
                .onAppear {
                    do {
                        try SupabaseManager.shared.startFromInfoPlist()
                    } catch {
                        #if DEBUG
                        print("Supabase init error:", error.localizedDescription)
                        #endif
                    }
                }
        }
    }
}
