import SwiftUI

struct ThemePickerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTheme: ColorTheme
    let onSave: (ColorTheme) -> Void
    
    init(themeManager: ThemeManager, onSave: @escaping (ColorTheme) -> Void) {
        self.themeManager = themeManager
        self._selectedTheme = State(initialValue: themeManager.currentTheme)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Preset themes list
                ForEach(PresetTheme.allCases, id: \.rawValue) { preset in
                    ThemeOptionCard(
                        preset: preset,
                        isSelected: isPresetSelected(preset),
                        onTap: {
                            selectedTheme = preset.colorTheme
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Color Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(selectedTheme)
                        themeManager.setTheme(selectedTheme)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func isPresetSelected(_ preset: PresetTheme) -> Bool {
        if case .preset = selectedTheme.type,
           let name = selectedTheme.name,
           name == preset.rawValue {
            return true
        }
        return false
    }
}

struct ThemeOptionCard: View {
    let preset: PresetTheme
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Compact color preview indicator
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [preset.colors.0, preset.colors.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected ? preset.colors.0 : Color.clear,
                                lineWidth: isSelected ? 2.5 : 0
                            )
                    )
                
                // Theme name
                Text(preset.displayName)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(preset.colors.0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Preview
#Preview {
    ThemePickerView(
        themeManager: ThemeManager.shared,
        onSave: { theme in
            print("Selected theme: \(theme)")
        }
    )
}

