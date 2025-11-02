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
            ScrollView {
                VStack(spacing: 24) {
                    Text("Choose a color theme")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.top)
                    
                    // Preset themes grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(PresetTheme.allCases, id: \.rawValue) { preset in
                            ThemeOptionCard(
                                preset: preset,
                                isSelected: isPresetSelected(preset),
                                onTap: {
                                    selectedTheme = preset.colorTheme
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 100)
            }
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
            VStack(spacing: 12) {
                // Color preview gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [preset.colors.0, preset.colors.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isSelected ? Color.primary : Color.clear,
                                lineWidth: isSelected ? 3 : 0
                            )
                    )
                    .shadow(
                        color: isSelected ? preset.colors.0.opacity(0.3) : Color.black.opacity(0.1),
                        radius: isSelected ? 12 : 4,
                        x: 0,
                        y: isSelected ? 6 : 2
                    )
                
                // Theme name
                Text(preset.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(.primary)
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(preset.colors.0)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
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

