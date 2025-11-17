import SwiftUI
#if os(iOS)
import UIKit
import AuthenticationServices
import SafariServices
#endif

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var emblem: String = "🫧💖🌈"
    @State private var sparkle: String = "✨"
    @State private var showPassword: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var showResetEmailSent: Bool = false
    @State private var showSignUpEmailSent: Bool = false
    @State private var showNewPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isNewPasswordFocused: Bool
    @FocusState private var isConfirmPasswordFocused: Bool

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
                .contentShape(Rectangle())
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    isEmailFocused = false
                    isPasswordFocused = false
                    isNewPasswordFocused = false
                    isConfirmPasswordFocused = false
                }

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
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Sign in with Apple (first option)
                #if os(iOS)
                SignInWithAppleButton(
                    onRequest: { request in
                        viewModel.prepareSignInWithAppleRequest(request)
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            // Store user identifier for future sign-ins
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                UserDefaults.standard.set(appleIDCredential.user, forKey: "appleUserIdentifier")
                            }
                            Task {
                                await viewModel.signInWithApple(authorization: authorization)
                            }
                        case .failure(let error):
                            viewModel.handleAppleAuthorizationError(error)
                            #if DEBUG
                            let nsError = error as NSError
                            print("[Auth] Apple Sign In error: \(error.localizedDescription), code: \(nsError.code), domain: \(nsError.domain)")
                            #endif
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: isPad ? 56 : 50)
                .cornerRadius(isPad ? 28 : 25)
                .padding(.horizontal)
                .disabled(viewModel.isLoadingApple)
                #endif

                // Playful divider
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 2)
                    Text("or use email")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.primary.opacity(0.6))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 2)
                }
                .padding(.horizontal)

                // Password Reset Mode UI
                if viewModel.isPasswordResetMode {
                    VStack(spacing: isPad ? 20 : 16) {
                        Text("Set New Password")
                            .font(
                                isPad
                                ? .system(size: 32, weight: .bold, design: .rounded)
                                : .system(.title, design: .rounded).weight(.bold)
                            )
                            .padding(.bottom, 4)
                        
                        Text("Enter your new password below")
                            .font(isPad ? .system(.body, design: .rounded) : .system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .padding(.bottom, isPad ? 8 : 4)
                        
                        // New Password field
                        HStack(spacing: isPad ? 14 : 12) {
                            ZStack {
                                Circle()
                                    .fill(.blue.gradient)
                                    .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
                                    .shadow(color: .blue.opacity(0.25), radius: isPad ? 10 : 8, x: 0, y: 4)
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.white)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.thinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                                HStack {
                                    if showNewPassword {
                                        TextField("New Password", text: $viewModel.newPassword)
                                            .textContentType(.newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                            .focused($isNewPasswordFocused)
                                    } else {
                                        SecureField("New Password", text: $viewModel.newPassword)
                                            .textContentType(.newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                            .focused($isNewPasswordFocused)
                                    }
                                    Button(action: { showNewPassword.toggle() }) {
                                        Image(systemName: showNewPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(.secondary)
                                            .font(isPad ? .title3 : .body)
                                    }
                                }
                                .padding(.horizontal, isPad ? 16 : 14)
                                .padding(.vertical, isPad ? 12 : 10)
                            }
                            .frame(height: isPad ? 52 : 44)
                        }
                        
                        // Confirm Password field
                        HStack(spacing: isPad ? 14 : 12) {
                            ZStack {
                                Circle()
                                    .fill(.cyan.gradient)
                                    .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
                                    .shadow(color: .cyan.opacity(0.25), radius: isPad ? 10 : 8, x: 0, y: 4)
                                Image(systemName: "lock.rotation")
                                    .foregroundStyle(.white)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.thinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                    )
                                HStack {
                                    if showConfirmPassword {
                                        TextField("Confirm Password", text: $viewModel.confirmPassword)
                                            .textContentType(.newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                            .focused($isConfirmPasswordFocused)
                                    } else {
                                        SecureField("Confirm Password", text: $viewModel.confirmPassword)
                                            .textContentType(.newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                            .focused($isConfirmPasswordFocused)
                                    }
                                    Button(action: { showConfirmPassword.toggle() }) {
                                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(.secondary)
                                            .font(isPad ? .title3 : .body)
                                    }
                                }
                                .padding(.horizontal, isPad ? 16 : 14)
                                .padding(.vertical, isPad ? 12 : 10)
                            }
                            .frame(height: isPad ? 52 : 44)
                        }
                        
                        // Update Password button
                        Button(action: {
                            Task {
                                await viewModel.updatePasswordAfterReset()
                            }
                        }) {
                            HStack(spacing: isPad ? 10 : 8) {
                                if viewModel.isLoadingEmail { ProgressView() }
                                Text(viewModel.isLoadingEmail ? "Updating…" : "Update Password")
                                    .font(
                                        isPad
                                        ? .system(.title3, design: .rounded).weight(.semibold)
                                        : .system(.headline, design: .rounded).weight(.semibold)
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isPad ? 16 : 14)
                            .background(
                                LinearGradient(colors: [.green.opacity(0.95), .mint.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(color: .green.opacity(0.25), radius: isPad ? 12 : 10, x: 0, y: 8)
                        }
                        .disabled(viewModel.isLoadingEmail)
                        
                        Button(action: {
                            viewModel.cancelPasswordReset()
                        }) {
                            Text("Cancel")
                                .font(isPad ? .footnote : .caption)
                                .foregroundStyle(Color.primary.opacity(0.7))
                        }
                        .padding(.top, 4)
                    }
                    .padding(isPad ? 18 : 16)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.06), radius: isPad ? 18 : 16, x: 0, y: 10)
                    )
                    .padding(.horizontal)
                } else {
                    // Email/Password card
                    VStack(spacing: isPad ? 14 : 12) {
                        // Email field (hide when showing reset or sign up email sent success)
                        if !showResetEmailSent && !showSignUpEmailSent {
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
                                        .focused($isEmailFocused)
                                }
                                .frame(height: isPad ? 52 : 44)
                            }
                        }

                        // Password field (only show when not in forgot password mode and not showing sign up success)
                        if !showForgotPassword && !showSignUpEmailSent {
                            HStack(spacing: isPad ? 14 : 12) {
                                ZStack {
                                    Circle()
                                        .fill(.purple.gradient)
                                        .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
                                        .shadow(color: .purple.opacity(0.25), radius: isPad ? 10 : 8, x: 0, y: 4)
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.white)
                                }
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.thinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                        )
                                    HStack {
                                        if showPassword {
                                            TextField("Password", text: $viewModel.password)
                                                .textContentType(viewModel.authMode == .signUp ? .newPassword : .password)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                                .focused($isPasswordFocused)
                                        } else {
                                            SecureField("Password", text: $viewModel.password)
                                                .textContentType(viewModel.authMode == .signUp ? .newPassword : .password)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .font(isPad ? .system(.title3, design: .rounded) : .system(.body, design: .rounded))
                                                .focused($isPasswordFocused)
                                        }
                                        Button(action: { showPassword.toggle() }) {
                                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                                .foregroundStyle(.secondary)
                                                .font(isPad ? .title3 : .body)
                                        }
                                    }
                                    .padding(.horizontal, isPad ? 16 : 14)
                                    .padding(.vertical, isPad ? 12 : 10)
                                }
                                .frame(height: isPad ? 52 : 44)
                            }
                        }

                    // Forgot password link (only show in sign in mode and not already showing forgot password)
                    if viewModel.authMode == .signIn && !showForgotPassword {
                        HStack {
                            Spacer()
                            Button(action: {
                                showForgotPassword = true
                            }) {
                                Text("Forgot Password?")
                                    .font(isPad ? .footnote : .caption)
                                    .foregroundStyle(Color.primary.opacity(0.7))
                            }
                            .padding(.trailing, isPad ? 4 : 2)
                        }
                    }

                    // Forgot password email input (when forgot password is active)
                    if showForgotPassword {
                        if showResetEmailSent {
                            // Success state - email sent
                            VStack(spacing: isPad ? 24 : 20) {
                                ZStack {
                                    Circle()
                                        .fill(.green.gradient)
                                        .frame(width: isPad ? 80 : 64, height: isPad ? 80 : 64)
                                        .shadow(color: .green.opacity(0.3), radius: isPad ? 16 : 12, x: 0, y: 8)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: isPad ? 40 : 32, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                VStack(spacing: isPad ? 12 : 8) {
                                    Text("Check your email")
                                        .font(
                                            isPad
                                            ? .system(size: 28, weight: .bold, design: .rounded)
                                            : .system(.title2, design: .rounded).weight(.bold)
                                        )
                                    
                                    Text("We've sent a password reset link to")
                                        .font(isPad ? .system(.body, design: .rounded) : .system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                    
                                    Text(viewModel.email)
                                        .font(isPad ? .system(.body, design: .rounded).weight(.semibold) : .system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("Click the link in the email to reset your password.")
                                        .font(isPad ? .system(.body, design: .rounded) : .system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 4)
                                }
                                
                                Button(action: {
                                    showForgotPassword = false
                                    showResetEmailSent = false
                                }) {
                                    Text("Back to Sign In")
                                        .font(isPad ? .footnote : .caption)
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                }
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isPad ? 24 : 20)
                        } else {
                            // Email input and send button
                            Button(action: {
                                Task {
                                    await viewModel.resetPassword()
                                    if viewModel.noticeMessage != nil {
                                        showResetEmailSent = true
                                    }
                                }
                            }) {
                                HStack(spacing: isPad ? 10 : 8) {
                                    if viewModel.isLoadingEmail { ProgressView() }
                                    Text(viewModel.isLoadingEmail ? "Sending…" : "Send Reset Email")
                                        .font(
                                            isPad
                                            ? .system(.title3, design: .rounded).weight(.semibold)
                                            : .system(.headline, design: .rounded).weight(.semibold)
                                        )
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, isPad ? 16 : 14)
                                .background(
                                    LinearGradient(colors: [.blue.opacity(0.95), .cyan.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: .blue.opacity(0.25), radius: isPad ? 12 : 10, x: 0, y: 8)
                            }
                            .disabled(viewModel.isLoadingEmail)
                            
                            Button(action: {
                                showForgotPassword = false
                                showResetEmailSent = false
                            }) {
                                Text("Back to Sign In")
                                    .font(isPad ? .footnote : .caption)
                                    .foregroundStyle(Color.primary.opacity(0.7))
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        // Show sign up success UI or regular sign in/sign up buttons
                        if showSignUpEmailSent {
                            // Success state - sign up email confirmation sent
                            VStack(spacing: isPad ? 24 : 20) {
                                ZStack {
                                    Circle()
                                        .fill(.green.gradient)
                                        .frame(width: isPad ? 80 : 64, height: isPad ? 80 : 64)
                                        .shadow(color: .green.opacity(0.3), radius: isPad ? 16 : 12, x: 0, y: 8)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: isPad ? 40 : 32, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                VStack(spacing: isPad ? 12 : 8) {
                                    Text("Check your email")
                                        .font(
                                            isPad
                                            ? .system(size: 28, weight: .bold, design: .rounded)
                                            : .system(.title2, design: .rounded).weight(.bold)
                                        )
                                    
                                    Text("We've sent a confirmation link to")
                                        .font(isPad ? .system(.body, design: .rounded) : .system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                    
                                    Text(viewModel.email)
                                        .font(isPad ? .system(.body, design: .rounded).weight(.semibold) : .system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("Click the link in the email to confirm your account and get started.")
                                        .font(isPad ? .system(.body, design: .rounded) : .system(.subheadline, design: .rounded))
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 4)
                                }
                                
                                Button(action: {
                                    showSignUpEmailSent = false
                                    viewModel.authMode = .signIn
                                }) {
                                    Text("Back to Sign In")
                                        .font(isPad ? .footnote : .caption)
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                }
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isPad ? 24 : 20)
                        } else {
                            // Sign in/Sign up button
                            Button(action: {
                                Task {
                                    if viewModel.authMode == .signIn {
                                        await viewModel.signInWithEmail()
                                    } else {
                                        await viewModel.signUpWithEmail()
                                        if viewModel.noticeMessage != nil {
                                            showSignUpEmailSent = true
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: isPad ? 10 : 8) {
                                    if viewModel.isLoadingEmail { ProgressView() }
                                    Text(viewModel.isLoadingEmail ? "Please wait…" : (viewModel.authMode == .signIn ? "Sign In" : "Sign Up"))
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
                            .disabled(viewModel.isLoadingEmail)

                            // Toggle between sign in and sign up
                            Button(action: {
                                withAnimation {
                                    viewModel.authMode = viewModel.authMode == .signIn ? .signUp : .signIn
                                    viewModel.password = ""
                                    viewModel.errorMessage = nil
                                    showSignUpEmailSent = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(viewModel.authMode == .signIn ? "Don't have an account?" : "Already have an account?")
                                        .font(isPad ? .footnote : .caption)
                                        .foregroundStyle(Color.primary.opacity(0.7))
                                    Text(viewModel.authMode == .signIn ? "Sign Up" : "Sign In")
                                        .font(isPad ? .footnote : .caption)
                                        .foregroundStyle(.purple)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(isPad ? 18 : 16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.06), radius: isPad ? 18 : 16, x: 0, y: 10)
                )
                .padding(.horizontal)
                }

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
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .padding(.top, 2)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                        .font(isPad ? .footnote : .caption2)
                        .foregroundStyle(Color.primary.opacity(0.7))
                    Button("Terms") {
                        Task {
                            await openURL(urlString: "https://schedulr.co.uk/terms")
                        }
                    }
                    .font(isPad ? .footnote : .caption2)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    Text("&")
                        .font(isPad ? .footnote : .caption2)
                        .foregroundStyle(Color.primary.opacity(0.7))
                    Button("Privacy Policy") {
                        Task {
                            await openURL(urlString: "https://schedulr.co.uk/privacy")
                        }
                    }
                    .font(isPad ? .footnote : .caption2)
                    .foregroundStyle(Color.primary.opacity(0.7))
                }
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
    
    /// Opens a URL in SFSafariViewController
    /// No tracking is performed - cookies are only used for essential website functionality
    private func openURL(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        #if os(iOS)
        // Use SFSafariViewController for better in-app experience
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = .systemPurple
        safariVC.preferredBarTintColor = .systemBackground
        if #available(iOS 11.0, *) {
            safariVC.dismissButtonStyle = .close
        }
        
        // Present the Safari view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(safariVC, animated: true)
        }
        #else
        await UIApplication.shared.open(url)
        #endif
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
