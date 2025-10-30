//
//  ContentView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var calendarManager: CalendarSyncManager
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var selectedTab: Int = 0

    init(calendarManager: CalendarSyncManager) {
        _calendarManager = ObservedObject(initialValue: calendarManager)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(calendarManager: calendarManager))
    }

    var body: some View {
        ZStack {
            // Main content area
            Group {
                switch selectedTab {
                case 0:
                    GroupDashboardView(viewModel: viewModel)
                case 1:
                    PlaceholderView(title: "Create Event", icon: "plus.circle.fill", message: "Event creation is coming soon!")
                case 2:
                    PlaceholderView(title: "Ask AI", icon: "sparkles", message: "AI assistant is coming soon!")
                case 3:
                    ProfileView(viewModel: profileViewModel)
                        .environmentObject(authVM)
                default:
                    GroupDashboardView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating tab bar
            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: icon)
                        .font(.system(size: 72, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                        .padding()
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )

                    VStack(spacing: 12) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(message)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .padding(.bottom, 100) // Space for floating tab bar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    return ContentView(calendarManager: calendarManager)
        .environmentObject(AuthViewModel())
        .environmentObject(calendarManager)
}
