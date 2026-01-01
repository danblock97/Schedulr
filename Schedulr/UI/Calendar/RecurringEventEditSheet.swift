import SwiftUI

enum RecurringEditScope: CaseIterable {
    case thisOccurrence
    case thisAndFuture
    case allOccurrences

    var title: String {
        switch self {
        case .thisOccurrence: return "This Occurrence"
        case .thisAndFuture: return "This & Future Occurrences"
        case .allOccurrences: return "All Occurrences"
        }
    }

    var subtitle: String {
        switch self {
        case .thisOccurrence: return "Only edit this single event"
        case .thisAndFuture: return "Edit from this date forward"
        case .allOccurrences: return "Edit the entire series"
        }
    }
}

struct RecurringEventEditSheet: View {
    let event: CalendarEventWithUser
    let action: RecurringEventAction
    let onSelect: (RecurringEditScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    enum RecurringEventAction {
        case edit
        case delete

        var title: String {
            switch self {
            case .edit: return "Edit Recurring Event"
            case .delete: return "Delete Recurring Event"
            }
        }

        var prompt: String {
            switch self {
            case .edit: return "What would you like to edit?"
            case .delete: return "What would you like to delete?"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "repeat")
                    .font(.system(size: 48))
                    .foregroundStyle(action == .delete ? .red : themeManager.primaryColor)
                    .padding(.top, 24)

                // Title
                Text("This is a recurring event")
                    .font(.headline)

                Text(action.prompt)
                    .foregroundStyle(.secondary)

                // Options
                VStack(spacing: 12) {
                    ForEach(RecurringEditScope.allCases, id: \.self) { scope in
                        Button {
                            onSelect(scope)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(scope.title)
                                        .font(.headline)
                                        .foregroundStyle(action == .delete && scope != .thisOccurrence ? .red : .primary)
                                    Text(scope.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct RecurringEventDeleteConfirmation: View {
    let event: CalendarEventWithUser
    let scope: RecurringEditScope
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "trash")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                    .padding(.top, 24)

                Text("Delete \"\(event.title)\"?")
                    .font(.headline)

                Text(confirmationMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Delete")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Confirm Delete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var confirmationMessage: String {
        switch scope {
        case .thisOccurrence:
            return "This will only delete this single occurrence. Other occurrences will not be affected."
        case .thisAndFuture:
            return "This will delete this occurrence and all future occurrences of this event."
        case .allOccurrences:
            return "This will delete the entire recurring event series, including all past and future occurrences."
        }
    }
}

#Preview {
    let mockEvent = CalendarEventWithUser(
        id: UUID(),
        user_id: UUID(),
        group_id: UUID(),
        title: "Weekly Team Meeting",
        start_date: Date(),
        end_date: Date().addingTimeInterval(3600),
        is_all_day: false,
        location: "Conference Room",
        is_public: true,
        original_event_id: nil,
        calendar_name: "Schedulr",
        calendar_color: nil,
        created_at: Date(),
        updated_at: Date(),
        synced_at: Date(),
        notes: nil,
        category_id: nil,
        event_type: "group",
        user: nil,
        category: nil,
        hasAttendees: true,
        isCurrentUserAttendee: true,
        recurrenceRule: .weekly(daysOfWeek: [1, 3, 5]),
        recurrenceEndDate: nil,
        parentEventId: nil,
        isRecurrenceException: false,
        originalOccurrenceDate: nil
    )

    return RecurringEventEditSheet(
        event: mockEvent,
        action: .edit,
        onSelect: { scope in
            print("Selected: \(scope)")
        }
    )
    .environmentObject(ThemeManager.shared)
}
