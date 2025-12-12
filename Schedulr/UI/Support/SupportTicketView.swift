import SwiftUI

struct SupportTicketView: View {
    @StateObject private var viewModel = SupportTicketViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case title
        case description
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .description }
                    
                    Picker("Priority", selection: $viewModel.priority) {
                        ForEach(SupportTicketViewModel.Priority.allCases) { prio in
                            Text(prio.displayName).tag(prio)
                        }
                    }
                    .tint(themeManager.primaryColor)
                    
                    TextField("Description", text: $viewModel.description, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(6, reservesSpace: true)
                }
                
                if let issue = viewModel.createdIssue {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Ticket created", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            
                            if let identifier = issue.identifier {
                                Text("Reference: \(identifier)")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("Thanks — our team will review this and follow up if needed.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        focusedField = nil
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                        }
                    }
                    .disabled(viewModel.isSubmitting || viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}


