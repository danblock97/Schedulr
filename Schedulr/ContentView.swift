//
//  ContentView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI
import Supabase

struct ContentView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Button("Ping Supabase") {
                Task {
                    _ = SupabaseManager.shared.client
                    #if DEBUG
                    print("Supabase client ready")
                    #endif
                }
            }
            Button("Sign Out") {
                Task { await authVM.signOut() }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
