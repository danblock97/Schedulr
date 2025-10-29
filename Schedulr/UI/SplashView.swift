import SwiftUI

struct SplashView: View {
    // Parent can control visibility; when set to false, the view fades out.
    @Binding var isVisible: Bool

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
                .ignoresSafeArea()

            logoImageView()
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: isVisible)
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
