import SwiftUI

struct RainCheckApprovalSheet: View {
    let event: CalendarEventWithUser
    let requesterName: String
    let reason: String?
    let onApprove: () async throws -> Void
    let onDeny: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon
                HStack {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.top)

                // Title and description
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rain Check Request")
                        .font(.title2.bold())

                    Text("\(requesterName) has requested to postpone this event.")
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

                // Reason section
                if let reason {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reason")
                            .font(.subheadline.weight(.medium))

                        Text(reason)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }

                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Approving will hide this event from everyone's calendar. You can reschedule it later from the Rain-Checked Events view.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

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
                    Button(action: approve) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Approve & Postpone")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isProcessing)

                    Button(action: deny) {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Deny Request")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isProcessing)

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }

    private func approve() {
        Task {
            isProcessing = true
            errorMessage = nil

            do {
                try await onApprove()
                dismiss()
            } catch {
                errorMessage = "Failed to approve: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func deny() {
        Task {
            isProcessing = true
            errorMessage = nil

            do {
                try await onDeny()
                dismiss()
            } catch {
                errorMessage = "Failed to deny: \(error.localizedDescription)"
                isProcessing = false
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
