import SwiftUI

struct MonthViewModePicker: View {
    @Binding var selectedMode: MonthViewMode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(MonthViewMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: icon(for: mode))
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                .frame(width: 24)
                            
                            Text(mode.rawValue)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("View Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func icon(for mode: MonthViewMode) -> String {
        switch mode {
        case .compact:
            return "calendar"
        case .stacked:
            return "square.stack.3d.up"
        case .details:
            return "list.bullet.rectangle"
        }
    }
}
