import SwiftUI

struct SupportTicketView: View {
    @StateObject private var viewModel: SupportTicketViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @FocusState private var focusedField: Field?
    
    init(ticketType: SupportTicketViewModel.TicketType) {
        let vm = SupportTicketViewModel()
        vm.ticketType = ticketType
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    private enum Field {
        case title
        case description
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .font(.system(size: 17, weight: .semibold))
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .description }
                    
                    TextField(viewModel.ticketType.descriptionPlaceholder, text: $viewModel.description, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(6, reservesSpace: true)
                        .font(.body)
                    
                    Picker("Priority", selection: $viewModel.priority) {
                        ForEach(SupportTicketViewModel.Priority.allCases) { prio in
                            Text(prio.displayName).tag(prio)
                        }
                    }
                    .tint(themeManager.primaryColor)
                } header: {
                    Text("Details")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(themeManager.primaryColor)
                        .textCase(.uppercase)
                }
                
                if let issue = viewModel.createdIssue {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Ticket created", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            if let identifier = issue.identifier {
                                Text("Reference: \(identifier)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("Thanks — our team will review this and follow up if needed.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.ticketType.title)
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


