import SwiftUI

struct FloatingTabBar: View {
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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 22, x: 0, y: 16)
                    .shadow(color: Color.white.opacity(colorScheme == .dark ? 0.0 : 0.28), radius: 10, x: 0, y: -3)
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
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
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor.opacity(0.95),
                                    themeManager.secondaryColor.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 82, height: 82)
                        .matchedGeometryEffect(id: "TAB_BALL", in: animation)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.38), radius: 26, x: 0, y: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28),
                                            Color.clear
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    ),
                                    lineWidth: 2
                                )
                                .blur(radius: 0.6)
                                .offset(y: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                                .blur(radius: 12)
                                .opacity(0.5)
                        )
                        .offset(y: 4)
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
                            .foregroundStyle(isSelected ? Color.white : iconColor)
                            .scaleEffect(isSelected ? 1.12 : 1.0)
                    }

                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : iconColor)
                        .opacity(isSelected ? 1.0 : 0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70)
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
