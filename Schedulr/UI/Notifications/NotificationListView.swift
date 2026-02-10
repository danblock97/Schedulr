//
//  NotificationListView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct NotificationListView: View {
    @ObservedObject var viewModel: NotificationViewModel
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var eventToNavigate: CalendarEventWithUser?
    @State private var currentUserId: UUID?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if viewModel.notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.notifications.isEmpty {
                        Button {
                            viewModel.markAllAsRead()
                        } label: {
                            Text("Mark All Read")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(themeManager.primaryColor)
                        }
                    }
                }
            }
            .sheet(item: $eventToNavigate) { event in
                NavigationStack {
                    EventDetailView(
                        event: event,
                        member: nil, // Member info not available in notification context
                        currentUserId: currentUserId
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                eventToNavigate = nil
                            }
                        }
                    }
                }
            }
            .task {
                // Get current user ID
                currentUserId = try? await SupabaseManager.shared.client.auth.session.user.id
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.slash")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            themeManager.primaryColor.opacity(0.6),
                            themeManager.secondaryColor.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 8) {
                Text("No Notifications")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("You're all caught up!")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.notifications, id: \.id) { notification in
                    NotificationRow(
                        notification: notification,
                        onTap: {
                            handleNotificationTap(notification)
                        },
                        onDismiss: {
                            viewModel.markAsRead(notification)
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private func handleNotificationTap(_ notification: InAppNotificationItem) {
        switch notification.notificationType {
        case "event_invite", "event_update", "event_cancellation", "rsvp_response", "event_reminder", "rain_check_requested", "rain_check_approved", "rain_check_denied", "event_rescheduled":
            if let eventIdString = notification.eventId,
               let eventId = UUID(uuidString: eventIdString) {
                Task {
                    await navigateToEvent(eventId: eventId)
                }
            }

        case "new_group_member", "group_member_left", "group_ownership_transfer", "group_renamed":
            if let groupIdString = notification.groupId,
               let groupId = UUID(uuidString: groupIdString) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToGroup"),
                    object: nil,
                    userInfo: ["groupId": groupId]
                )
            }

        case "group_deleted":
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToProfile"),
                object: nil,
                userInfo: nil
            )

        case "subscription_change", "feature_limit_warning":
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToProfile"),
                object: nil,
                userInfo: ["showSubscription": true]
            )

        default:
            break
        }

        viewModel.markAsRead(notification)
    }
    
    private func navigateToEvent(eventId: UUID) async {
        do {
            guard let event = try await CalendarEventService.shared.fetchEventById(eventId: eventId) else {
                return
            }
            await MainActor.run {
                eventToNavigate = event
            }
        } catch {
            print("[NotificationListView] Error fetching event for navigation: \(error.localizedDescription)")
        }
    }
}

struct NotificationRow: View {
    let notification: InAppNotificationItem
    let onTap: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale.current // Use device locale for proper formatting
        return formatter
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor.opacity(0.2),
                                    themeManager.secondaryColor.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [themeManager.primaryColor, themeManager.secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(notification.body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    
                    Text(dateFormatter.string(from: notification.date))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch notification.notificationType {
        case "event_invite":
            return "calendar.badge.plus"
        case "event_update":
            return "calendar.badge.clock"
        case "event_cancellation":
            return "calendar.badge.exclamationmark"
        case "rsvp_response":
            return "person.crop.circle.badge.checkmark"
        case "event_reminder":
            return "bell.badge"
        case "new_group_member":
            return "person.badge.plus"
        case "group_member_left":
            return "person.crop.circle.badge.minus"
        case "group_ownership_transfer":
            return "person.2.badge.key.fill"
        case "group_renamed":
            return "textformat.abc"
        case "group_deleted":
            return "trash.circle.fill"
        case "subscription_change":
            return "crown.fill"
        case "feature_limit_warning":
            return "exclamationmark.triangle.fill"
        default:
            return "bell.fill"
        }
    }
}

#Preview {
    NotificationListView(viewModel: NotificationViewModel())
        .environmentObject(ThemeManager.shared)
}
