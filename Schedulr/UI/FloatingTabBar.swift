import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animation
    var avatarURL: String?

    var body: some View {
        HStack(spacing: 12) {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                // Main background with blur
                Capsule()
                    .fill(.ultraThinMaterial)
                
                // Subtle theme color tint
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                themeManager.primaryColor.opacity(0.08),
                                themeManager.secondaryColor.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                // Border with gradient (adapts to color scheme)
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.2), radius: 30, x: 0, y: 15)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 10, x: 0, y: 5)
            .shadow(color: themeManager.primaryColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
                        .shadow(color: themeManager.primaryColor.opacity(0.5), radius: 12, x: 0, y: 6)
                        .shadow(color: themeManager.secondaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
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
                                .font(.system(size: isCenter ? 32 : 26, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        case .failure:
                            Image(systemName: icon)
                                .font(.system(size: isCenter ? 32 : 26, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        @unknown default:
                            Image(systemName: icon)
                                .font(.system(size: isCenter ? 32 : 26, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .frame(width: isCenter ? 32 : 26, height: isCenter ? 32 : 26)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: isSelected ? 2.5 : 0)
                    )
                    .scaleEffect(isSelected ? 1.05 : 0.95)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: isCenter ? 32 : 26, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(isSelected ? 1.05 : 0.95)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
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
