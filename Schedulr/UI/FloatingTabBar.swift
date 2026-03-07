import SwiftUI
import UIKit

struct FloatingTabBar: View {
    static let reservedHeight: CGFloat = 112

    @Binding var selectedTab: Int
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var animation

    var avatarURL: String?

    var body: some View {
        GeometryReader { proxy in
            let metrics = FloatingTabBarMetrics(
                containerWidth: proxy.size.width,
                bottomInset: max(proxy.safeAreaInsets.bottom, fallbackBottomInset),
                idiom: UIDevice.current.userInterfaceIdiom,
                horizontalSizeClass: horizontalSizeClass
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: metrics.itemSpacing) {
                    ForEach(FloatingTabItem.allCases, id: \.rawValue) { item in
                        TabBarButton(
                            item: item,
                            selectedTab: $selectedTab,
                            animation: animation,
                            themeManager: themeManager,
                            metrics: metrics,
                            avatarURL: avatarURL
                        )
                    }
                }
                .padding(.horizontal, metrics.barHorizontalPadding)
                .padding(.top, metrics.barTopPadding)
                .padding(.bottom, metrics.barBottomPadding + max(metrics.bottomInset - 6, 0))
                .frame(maxWidth: metrics.barWidth)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 1)
                        }
                        .overlay(alignment: .topLeading) {
                            RadialGradient(
                                colors: [
                                    themeManager.primaryColor.opacity(colorScheme == .dark ? 0.12 : 0.10),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: 220
                            )
                        }
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 18, x: 0, y: -3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: Self.reservedHeight)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
    }

    private var fallbackBottomInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
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

private enum FloatingTabItem: Int, CaseIterable {
    case home = 0
    case calendar = 1
    case ai = 2
    case profile = 3

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .ai: return "sparkles"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .calendar: return "Calendar"
        case .ai: return "AI"
        case .profile: return "Profile"
        }
    }
}

private struct FloatingTabBarMetrics {
    let containerWidth: CGFloat
    let bottomInset: CGFloat
    let idiom: UIUserInterfaceIdiom
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var isPadLayout: Bool {
        idiom == .pad || (horizontalSizeClass == .regular && containerWidth >= 700)
    }

    private var isCompactPhone: Bool {
        !isPadLayout && containerWidth <= 350
    }

    private var isLargePhone: Bool {
        !isPadLayout && containerWidth >= 430
    }

    var barWidth: CGFloat {
        if isPadLayout {
            return min(containerWidth, 820)
        }
        return containerWidth
    }

    var outerHorizontalPadding: CGFloat {
        if isPadLayout { return 24 }
        return isCompactPhone ? 10 : 14
    }

    var barHorizontalPadding: CGFloat {
        if isPadLayout { return 52 }
        return isCompactPhone ? 12 : (isLargePhone ? 28 : 18)
    }

    var barTopPadding: CGFloat {
        if isPadLayout { return 11 }
        return isCompactPhone ? 9 : 10
    }

    var barBottomPadding: CGFloat {
        if isPadLayout { return 10 }
        return isCompactPhone ? 8 : 9
    }

    var itemSpacing: CGFloat {
        if isPadLayout { return 20 }
        return isCompactPhone ? 6 : 10
    }

    var buttonCornerRadius: CGFloat {
        if isPadLayout { return 24 }
        return isCompactPhone ? 18 : 21
    }

    var barCornerRadius: CGFloat {
        if isPadLayout { return 34 }
        return isCompactPhone ? 26 : 30
    }

    var buttonHorizontalPadding: CGFloat {
        if isPadLayout { return 12 }
        return isCompactPhone ? 4 : 8
    }

    var buttonVerticalPadding: CGFloat {
        if isPadLayout { return 9 }
        return isCompactPhone ? 9 : 10
    }

    var iconCircleSize: CGFloat {
        if isPadLayout { return 42 }
        return isCompactPhone ? 34 : (isLargePhone ? 40 : 37)
    }

    var iconSize: CGFloat {
        if isPadLayout { return 20 }
        return isCompactPhone ? 16 : 18
    }

    var labelSize: CGFloat {
        if isPadLayout { return 13.5 }
        return isCompactPhone ? 11 : 12
    }

    var selectedLabelSize: CGFloat {
        if isPadLayout { return 14.5 }
        return isCompactPhone ? 11.5 : 12.5
    }

    var itemContentSpacing: CGFloat {
        isCompactPhone ? 5 : 6
    }
}

private struct TabBarButton: View {
    let item: FloatingTabItem
    @Binding var selectedTab: Int
    let animation: Namespace.ID
    @ObservedObject var themeManager: ThemeManager
    let metrics: FloatingTabBarMetrics
    var avatarURL: String?

    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool {
        selectedTab == item.rawValue
    }

    private var isProfileTab: Bool {
        item == .profile
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedTab = item.rawValue
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: metrics.itemContentSpacing) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        themeManager.primaryColor.opacity(colorScheme == .dark ? 0.95 : 0.90),
                                        themeManager.secondaryColor.opacity(colorScheme == .dark ? 0.78 : 0.72)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .matchedGeometryEffect(id: "ACTIVE_TAB_ICON", in: animation)
                            .shadow(color: themeManager.primaryColor.opacity(0.24), radius: 10, x: 0, y: 6)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.18))
                            .scaleEffect(0.88)
                    }

                    iconView
                }
                .frame(width: metrics.iconCircleSize, height: metrics.iconCircleSize)

                Text(item.title)
                    .font(.system(size: isSelected ? metrics.selectedLabelSize : metrics.labelSize, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                Capsule(style: .continuous)
                    .fill(selectionIndicator)
                    .frame(width: isSelected ? metrics.iconCircleSize - 6 : 6, height: 4)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.buttonHorizontalPadding)
            .padding(.vertical, metrics.buttonVerticalPadding)
            .contentShape(RoundedRectangle(cornerRadius: metrics.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var iconView: some View {
        if isProfileTab, let avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackIcon
                }
            }
            .frame(width: metrics.iconCircleSize - 4, height: metrics.iconCircleSize - 4)
            .clipShape(Circle())
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(.white.opacity(0.85), lineWidth: 1.5)
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: item.icon)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: metrics.iconSize, weight: .semibold))
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        isSelected ? .white : Color.primary.opacity(colorScheme == .dark ? 0.84 : 0.70)
    }

    private var labelColor: Color {
        isSelected ? Color.primary : Color.primary.opacity(colorScheme == .dark ? 0.76 : 0.66)
    }

    private var selectionIndicator: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        themeManager.primaryColor.opacity(0.92),
                        themeManager.secondaryColor.opacity(0.78)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }

        return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        FloatingTabBar(selectedTab: .constant(1), avatarURL: nil)
            .environmentObject(ThemeManager.shared)
    }
}
