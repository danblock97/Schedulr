import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            // Home Tab
            TabBarButton(
                icon: "house.fill",
                index: 0,
                selectedTab: $selectedTab,
                animation: animation
            )

            // Create Event Tab
            TabBarButton(
                icon: "plus.circle.fill",
                index: 1,
                selectedTab: $selectedTab,
                animation: animation,
                isCenter: true
            )

            // Ask AI Tab
            TabBarButton(
                icon: "sparkles",
                index: 2,
                selectedTab: $selectedTab,
                animation: animation
            )

            // Profile Tab
            TabBarButton(
                icon: "person.crop.circle.fill",
                index: 3,
                selectedTab: $selectedTab,
                animation: animation
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

struct TabBarButton: View {
    let icon: String
    let index: Int
    @Binding var selectedTab: Int
    let animation: Namespace.ID
    var isCenter: Bool = false

    var isSelected: Bool {
        selectedTab == index
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
                    // Selected background
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .matchedGeometryEffect(id: "TAB", in: animation)
                        .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4), radius: 8, x: 0, y: 4)
                }

                Image(systemName: icon)
                    .font(.system(size: isCenter ? 28 : 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(isSelected ? 1.0 : 0.9)
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
            FloatingTabBar(selectedTab: .constant(0))
        }
    }
}
