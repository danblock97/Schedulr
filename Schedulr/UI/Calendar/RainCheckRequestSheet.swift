import SwiftUI

struct RainCheckRequestSheet: View {
    let event: CalendarEventWithUser
    let isCreator: Bool
    let onSubmit: (String?) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon
                HStack {
                    Spacer()
                    Image(systemName: "cloud.rain")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.top)

                // Title and description
                VStack(alignment: .leading, spacing: 12) {
                    Text(isCreator ? "Rain Check This Event?" : "Request Rain Check")
                        .font(.title2.bold())

                    Text(isCreator
                        ? "This will postpone the event and hide it from everyone's calendar. You can reschedule it later."
                        : "Ask the event creator to postpone this event. They can reschedule it when everyone's available.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Event info card
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(.headline)

                    HStack {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDate(event.start_date))
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
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Reason field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reason (Optional)")
                        .font(.subheadline.weight(.medium))

                    TextField("e.g., Can't make it anymore", text: $reason, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.vertical, 4)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isCreator ? "Rain Check Event" : "Send Request")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() {
        Task {
            isSubmitting = true
            errorMessage = nil

            do {
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalReason = trimmedReason.isEmpty ? nil : trimmedReason

                try await onSubmit(finalReason)
                dismiss()
            } catch {
                errorMessage = "Failed to submit: \(error.localizedDescription)"
                isSubmitting = false
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = event.is_all_day ? .none : .short
        return formatter.string(from: date)
    }
}
