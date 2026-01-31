import SwiftUI

struct FloatingTabBar: View {
    static let reservedHeight: CGFloat = 90

    @Binding var selectedTab: Int
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @Namespace private var animation
    var avatarURL: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Home Tab
                TabBarButton(
                    icon: "house.fill",
                    title: "Home",
                    index: 0,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager
                )

                // Calendar Tab
                TabBarButton(
                    icon: "calendar",
                    title: "Calendar",
                    index: 1,
                    selectedTab: $selectedTab,
                    animation: animation,
                    isCenter: true,
                    themeManager: themeManager
                )

                // Ask AI Tab
                TabBarButton(
                    icon: "sparkles",
                    title: "AI",
                    index: 2,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager
                )

                // Profile Tab
                TabBarButton(
                    icon: "person.crop.circle.fill",
                    title: "Profile",
                    index: 3,
                    selectedTab: $selectedTab,
                    animation: animation,
                    themeManager: themeManager,
                    avatarURL: avatarURL
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .liquidGlass()
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.primary.opacity(0.1))
            }
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
    }
}

extension View {
    func tabBarSafeAreaInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: FloatingTabBar.reservedHeight)
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let index: Int
    @Binding var selectedTab: Int
    let animation: Namespace.ID
    var isCenter: Bool = false
    @ObservedObject var themeManager: ThemeManager
    var avatarURL: String? = nil
    @Environment(\.colorScheme) private var colorScheme

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
                    // Subtle indicator dot
                    Circle()
                        .fill(themeManager.primaryColor)
                        .frame(width: 4, height: 4)
                        .offset(y: 24)
                        .matchedGeometryEffect(id: "TAB_DOT", in: animation)
                }

                VStack(spacing: 6) {
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
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: isCenter ? 26 : 22, weight: .semibold))
                                    .foregroundStyle(iconColor)
                            case .failure:
                                Image(systemName: icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: isCenter ? 26 : 22, weight: .semibold))
                                    .foregroundStyle(iconColor)
                            @unknown default:
                                Image(systemName: icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: isCenter ? 26 : 22, weight: .semibold))
                                    .foregroundStyle(iconColor)
                            }
                        }
                        .frame(width: isCenter ? 28 : 24, height: isCenter ? 28 : 24)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.white.opacity(0.9) : Color.clear, lineWidth: isSelected ? 2 : 0)
                        )
                        .scaleEffect(isSelected ? 1.08 : 1.0)
                    } else {
                        Image(systemName: icon)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: isCenter ? 26 : 22, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? themeManager.primaryColor : Color.primary.opacity(0.6))
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                    }

                Text(title)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? themeManager.primaryColor : Color.primary.opacity(0.6))
                        .opacity(isSelected ? 1.0 : 0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .offset(y: isSelected ? -2 : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var iconColor: Color {
        isSelected ? themeManager.primaryColor : Color.primary.opacity(0.8)
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

// MARK: - Liquid Glass Modifier

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    
    func body(content: Content) -> some View {
        if !reduceTransparency {
            // Simulate Liquid Glass for iOS 26
            content
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                             Color.white.opacity(0.1).blendMode(.overlay)
                        )
                        .shadow(color: Color.white.opacity(0.2), radius: 10, x: -5, y: -5)
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 5, y: 5)
                }
        } else {
            content
                .background(
                    Color(uiColor: .systemBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: -5)
                )
        }
    }
}

extension View {
    func liquidGlass() -> some View {
        self.modifier(LiquidGlassModifier())
    }
}
