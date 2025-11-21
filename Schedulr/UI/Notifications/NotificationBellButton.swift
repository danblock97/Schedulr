//
//  NotificationBellButton.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct NotificationBellButton: View {
    @ObservedObject var viewModel: NotificationViewModel
    @State private var showingNotifications = false
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button {
            showingNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(themeManager.primaryColor)
                
                if viewModel.badgeCount > 0 {
                    Text("\(viewModel.badgeCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                        .offset(x: 6, y: -6) // Reduced offset to prevent cutoff
                }
            }
            .padding(.top, 4) // Add top padding to prevent badge cutoff
            .padding(.bottom, 2)
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationListView(viewModel: viewModel)
                .environmentObject(themeManager)
        }
        .onAppear {
            viewModel.refresh()
        }
        .onChange(of: showingNotifications) { _, isShowing in
            if isShowing {
                viewModel.refresh()
            }
        }
    }
}

#Preview {
    NotificationBellButton(viewModel: NotificationViewModel())
        .environmentObject(ThemeManager.shared)
        .padding()
}

