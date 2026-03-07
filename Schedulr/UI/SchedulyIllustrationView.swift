import SwiftUI

struct SchedulyIllustrationView: View {
    enum Style {
        case avatar
        case hero
    }

    @EnvironmentObject private var themeManager: ThemeManager

    let style: Style
    var showsBadge: Bool = false

    private var frameSize: CGSize {
        style == .hero ? CGSize(width: 164, height: 164) : CGSize(width: 50, height: 50)
    }

    private var bodySize: CGFloat {
        style == .hero ? 134 : 40
    }

    var body: some View {
        ZStack {
            if style == .hero {
                blobModel(size: bodySize)
                .offset(y: 6)
            } else {
                blobModel(size: bodySize)
            }

            if showsBadge {
                badge
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
    }

    private func blobModel(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(themeManager.primaryColor.opacity(0.22))
                .frame(width: size * 0.86, height: size * 0.86)
                .blur(radius: size * 0.1)
                .offset(y: size * 0.08)

            MainBodyShape()
                .fill(
                    LinearGradient(
                        colors: [
                            themeManager.primaryColor,
                            themeManager.secondaryColor.opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    MainBodyShape()
                        .stroke(Color.white.opacity(0.25), lineWidth: max(1, size * 0.01))
                        .padding(size * 0.012)
                )

            VStack(spacing: size * 0.065) {
                HStack(spacing: size * 0.225) {
                    PersonaEye(size: size * 0.17)
                    PersonaEye(size: size * 0.17)
                }
                .offset(y: size * 0.02)

                PersonaSmile(size: size * 0.18)
                    .offset(y: size * 0.045)
            }
        }
        .frame(width: size, height: size)
    }

    private var badge: some View {
        HStack(spacing: style == .hero ? 5 : 3) {
            Image(systemName: "sparkles")
                .font(.system(size: style == .hero ? 9 : 6, weight: .bold))
            Text("AI")
                .font(.system(size: style == .hero ? 11 : 7, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, style == .hero ? 9 : 6)
        .padding(.vertical, style == .hero ? 5 : 3)
        .background(themeManager.secondaryColor, in: Capsule())
        .offset(x: style == .hero ? 42 : 10, y: style == .hero ? -44 : -11)
    }
}

private struct PersonaEye: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)

            ZStack {
                Circle()
                    .fill(Color(white: 0.15))

                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: -size * 0.14, y: -size * 0.14)
            }
            .frame(width: size * 0.5, height: size * 0.5)
        }
    }
}

private struct PersonaSmile: View {
    let size: CGFloat

    var body: some View {
        Path { path in
            path.addArc(
                center: CGPoint(x: size / 2, y: 0),
                radius: size / 2,
                startAngle: .degrees(30),
                endAngle: .degrees(150),
                clockwise: false
            )
        }
        .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: max(1.5, size * 0.14), lineCap: .round))
        .frame(width: size, height: size * 0.44)
    }
}

private struct MainBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.2, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: 0), control: CGPoint(x: w / 2, y: -h * 0.05))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w * 1.05, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 1.1, y: h / 2))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h), control: CGPoint(x: w * 1.05, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.2, y: h), control: CGPoint(x: w / 2, y: h * 1.05))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.8), control: CGPoint(x: -w * 0.05, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.2), control: CGPoint(x: -w * 0.1, y: h / 2))
        path.addQuadCurve(to: CGPoint(x: w * 0.2, y: 0), control: CGPoint(x: -w * 0.05, y: 0))

        return path
    }
}

#Preview("Hero") {
    SchedulyIllustrationView(style: .hero, showsBadge: true)
        .environmentObject(ThemeManager.shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Avatar") {
    SchedulyIllustrationView(style: .avatar)
        .environmentObject(ThemeManager.shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}
