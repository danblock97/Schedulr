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

    init(calendarManager: CalendarSyncManager) {
        _calendarManager = ObservedObject(initialValue: calendarManager)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(calendarManager: calendarManager))
    }

    var body: some View {
        GroupDashboardView(viewModel: viewModel) {
            Task { await authVM.signOut() }
        }
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    return ContentView(calendarManager: calendarManager)
        .environmentObject(AuthViewModel())
        .environmentObject(calendarManager)
}
