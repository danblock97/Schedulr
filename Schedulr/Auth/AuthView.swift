import SwiftUI
#if os(iOS)
import UIKit
import AuthenticationServices
import SafariServices
#endif

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showPassword: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var showResetEmailSent: Bool = false
    @State private var showSignUpEmailSent: Bool = false
    @State private var showNewPassword: Bool = false
    @State private var showConfirmPassword: Bool = false
    @State private var animateIn = false
    @State private var logoScale: CGFloat = 0.5
    @State private var isButtonPressed = false
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isNewPasswordFocused: Bool
    @FocusState private var isConfirmPasswordFocused: Bool

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated background
                AuthAnimatedBackground()
                    .ignoresSafeArea()
                
                // Floating particles
                AuthFloatingParticles()
                    .ignoresSafeArea()
                
                // Main content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: geometry.safeAreaInsets.top + 40)
                        
                        // Logo and header
                        AuthHeaderView(animateIn: $animateIn, logoScale: $logoScale)
                            .padding(.bottom, 40)
                        
                        // Main auth card
                        if viewModel.isPasswordResetMode {
                            PasswordResetCard(
                                viewModel: viewModel,
                                showNewPassword: $showNewPassword,
                                showConfirmPassword: $showConfirmPassword,
                                isNewPasswordFocused: $isNewPasswordFocused,
                                isConfirmPasswordFocused: $isConfirmPasswordFocused
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        } else {
                            AuthFormCard(
                                viewModel: viewModel,
                                showPassword: $showPassword,
                                showForgotPassword: $showForgotPassword,
                                showResetEmailSent: $showResetEmailSent,
                                showSignUpEmailSent: $showSignUpEmailSent,
                                isEmailFocused: $isEmailFocused,
                                isPasswordFocused: $isPasswordFocused,
                                isPad: isPad
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                        
                        // Error/Notice messages
                        AuthMessagesView(viewModel: viewModel)
                            .padding(.top, 16)
                        
                        // Terms and Privacy
                        AuthFooterView()
                            .padding(.top, 24)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                    }
                    .padding(.horizontal, isPad ? 40 : 24)
                    .frame(maxWidth: isPad ? 520 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.isPasswordResetMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showForgotPassword)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showResetEmailSent)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSignUpEmailSent)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.authMode)
        .onAppear {
            viewModel.loadInitialSession()
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.1)) {
                logoScale = 1
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.2)) {
                animateIn = true
            }
        }
    }
    
    private func dismissKeyboard() {
        isEmailFocused = false
        isPasswordFocused = false
        isNewPasswordFocused = false
        isConfirmPasswordFocused = false
    }
}

// MARK: - Animated Background

private struct AuthAnimatedBackground: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas { context, size in
                // Base gradient
                let baseGradient = Gradient(colors: [
                    colorScheme == .dark ? Color(hex: "0a0a12") : Color(hex: "faf8ff"),
                    colorScheme == .dark ? Color(hex: "0c0815") : Color(hex: "f5f0ff"),
                    colorScheme == .dark ? Color(hex: "080a10") : Color(hex: "f0f5ff")
                ])
                
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        baseGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                
                // Animated blobs
                let blobs: [(Color, CGFloat, CGFloat, CGFloat)] = [
                    (themeManager.primaryColor.opacity(colorScheme == .dark ? 0.18 : 0.15), 0.15, 0.15, 0.5),
                    (themeManager.secondaryColor.opacity(colorScheme == .dark ? 0.15 : 0.12), 0.85, 0.25, 0.6),
                    (Color(hex: "06b6d4").opacity(colorScheme == .dark ? 0.12 : 0.10), 0.5, 0.5, 0.45),
                    (Color(hex: "f59e0b").opacity(colorScheme == .dark ? 0.10 : 0.08), 0.2, 0.75, 0.4),
                    (Color(hex: "10b981").opacity(colorScheme == .dark ? 0.08 : 0.06), 0.8, 0.85, 0.35)
                ]
                
