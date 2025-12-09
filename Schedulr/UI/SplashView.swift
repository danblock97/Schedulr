import SwiftUI

struct SplashView: View {
    // Parent can control visibility; when set to false, the view fades out.
    @Binding var isVisible: Bool
    @State private var showTagline: Bool = false
    @State private var shimmerActive: Bool = false

    // Copy-friendly, calm welcome lines.
    private let primaryTagline = "Welcome to Schedulr"
    private let secondaryTagline = "Setting up your day..."

    // Gradient approximating the logo colors: pink -> purple -> blue -> teal -> green -> yellow
    private var splashGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.98, green: 0.29, blue: 0.55), // pink
                Color(red: 0.58, green: 0.41, blue: 0.87), // purple
                Color(red: 0.27, green: 0.63, blue: 0.98), // blue
                Color(red: 0.20, green: 0.78, blue: 0.74), // teal
                Color(red: 0.59, green: 0.85, blue: 0.34), // green
                Color(red: 1.00, green: 0.78, blue: 0.16)  // yellow
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            splashGradient
                .overlay(Color.black.opacity(0.08)) // soften the background while keeping brand colors
                .ignoresSafeArea()

            VStack(spacing: 24) {
                logoImageView()
                taglineView()
                loadingSkeleton()
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: isVisible)
        .onAppear {
            showTagline = true
            shimmerActive = true
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                showTagline = false
                shimmerActive = false
            }
        }
    }

    @ViewBuilder
    private func logoImageView() -> some View {
        // Try a normal image set first (recommended): "schedulr-logo"
        if UIImage(named: "schedulr-logo") != nil {
            Image("schedulr-logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
                .accessibilityLabel("Schedulr Logo")
        } else if UIImage(named: "schedulr-logo-any") != nil {
            // Fallback name if you create an image set with this name
            Image("schedulr-logo-any")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
                .accessibilityLabel("Schedulr Logo")
        } else {
            #if DEBUG
            // Placeholder + debug hint to add a proper Image Set
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Add an Image Set named 'schedulr-logo' in Assets.xcassets")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityHidden(true)
            #else
            EmptyView()
            #endif
        }
    }

    @ViewBuilder
    private func taglineView() -> some View {
        VStack(spacing: 6) {
            Text(primaryTagline)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .accessibilityAddTraits(.isHeader)

            Text(secondaryTagline)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
        }
        .multilineTextAlignment(.center)
        .opacity(showTagline ? 1 : 0)
        .offset(y: showTagline ? 0 : 12)
        .animation(.easeOut(duration: 0.6), value: showTagline)
    }

    @ViewBuilder
    private func loadingSkeleton() -> some View {
        LoadingBouncingDots(isAnimating: shimmerActive)
            .frame(height: 24)
            .accessibilityLabel("Loading")
            .accessibilityHint("Please wait while we prepare your schedule")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isVisible)
    }
}

#Preview("SplashView") {
    StatefulPreviewWrapper(true) { isVisible in
        SplashView(isVisible: isVisible)
    }
}

// Helper to preview a binding
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

/// Calm bouncing dots loader to replace a simple bar.
private struct LoadingBouncingDots: View {
    var isAnimating: Bool
    private let dotCount = 3
    private let baseSize: CGFloat = 10

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<dotCount, id: \.self) { index in
                    let phaseShift = Double(index) * 0.25
                    let progress = (time + phaseShift).truncatingRemainder(dividingBy: 1.2) / 1.2
                    let bounce = sin(progress * .pi * 2)
                    let scale = 0.82 + 0.18 * max(bounce, 0) // keep it subtle
                    let verticalOffset = -8 * max(bounce, 0)

                    Circle()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: baseSize, height: baseSize)
                        .scaleEffect(isAnimating ? scale : 1.0)
                        .offset(y: isAnimating ? verticalOffset : 0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 24)
    }
}
