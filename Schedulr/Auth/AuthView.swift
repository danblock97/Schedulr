import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var emblem: String = "🫧💖🌈"
    @State private var sparkle: String = "✨"

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif

    private let emblemOptions: [String] = [
        "🫧💖🌈", "☁️🌸🫧", "🌈🫧✨", "🧁✨🫧", "⭐️🫧🌈", "🍓🫧✨"
    ]
    private let sparkleOptions: [String] = ["✨", "💫", "🌟"]

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.82, blue: 0.93),
                Color(red: 0.87, green: 0.93, blue: 1.00),
                Color(red: 0.86, green: 1.00, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()

            // Playful, bubbly background circles
            BubbleBackground()
                .scaleEffect(isPad ? 1.18 : 1.0)
                .allowsHitTesting(false)

            VStack(spacing: isPad ? 26 : 22) {
                // Cute header with playful emoji variants
                VStack(spacing: 8) {
                    Text(emblem)
                        .font(.system(size: isPad ? 72 : 56))
                    Text("Welcome to Schedulr")
                        .font(
                            isPad
                            ? .system(size: 44, weight: .heavy, design: .rounded)
                            : .system(.largeTitle, design: .rounded).weight(.heavy)
                        )
                        .multilineTextAlignment(.center)
                    Text("Plan your day with a sprinkle of magic \(sparkle)")
                        .font(
                            isPad
                            ? .system(.title3, design: .rounded).weight(.medium)
                            : .system(.subheadline, design: .rounded).weight(.medium)
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Google first (moved above email)
                Button(action: { Task { await viewModel.signInWithGoogle() } }) {
                    HStack(spacing: isPad ? 14 : 12) {
                        Image(systemName: "g.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(isPad ? .title : .title2)
                        Text(viewModel.isLoadingGoogle ? "Connecting…" : "Continue with Google")
                            .font(
                                isPad
                                ? .system(.title3, design: .rounded).weight(.semibold)
                                : .system(.headline, design: .rounded).weight(.semibold)
                            )
                        Spacer(minLength: 0)
                        if viewModel.isLoadingGoogle { ProgressView() }
                    }
                    .padding(.horizontal, isPad ? 24 : 20)
                    .padding(.vertical, isPad ? 16 : 14)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.06), radius: isPad ? 14 : 12, x: 0, y: 10)
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }
                .disabled(viewModel.isLoadingGoogle)

                // Playful divider
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 2)
                    Text("or use email")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 2)
                }
                .padding(.horizontal)

                // Email card
                VStack(spacing: isPad ? 14 : 12) {
                    HStack(spacing: isPad ? 14 : 12) {
                        ZStack {
                            Circle()
                                .fill(.pink.gradient)
                                .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
                                .shadow(color: .pink.opacity(0.25), radius: isPad ? 10 : 8, x: 0, y: 4)
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.white)
                        }
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                )
                            TextField("your@email.com", text: $viewModel.email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                .padding(.horizontal, isPad ? 16 : 14)
                                .padding(.vertical, isPad ? 12 : 10)
                        }
                        .frame(height: isPad ? 52 : 44)
                    }

                    Button(action: { Task { await viewModel.sendMagicLink() } }) {
                        HStack(spacing: isPad ? 10 : 8) {
                            if viewModel.isLoadingMagic { ProgressView() }
                            Text(viewModel.isLoadingMagic ? "Sending…" : "Send Magic Link")
                                .font(
                                    isPad
                                    ? .system(.title3, design: .rounded).weight(.semibold)
                                    : .system(.headline, design: .rounded).weight(.semibold)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isPad ? 16 : 14)
                        .background(
                            LinearGradient(colors: [.purple.opacity(0.95), .pink.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .purple.opacity(0.25), radius: isPad ? 12 : 10, x: 0, y: 8)
                    }
                    .disabled(viewModel.isLoadingMagic)

                    // Magic link notice now shown via noticeMessage for consistency.
                }
                .padding(isPad ? 18 : 16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.06), radius: isPad ? 18 : 16, x: 0, y: 10)
                )
                .padding(.horizontal)

                if let error = viewModel.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                if let notice = viewModel.noticeMessage, !notice.isEmpty {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(isPad ? .footnote : .caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, isPad ? 28 : 16)
            .frame(maxWidth: isPad ? 560 : .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            viewModel.loadInitialSession()
            emblem = emblemOptions.randomElement() ?? emblem
            sparkle = sparkleOptions.randomElement() ?? sparkle
        }
    }
}

private struct BubbleBackground: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.28))
                .frame(width: 200, height: 200)
                .blur(radius: 24)
                .offset(x: -130, y: -260)

            Circle()
                .fill(Color.blue.opacity(0.24))
                .frame(width: 240, height: 240)
                .blur(radius: 28)
                .offset(x: 130, y: -210)

            Circle()
                .fill(Color.mint.opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 34)
                .offset(x: 0, y: 280)

            // Extra tiny bubbles for a fuller feel
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 20, height: 20)
                .blur(radius: 1)
                .offset(x: -160, y: -40)

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 14, height: 14)
                .blur(radius: 1)
                .offset(x: 140, y: 60)

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 10, height: 10)
                .blur(radius: 1)
                .offset(x: -40, y: 160)
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel())
}