                for (index, (color, baseX, baseY, baseRadius)) in blobs.enumerated() {
                    let offset = Double(index) * 0.7
                    let x = size.width * (baseX + 0.08 * sin(time * 0.25 + offset))
                    let y = size.height * (baseY + 0.06 * cos(time * 0.2 + offset))
                    let radius = min(size.width, size.height) * (baseRadius + 0.05 * sin(time * 0.15 + offset))
                    
                    let blobGradient = Gradient(colors: [color, color.opacity(0)])
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            blobGradient,
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .blur(radius: 80)
    }
}

// MARK: - Floating Particles

private struct AuthFloatingParticles: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    AuthParticle(
                        index: index,
                        containerSize: geometry.size
                    )
                }
            }
        }
    }
}

private struct AuthParticle: View {
    let index: Int
    let containerSize: CGSize
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0
    @State private var rotation: Double = 0
    
    private var size: CGFloat { CGFloat.random(in: 3...8) }
    private var startX: CGFloat { CGFloat.random(in: 0...1) * containerSize.width }
    private var startY: CGFloat { CGFloat.random(in: 0...1) * containerSize.height }
    
    var body: some View {
        Circle()
            .fill(
        LinearGradient(
            colors: [
                        themeManager.primaryColor.opacity(0.5),
                        themeManager.secondaryColor.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
            )
            .frame(width: CGFloat(4 + index % 4), height: CGFloat(4 + index % 4))
            .blur(radius: CGFloat(1 + index % 2))
            .position(x: containerSize.width * CGFloat(index % 5 + 1) / 6, 
                     y: containerSize.height * CGFloat(index % 4 + 1) / 5)
            .offset(offset)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                let delay = Double(index) * 0.15
                
                withAnimation(.easeOut(duration: 1).delay(delay)) {
                    opacity = 0.6
                }
                
                withAnimation(
                    .easeInOut(duration: Double.random(in: 5...9))
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    offset = CGSize(
                        width: CGFloat.random(in: -40...40),
                        height: CGFloat.random(in: -60...60)
                    )
                    rotation = Double.random(in: -30...30)
                }
            }
    }
}

// MARK: - Header View

private struct AuthHeaderView: View {
    @Binding var animateIn: Bool
    @Binding var logoScale: CGFloat
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 20) {
            // App logo with glow
        ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                themeManager.primaryColor.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                // Logo container
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 88, height: 88)
                    
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor.opacity(0.5),
                                    themeManager.secondaryColor.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 88, height: 88)
                    
                    if UIImage(named: "schedulr-logo") != nil {
                        Image("schedulr-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if UIImage(named: "schedulr-logo-any") != nil {
                        Image("schedulr-logo-any")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "calendar")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(themeManager.gradient)
                    }
                }
                .shadow(color: themeManager.primaryColor.opacity(0.2), radius: 20, x: 0, y: 10)
            }
            .scaleEffect(logoScale)
            
            // Title
                VStack(spacing: 8) {
                    Text("Welcome to Schedulr")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                
                Text("Schedule together, effortlessly")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
        }
    }
}

// MARK: - Auth Form Card

private struct AuthFormCard: View {
    @ObservedObject var viewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showPassword: Bool
    @Binding var showForgotPassword: Bool
    @Binding var showResetEmailSent: Bool
    @Binding var showSignUpEmailSent: Bool
    var isEmailFocused: FocusState<Bool>.Binding
    var isPasswordFocused: FocusState<Bool>.Binding
    let isPad: Bool
    
