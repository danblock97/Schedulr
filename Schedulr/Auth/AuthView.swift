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

    // Refined gradient matching app color scheme
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.96, blue: 0.99), // Soft lavender-white
                Color(red: 0.95, green: 0.92, blue: 0.98), // Warm lavender tint
                Color(red: 0.92, green: 0.95, blue: 1.00), // Soft blue-white
                Color(red: 0.89, green: 0.97, blue: 0.98)  // Soft mint-white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()

            // Refined, subtle bubbly background
            BubbleBackground()
                .scaleEffect(isPad ? 1.18 : 1.0)
                .allowsHitTesting(false)

            VStack(spacing: isPad ? 28 : 24) {
                Spacer()
                
                // Polished header with refined typography
                VStack(spacing: isPad ? 12 : 10) {
                    Text(emblem)
                        .font(.system(size: isPad ? 72 : 56))
                    
                    Text("Welcome to Schedulr")
                        .font(
                            isPad
                            ? .system(size: 42, weight: .bold, design: .rounded)
                            : .system(size: 32, weight: .bold, design: .rounded)
                        )
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.top, isPad ? 8 : 4)
                    
                    Text("Plan your day with a sprinkle of magic \(sparkle)")
                        .font(
                            isPad
                            ? .system(size: 20, weight: .medium, design: .rounded)
                            : .system(size: 16, weight: .medium, design: .rounded)
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, isPad ? 32 : 24)
                        .lineSpacing(2)
                }

                // Professional Google button with refined styling
                Button(action: { 
                    #if os(iOS)
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    #endif
                    Task { await viewModel.signInWithGoogle() } 
                }) {
                    HStack(spacing: isPad ? 16 : 14) {
                        Image(systemName: "g.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(isPad ? .system(size: 24) : .system(size: 22))
                        
                        Text(viewModel.isLoadingGoogle ? "Connecting…" : "Continue with Google")
                            .font(
                                isPad
                                ? .system(size: 19, weight: .semibold, design: .rounded)
                                : .system(size: 17, weight: .semibold, design: .rounded)
                            )
                        
                        Spacer(minLength: 0)
                        
                        if viewModel.isLoadingGoogle { 
                            ProgressView()
                                .tint(.primary)
                        }
                    }
                    .padding(.horizontal, isPad ? 26 : 22)
                    .padding(.vertical, isPad ? 18 : 16)
                    .background(.white)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: isPad ? 16 : 14, x: 0, y: isPad ? 6 : 5)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(AuthButtonStyle())
                .disabled(viewModel.isLoadingGoogle)
                .padding(.horizontal, isPad ? 32 : 24)

                // Refined divider
                HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1.5)
                        
                        Text("or use email")
                            .font(.system(size: isPad ? 14 : 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1.5)
                }
                .padding(.horizontal, isPad ? 32 : 24)
                .padding(.vertical, isPad ? 4 : 2)

                // Polished email card with refined materials
                VStack(spacing: isPad ? 16 : 14) {
                    HStack(spacing: isPad ? 14 : 12) {
                        // Email icon
                        ZStack {
                            Circle()
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
                                .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
                            
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: isPad ? 18 : 16, weight: .semibold))
                        }
                        
                        // Email input field
                        TextField("your@email.com", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: isPad ? 17 : 16, weight: .regular, design: .rounded))
                            .padding(.horizontal, isPad ? 18 : 16)
                            .padding(.vertical, isPad ? 14 : 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .frame(height: isPad ? 52 : 44)
                    }

                    Button(action: { 
                        #if os(iOS)
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        #endif
                        Task { await viewModel.sendMagicLink() } 
                    }) {
                        HStack(spacing: isPad ? 10 : 8) {
                            if viewModel.isLoadingMagic { 
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: isPad ? 18 : 16, weight: .semibold))
                            }
                            
                            Text(viewModel.isLoadingMagic ? "Sending…" : "Send Magic Link")
                                .font(
                                    isPad
                                    ? .system(size: 19, weight: .semibold, design: .rounded)
                                    : .system(size: 17, weight: .semibold, design: .rounded)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isPad ? 18 : 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4), radius: isPad ? 14 : 12, x: 0, y: isPad ? 6 : 5)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(AuthButtonStyle())
                    .disabled(viewModel.isLoadingMagic)
                }
                .padding(isPad ? 22 : 20)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.08), radius: isPad ? 20 : 18, x: 0, y: isPad ? 8 : 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, isPad ? 32 : 24)

                // Error message styling
                if let error = viewModel.errorMessage, !error.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(error)
                            .font(.system(size: isPad ? 14 : 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, isPad ? 32 : 24)
                    .padding(.vertical, isPad ? 12 : 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, isPad ? 32 : 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Notice message styling
                if let notice = viewModel.noticeMessage, !notice.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(notice)
                            .font(.system(size: isPad ? 14 : 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, isPad ? 32 : 24)
                    .padding(.vertical, isPad ? 12 : 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, isPad ? 32 : 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Refined legal text
                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(.system(size: isPad ? 13 : 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isPad ? 32 : 24)
                    .padding(.top, isPad ? 8 : 6)
                    .padding(.bottom, 12)
                
                Spacer()
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

// Custom button style for polished interactions
private struct AuthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Refined, subtle bubbly background
private struct BubbleBackground: View {
    var body: some View {
        ZStack {
            // Larger, more subtle bubbles
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.15),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: -140, y: -280)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.12),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 32)
                .offset(x: 150, y: -220)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.78, blue: 0.74).opacity(0.15),
                            Color(red: 0.27, green: 0.63, blue: 0.98).opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 38)
                .offset(x: 0, y: 300)

            // Subtle accent bubbles
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 24, height: 24)
                .blur(radius: 2)
                .offset(x: -170, y: -50)

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 18, height: 18)
                .blur(radius: 2)
                .offset(x: 150, y: 70)

            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 14, height: 14)
                .blur(radius: 1.5)
                .offset(x: -50, y: 180)
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel())
}
