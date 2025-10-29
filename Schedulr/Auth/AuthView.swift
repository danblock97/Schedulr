import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.77, blue: 0.92),
                Color(red: 0.85, green: 0.91, blue: 1.00),
                Color(red: 0.84, green: 1.00, blue: 0.93)
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
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text("🫧✨")
                        .font(.system(size: 48))
                    Text("Welcome to Schedulr")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Plan your day with a sprinkle of magic ✨")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.pink.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        TextField("your@email.com", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { Task { await viewModel.sendMagicLink() } }) {
                        HStack {
                            if viewModel.isLoadingMagic { ProgressView() }
                            Text(viewModel.isLoadingMagic ? "Sending…" : "Send Magic Link")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.purple.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(viewModel.isLoadingMagic)

                    if viewModel.magicSent {
                        Label("Magic link sent! Check your email.", systemImage: "paperplane.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }
                .padding(.horizontal)

                Button(action: { Task { await viewModel.signInWithGoogle() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                        Text(viewModel.isLoadingGoogle ? "Connecting…" : "Continue with Google")
                            .fontWeight(.semibold)
                        Spacer()
                        if viewModel.isLoadingGoogle { ProgressView() }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 8)
                    .padding(.horizontal)
                }
                .disabled(viewModel.isLoadingGoogle)

                if let error = viewModel.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 10)

                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
        .onAppear { viewModel.loadInitialSession() }
    }
}

private struct BubbleBackground: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.pink.opacity(0.25))
                .frame(width: 180, height: 180)
                .blur(radius: 20)
                .offset(x: -120, y: -240)

            Circle()
                .fill(Color.blue.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 26)
                .offset(x: 120, y: -200)

            Circle()
                .fill(Color.mint.opacity(0.25))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: 0, y: 260)
        }
    }
}

#Preview {
    AuthView(viewModel: AuthViewModel())
}