    @State private var animateIn = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Sign in with Apple
                #if os(iOS)
                SignInWithAppleButton(
                    onRequest: { request in
                        viewModel.prepareSignInWithAppleRequest(request)
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                UserDefaults.standard.set(appleIDCredential.user, forKey: "appleUserIdentifier")
                            }
                            Task {
                                await viewModel.signInWithApple(authorization: authorization)
                            }
                        case .failure(let error):
                            viewModel.handleAppleAuthorizationError(error)
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                .disabled(viewModel.isLoadingApple)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
                #endif

            // Divider
            AuthDivider()
                .opacity(animateIn ? 1 : 0)
            
            // Form content
            if showForgotPassword {
                ForgotPasswordView(
                    viewModel: viewModel,
                    showForgotPassword: $showForgotPassword,
                    showResetEmailSent: $showResetEmailSent,
                    isEmailFocused: isEmailFocused,
                    isPad: isPad
                )
            } else if showSignUpEmailSent {
                SignUpSuccessView(
                    viewModel: viewModel,
                    showSignUpEmailSent: $showSignUpEmailSent
                )
            } else {
                // Email/Password form
                VStack(spacing: 16) {
                    // Email field
                    AuthTextField(
                        text: $viewModel.email,
                        placeholder: "Email address",
                        icon: "envelope.fill",
                        iconColor: themeManager.primaryColor,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        isFocused: isEmailFocused
                    )
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                    
                    // Password field
                    AuthSecureField(
                        text: $viewModel.password,
                        placeholder: "Password",
                        icon: "lock.fill",
                        iconColor: themeManager.secondaryColor,
                        showPassword: $showPassword,
                        textContentType: viewModel.authMode == .signUp ? .newPassword : .password,
                        isFocused: isPasswordFocused
                    )
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                    
                    // Forgot password link
                    if viewModel.authMode == .signIn {
                                HStack {
                            Spacer()
                            Button(action: { showForgotPassword = true }) {
                                Text("Forgot Password?")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(themeManager.secondaryColor)
                            }
                        }
                        .opacity(animateIn ? 1 : 0)
                    }
                }
                
                // Sign in/Sign up button
                AuthPrimaryButton(
                    title: viewModel.authMode == .signIn ? "Sign In" : "Create Account",
                    isLoading: viewModel.isLoadingEmail,
                    action: {
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
                    }
                )
                .disabled(viewModel.isLoadingEmail)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
                
                // Toggle auth mode
                AuthModeToggle(authMode: $viewModel.authMode, password: $viewModel.password, errorMessage: $viewModel.errorMessage, showSignUpEmailSent: $showSignUpEmailSent)
                    .opacity(animateIn ? 1 : 0)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
        )
                                    .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Password Reset Card

private struct PasswordResetCard: View {
    @ObservedObject var viewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showNewPassword: Bool
    @Binding var showConfirmPassword: Bool
    var isNewPasswordFocused: FocusState<Bool>.Binding
    var isConfirmPasswordFocused: FocusState<Bool>.Binding
    
    @State private var animateIn = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "06b6d4").opacity(0.2), Color(hex: "8b5cf6").opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "key.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "06b6d4"), Color(hex: "8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("Set New Password")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text("Enter your new password below")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
            
            // Password fields
            VStack(spacing: 16) {
                AuthSecureField(
                    text: $viewModel.newPassword,
                    placeholder: "New Password",
                    icon: "lock.fill",
                    iconColor: Color(hex: "06b6d4"),
                    showPassword: $showNewPassword,
                    textContentType: .newPassword,
                    isFocused: isNewPasswordFocused
                )
                
                AuthSecureField(
                    text: $viewModel.confirmPassword,
                    placeholder: "Confirm Password",
                    icon: "lock.rotation",
                    iconColor: themeManager.secondaryColor,
                    showPassword: $showConfirmPassword,
                    textContentType: .newPassword,
                    isFocused: isConfirmPasswordFocused
                )
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
            
            // Update button
            AuthPrimaryButton(
                title: "Update Password",
                isLoading: viewModel.isLoadingEmail,
                gradient: [Color(hex: "06b6d4"), Color(hex: "8b5cf6")],
                action: {
                            Task {
                                await viewModel.updatePasswordAfterReset()
                            }
                }
            )
                        .disabled(viewModel.isLoadingEmail)
            .opacity(animateIn ? 1 : 0)
                        
            // Cancel button
            Button(action: { viewModel.cancelPasswordReset() }) {
                            Text("Cancel")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                        }
            .opacity(animateIn ? 1 : 0)
                    }
        .padding(24)
                    .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 12)
        )
                                        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Forgot Password View

