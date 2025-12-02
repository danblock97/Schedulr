import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animation
    var avatarURL: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top border separator with depth
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.12),
                            Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 2, y: 1)
            
            HStack(spacing: 8) {
                // Home Tab
                TabBarButton(
                    icon: "house.fill",
                    index: 0,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager
                )

                // Calendar Tab
                TabBarButton(
                    icon: "calendar",
                    index: 1,
                    selectedTab: $selectedTab,
                    animation: animation,
                    isCenter: true,
                    themeManager: themeManager
                )

                // Ask AI Tab
                TabBarButton(
                    icon: "sparkles",
                    index: 2,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager
                )

                // Profile Tab
                TabBarButton(
                    icon: "person.crop.circle.fill",
                    index: 3,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager,
                    avatarURL: avatarURL
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .padding(.bottom, 0)
            .background(
                ZStack {
                    // Main background with blur
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    
                    // Subtle theme color tint
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor.opacity(0.06),
                                    themeManager.secondaryColor.opacity(0.04)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            )
        }
        .ignoresSafeArea(edges: .horizontal)
    }
}

struct TabBarButton: View {
    let icon: String
    let index: Int
    @Binding var selectedTab: Int
    let animation: Namespace.ID
    var isCenter: Bool = false
    @ObservedObject var themeManager: ThemeManager
    var avatarURL: String? = nil

    var isSelected: Bool {
        selectedTab == index
    }
    
    var isProfileTab: Bool {
        index == 3
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } label: {
            ZStack {
                if isSelected {
                    // Selected background with enhanced styling
                    Capsule()
                        .fill(themeManager.gradient)
                        .matchedGeometryEffect(id: "TAB", in: animation)
                        .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 4, x: 0, y: 1)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }

                // Show avatar for profile tab if available, otherwise show icon
                if isProfileTab, let avatarURL = avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            Image(systemName: icon)
                                .font(.system(size: isCenter ? 28 : 22, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        case .failure:
                            Image(systemName: icon)
                                .font(.system(size: isCenter ? 28 : 22, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        @unknown default:
                            Image(systemName: icon)
                                .font(.system(size: isCenter ? 28 : 22, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .frame(width: isCenter ? 28 : 22, height: isCenter ? 28 : 22)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: isSelected ? 2 : 0)
                    )
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: isCenter ? 28 : 22, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// Custom button style for scale animation
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Preview
#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack {
            Spacer()
            FloatingTabBar(selectedTab: .constant(0), avatarURL: nil)
                .environmentObject(ThemeManager.shared)
        }
    }
}
