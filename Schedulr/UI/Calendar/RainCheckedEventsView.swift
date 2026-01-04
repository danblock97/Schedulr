import SwiftUI

struct RainCheckedEventsView: View {
    let groupId: UUID
    @State private var rainCheckedEvents: [CalendarEventWithUser] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var selectedEvent: CalendarEventWithUser?
    @State private var showingRescheduleSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendarSync: CalendarSyncManager

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading rain-checked events...")
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Error Loading Events")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await loadRainCheckedEvents() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if rainCheckedEvents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cloud.sun")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        Text("No Postponed Events")
                            .font(.title2.bold())
                        Text("Events that have been rain-checked will appear here so you can reschedule them later.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(rainCheckedEvents) { event in
                                RainCheckedEventCard(event: event) {
                                    selectedEvent = event
                                    showingRescheduleSheet = true
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Postponed Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRescheduleSheet) {
                if let event = selectedEvent {
                    EventEditorView(
                        groupId: event.group_id,
                        members: [],
                        existingEvent: event,
                        isRescheduling: true
                    )
                    .onDisappear {
                        // Refresh the list and calendar after rescheduling
                        Task {
                            await loadRainCheckedEvents()
                            try? await calendarSync.fetchGroupEvents(groupId: groupId)
                        }
                    }
                }
            }
            .task {
                await loadRainCheckedEvents()
            }
        }
    }

    private func loadRainCheckedEvents() async {
        isLoading = true
        errorMessage = nil

        do {
            let events = try await CalendarEventService.shared.fetchRainCheckedEvents(groupId: groupId)
            await MainActor.run {
                rainCheckedEvents = events
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

private struct RainCheckedEventCard: View {
    let event: CalendarEventWithUser
    let onReschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with rain check badge
            HStack {
                Image(systemName: "cloud.rain.fill")
                    .foregroundColor(.blue)
                Text("POSTPONED")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                Spacer()
                if let rainCheckedAt = event.rainCheckedAt {
                    Text(formatRelativeDate(rainCheckedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Event details
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.headline)

                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Was scheduled for \(formatDate(event.start_date))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let location = event.location {
                    HStack {
                        Image(systemName: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if let reason = event.rainCheckReason {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.bubble")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(reason)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding(.top, 4)
                }
            }

            // Action button
            Button(action: onReschedule) {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("Reschedule Event")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = event.is_all_day ? .none : .short
        return formatter.string(from: date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let components = calendar.dateComponents([.day], from: date, to: now)
            if let days = components.day, days <= 7 {
                return "\(days) days ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                return formatter.string(from: date)
            }
        }
    }
}