private struct ForgotPasswordView: View {
    @ObservedObject var viewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showForgotPassword: Bool
    @Binding var showResetEmailSent: Bool
    var isEmailFocused: FocusState<Bool>.Binding
    let isPad: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            if showResetEmailSent {
                // Success state
                SuccessStateView(
                    title: "Check Your Email",
                    message: "We've sent a password reset link to",
                    email: viewModel.email,
                    subtitle: "Click the link in the email to reset your password.",
                    buttonTitle: "Back to Sign In",
                    action: {
                        showForgotPassword = false
                        showResetEmailSent = false
                    }
                )
                                        } else {
                // Email input
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Reset Password")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        
                        Text("Enter your email to receive a reset link")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    AuthTextField(
                        text: $viewModel.email,
                        placeholder: "Email address",
                        icon: "envelope.fill",
                        iconColor: themeManager.primaryColor,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        isFocused: isEmailFocused
                    )
                    
                    AuthPrimaryButton(
                        title: "Send Reset Link",
                        isLoading: viewModel.isLoadingEmail,
                        gradient: [Color(hex: "06b6d4"), Color(hex: "8b5cf6")],
                        action: {
                            Task {
                                await viewModel.resetPassword()
                                if viewModel.noticeMessage != nil {
                                    showResetEmailSent = true
                                }
                            }
                        }
                    )
                    .disabled(viewModel.isLoadingEmail)
                    
                            Button(action: {
                        showForgotPassword = false
                        showResetEmailSent = false
                    }) {
                        Text("Back to Sign In")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Sign Up Success View

private struct SignUpSuccessView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var showSignUpEmailSent: Bool
    
    var body: some View {
        SuccessStateView(
            title: "Check Your Email",
            message: "We've sent a confirmation link to",
            email: viewModel.email,
            subtitle: "Click the link in the email to confirm your account.",
            buttonTitle: "Back to Sign In",
            action: {
                showSignUpEmailSent = false
                viewModel.authMode = .signIn
            }
        )
    }
}

// MARK: - Success State View

private struct SuccessStateView: View {
    let title: String
    let message: String
    let email: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var checkmarkScale: CGFloat = 0
    @State private var animateIn = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Success checkmark
                                ZStack {
                                    Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "10b981"), Color(hex: "059669")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color(hex: "10b981").opacity(0.2), radius: 10, x: 0, y: 5)
                
                                    Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                                        .foregroundStyle(.white)
                                }
            .scaleEffect(checkmarkScale)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                Text(email)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.secondaryColor)
                                        .multilineTextAlignment(.center)
                                    
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 4)
                                }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
            
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.secondaryColor)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(themeManager.secondaryColor.opacity(0.1), in: Capsule())
            }
            .opacity(animateIn ? 1 : 0)
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Auth Divider

private struct AuthDivider: View {
    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.primary.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
            
            Text("or continue with email")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize()
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.primary.opacity(0.15), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

// MARK: - Auth Text Field

private struct AuthTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    let iconColor: Color
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var isFocused: FocusState<Bool>.Binding
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
                                ZStack {
                                    Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            // Text field
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.secondary.opacity(0.6)))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused(isFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isFocused.wrappedValue ?
                    AnyShapeStyle(iconColor.opacity(0.4)) :
                    AnyShapeStyle(Color.primary.opacity(0.08)),
                    lineWidth: 1
                )
        )
        .animation(.spring(response: 0.3), value: isFocused.wrappedValue)
    }
}

// MARK: - Auth Secure Field

private struct AuthSecureField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    let iconColor: Color
    @Binding var showPassword: Bool
    var textContentType: UITextContentType? = nil
    var isFocused: FocusState<Bool>.Binding
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            // Password field
            Group {
                if showPassword {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.secondary.opacity(0.6)))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.secondary.opacity(0.6)))
                }
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .textContentType(textContentType)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .focused(isFocused)
            
            // Toggle visibility
            Button(action: { showPassword.toggle() }) {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isFocused.wrappedValue ?
                    AnyShapeStyle(iconColor.opacity(0.4)) :
                    AnyShapeStyle(Color.primary.opacity(0.08)),
                    lineWidth: 1
                )
        )
        .animation(.spring(response: 0.3), value: isFocused.wrappedValue)
    }
}

// MARK: - Primary Button

private struct AuthPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var gradient: [Color]?
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    init(title: String, isLoading: Bool = false, gradient: [Color]? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.gradient = gradient
        self.action = action
    }
    
    @State private var isPressed = false
    @State private var shimmerPhase: CGFloat = 0
    
    private var buttonGradient: [Color] {
        gradient ?? [themeManager.primaryColor, themeManager.secondaryColor]
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background
                LinearGradient(
                    colors: buttonGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Shimmer
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.25), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: shimmerPhase * geometry.size.width * 1.5 - geometry.size.width * 0.5)
                }
                .opacity(0.5)
                
                // Content
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isLoading ? "Please wait..." : title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                }
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: buttonGradient.first!.opacity(0.2), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3)) { isPressed = false }
                }
        )
        .onAppear {
            withAnimation(
                .linear(duration: 2.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1
            }
        }
    }
}

// MARK: - Auth Mode Toggle

private struct AuthModeToggle: View {
    @Binding var authMode: AuthViewModel.AuthMode
    @Binding var password: String
    @Binding var errorMessage: String?
    @Binding var showSignUpEmailSent: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
                            Button(action: {
            withAnimation(.spring(response: 0.4)) {
                authMode = authMode == .signIn ? .signUp : .signIn
                password = ""
                errorMessage = nil
                                    showSignUpEmailSent = false
                                }
                            }) {
            HStack(spacing: 6) {
                Text(authMode == .signIn ? "Don't have an account?" : "Already have an account?")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Text(authMode == .signIn ? "Sign Up" : "Sign In")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.secondaryColor)
            }
        }
    }
}

// MARK: - Messages View

private struct AuthMessagesView: View {
    @ObservedObject var viewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 8) {
                if let error = viewModel.errorMessage, !error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(error)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                        .foregroundStyle(.red)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .multilineTextAlignment(.center)
                .transition(.move(edge: .top).combined(with: .opacity))
                }
            
                if let notice = viewModel.noticeMessage, !notice.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(notice)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color(hex: "06b6d4"))
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(hex: "06b6d4").opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .multilineTextAlignment(.center)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: viewModel.errorMessage)
        .animation(.spring(response: 0.4), value: viewModel.noticeMessage)
    }
}

// MARK: - Footer View

private struct AuthFooterView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
                HStack(spacing: 4) {
                    Text("By continuing, you agree to our")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            
                    Button("Terms") {
                openURL(urlString: "https://schedulr.co.uk/terms")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(themeManager.secondaryColor)
            
                    Text("&")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            
            Button("Privacy") {
                openURL(urlString: "https://schedulr.co.uk/privacy")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(themeManager.secondaryColor)
        }
    }
    
    private func openURL(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        #if os(iOS)
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = UIColor(themeManager.secondaryColor)
        safariVC.preferredBarTintColor = .systemBackground
        if #available(iOS 11.0, *) {
            safariVC.dismissButtonStyle = .close
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(safariVC, animated: true)
        }
        #endif
    }
}


// MARK: - Preview

#Preview {
    AuthView(viewModel: AuthViewModel())
}
