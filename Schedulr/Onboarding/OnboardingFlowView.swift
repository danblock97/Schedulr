import SwiftUI
import PhotosUI
import EventKit

// MARK: - Main Onboarding Flow View

struct OnboardingFlowView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var previousStep: OnboardingViewModel.Step = .avatar
    @State private var animateBackground = false
    @State private var showContent = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Immersive animated background
                AnimatedMeshBackground()
                    .ignoresSafeArea()
                
                // Floating orbs layer
                FloatingOrbsView()
                    .ignoresSafeArea()
                
                // Main content
                VStack(spacing: 0) {
                    // Custom header with animated progress
                    OnboardingHeaderView(step: viewModel.step)
                        .padding(.horizontal, 24)
                        .padding(.top, max(geometry.safeAreaInsets.top, 20) + 8)
                    
                    Spacer(minLength: 16)
                    
                    // Step content with transitions
                    ZStack {
                        let forward = viewModel.step.rawValue >= previousStep.rawValue

                        if viewModel.step == .avatar {
                            AvatarStepView(viewModel: viewModel)
                                .transition(stepTransition(forward: forward))
                        }
                        if viewModel.step == .name {
                            NameStepView(viewModel: viewModel)
                                .transition(stepTransition(forward: forward))
                        }
                        if viewModel.step == .group {
                            GroupStepView(viewModel: viewModel)
                                .transition(stepTransition(forward: forward))
                        }
                        if viewModel.step == .calendar {
                            CalendarStepView(viewModel: viewModel)
                                .transition(stepTransition(forward: forward))
                        }
                        if viewModel.step == .done {
                            DoneStepView(onFinish: { viewModel.onFinished?() })
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.step)
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 16)
                    
                    // Bottom navigation
                    OnboardingNavigationBar(viewModel: viewModel)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
        }
        .ignoresSafeArea(edges: .top)
        .onChange(of: viewModel.step) { oldValue, _ in
            previousStep = oldValue
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
        }
    }
    
    private func stepTransition(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95)),
            removal: .move(edge: forward ? .leading : .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.95))
        )
    }
}

// MARK: - Animated Mesh Background

private struct AnimatedMeshBackground: View {
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas { context, size in
                // Base gradient
                let baseGradient = Gradient(colors: [
                    colorScheme == .dark ? Color(hex: "0a0a0f") : Color(hex: "fafbff"),
                    colorScheme == .dark ? Color(hex: "0f0a15") : Color(hex: "f5f0ff"),
                    colorScheme == .dark ? Color(hex: "0a0f12") : Color(hex: "f0f8ff")
                ])
                
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        baseGradient,
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                
                // Animated color blobs
                let colors: [(Color, CGFloat, CGFloat)] = [
                    (Color(hex: "ff4d8d").opacity(colorScheme == .dark ? 0.15 : 0.12), 0.3, 0.2),
                    (Color(hex: "8b5cf6").opacity(colorScheme == .dark ? 0.12 : 0.1), 0.7, 0.3),
                    (Color(hex: "06b6d4").opacity(colorScheme == .dark ? 0.1 : 0.08), 0.5, 0.7),
                    (Color(hex: "f59e0b").opacity(colorScheme == .dark ? 0.08 : 0.06), 0.2, 0.8)
                ]
                
                for (index, (color, baseX, baseY)) in colors.enumerated() {
                    let offset = Double(index) * 0.8
                    let x = size.width * (baseX + 0.1 * sin(time * 0.3 + offset))
                    let y = size.height * (baseY + 0.1 * cos(time * 0.25 + offset))
                    let radius = min(size.width, size.height) * (0.4 + 0.1 * sin(time * 0.2 + offset))
                    
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
        .blur(radius: 60)
    }
}

// MARK: - Floating Orbs

private struct FloatingOrbsView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    FloatingOrb(
                        size: CGFloat.random(in: 4...12),
                        startPosition: CGPoint(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        ),
                        delay: Double(index) * 0.3
                    )
                }
            }
        }
    }
}

private struct FloatingOrb: View {
    let size: CGFloat
    let startPosition: CGPoint
    let delay: Double
    
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "ff4d8d").opacity(0.6),
                        Color(hex: "8b5cf6").opacity(0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .blur(radius: size * 0.3)
            .position(startPosition)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1).delay(delay)) {
                    opacity = 0.6
                }
                withAnimation(
                    .easeInOut(duration: Double.random(in: 4...8))
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    offset = CGSize(
                        width: CGFloat.random(in: -50...50),
                        height: CGFloat.random(in: -80...80)
                    )
                }
            }
    }
}

// MARK: - Header View

private struct OnboardingHeaderView: View {
    let step: OnboardingViewModel.Step
    @State private var animateIn = false
    
    private var stepCount: Int { OnboardingViewModel.Step.allCases.count }
    private var currentIndex: Int { step.rawValue }
    private var progress: CGFloat { CGFloat(currentIndex + 1) / CGFloat(stepCount) }
    
    private var stepTitle: String {
        switch step {
        case .avatar: return "Express Yourself"
        case .name: return "Introduce Yourself"
        case .group: return "Find Your People"
        case .calendar: return "Stay in Sync"
        case .done: return "You're All Set"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Top row with logo and step indicator
            HStack {
                // App logo mark
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    
                    if UIImage(named: "schedulr-logo") != nil {
                        Image("schedulr-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "calendar")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .scaleEffect(animateIn ? 1 : 0.5)
                .opacity(animateIn ? 1 : 0)
                
                Spacer()
                
                // Step indicator pills
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentIndex ?
                                  AnyShapeStyle(LinearGradient(
                                    colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                  )) :
                                    AnyShapeStyle(Color.white.opacity(0.15))
                            )
                            .frame(width: index == currentIndex ? 32 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Title with animated underline
            VStack(alignment: .leading, spacing: 8) {
                Text(stepTitle)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .id(stepTitle) // Force animation on change
                                .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stepTitle)
                
                // Animated accent line
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 48, height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "ff4d8d").opacity(0.3))
                        .frame(width: 16, height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "8b5cf6").opacity(0.2))
                        .frame(width: 8, height: 4)
                }
                .offset(x: animateIn ? 0 : -100)
                .opacity(animateIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Navigation Bar

private struct OnboardingNavigationBar: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isPressed = false
    @State private var animateIn = false
    
    private var isNextDisabled: Bool {
        (viewModel.step == .name && viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        || (viewModel.step == .avatar && viewModel.isUploadingAvatar)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Back button
                    if viewModel.step != .avatar {
                        Button {
                            viewModel.back()
                        } label: {
                    HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                                Text("Back")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            // Next/Finish button
                    Button {
                        Task { await viewModel.next() }
                    } label: {
                HStack(spacing: 10) {
                    Text(viewModel.step == .done ? "Let's Go" : "Continue")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    
                    Image(systemName: viewModel.step == .done ? "arrow.right.circle.fill" : "arrow.right")
                        .font(.system(size: viewModel.step == .done ? 20 : 14, weight: .bold))
                        .symbolEffect(.bounce, value: viewModel.step)
                        }
                        .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                        .background(
                    ZStack {
                        // Gradient background
                            LinearGradient(
                            colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                        )
                        
                        // Shimmer effect
                        ShimmerView()
                            .opacity(0.3)
                    }
                    .clipShape(Capsule())
                )
                .shadow(color: Color(hex: "ff4d8d").opacity(0.2), radius: 8, x: 0, y: 4)
                .scaleEffect(isPressed ? 0.95 : 1)
            }
            .disabled(isNextDisabled)
            .opacity(isNextDisabled ? 0.5 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.step)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 30)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Shimmer Effect

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.5),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.5)
            .offset(x: phase * geometry.size.width * 1.5 - geometry.size.width * 0.5)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

// MARK: - Avatar Step

private struct AvatarStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var animateIn = false
    @State private var pulseRing = false

    var body: some View {
        VStack(spacing: 32) {
            // Subtitle
            Text("Add a profile photo so your group knows who's who")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            
            Spacer()
            
            // Avatar display
            ZStack {
                // Animated ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "ff4d8d").opacity(0.3),
                                Color(hex: "8b5cf6").opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(pulseRing ? 1.1 : 1)
                    .opacity(pulseRing ? 0 : 0.8)
                
                // Secondary ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "ff4d8d").opacity(0.2),
                                Color(hex: "8b5cf6").opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulseRing ? 1.2 : 1.1)
                    .opacity(pulseRing ? 0 : 0.5)
                
            if let data = viewModel.pickedImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                        .frame(width: 160, height: 160)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                        colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 4
                            )
                    )
                        .shadow(color: Color(hex: "ff4d8d").opacity(0.15), radius: 12, x: 0, y: 6)
                        .transition(.scale.combined(with: .opacity))
            } else {
                    // Placeholder
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                        Color(hex: "ff4d8d").opacity(0.1),
                                        Color(hex: "8b5cf6").opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                            .frame(width: 160, height: 160)
                        
                            Circle()
                            .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                        Color(hex: "ff4d8d").opacity(0.5),
                                        Color(hex: "8b5cf6").opacity(0.5)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                style: StrokeStyle(lineWidth: 3, dash: [8, 8])
                                )
                            .frame(width: 160, height: 160)
                        
                    Image(systemName: "person.fill")
                            .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                    colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            }
            .scaleEffect(animateIn ? 1 : 0.8)
            .opacity(animateIn ? 1 : 0)
            
            Spacer()
            
            // Upload button
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.pickedImageData == nil ? "Choose Photo" : "Change Photo")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 32)
                .padding(.vertical, 18)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                    LinearGradient(
                        colors: [
                                    Color(hex: "ff4d8d").opacity(0.5),
                                    Color(hex: "8b5cf6").opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                            lineWidth: 1.5
                )
                )
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 20)
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { viewModel.pickedImageData = data }
                        await viewModel.next()
                    }
                }
            }

            // Status messages
            VStack(spacing: 8) {
                if viewModel.isUploadingAvatar {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "ff4d8d"))
                        Text("Uploading...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(height: 50)
            
            // Skip hint
            Text("You can skip this and add a photo later")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .opacity(animateIn ? 1 : 0)
        }
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
            withAnimation(
                .easeInOut(duration: 2)
                .repeatForever(autoreverses: false)
            ) {
                pulseRing = true
            }
        }
    }
}

// MARK: - Name Step

private struct NameStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var nameFieldFocused: Bool
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 32) {
            // Subtitle
            Text("What should we call you?")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            
            Spacer()
            
            // Name input card
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "ff4d8d").opacity(0.15),
                                    Color(hex: "8b5cf6").opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(animateIn ? 1 : 0.5)
                .opacity(animateIn ? 1 : 0)
                
                // Input field
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                        Text("Display Name")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("•")
                            .foregroundStyle(Color(hex: "ff4d8d"))
                        Text("Required")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "ff4d8d"))
                    }
                    
                    TextField("", text: $viewModel.displayName, prompt: Text("Alex Morgan").foregroundStyle(Color.secondary.opacity(0.6)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($nameFieldFocused)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    nameFieldFocused ?
                                    AnyShapeStyle(Color(hex: "8b5cf6").opacity(0.4)) :
                                    AnyShapeStyle(Color.primary.opacity(0.08)),
                                    lineWidth: 1
                                )
                        )
                        .animation(.spring(response: 0.3), value: nameFieldFocused)
                }
                .padding(.horizontal, 4)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 30)
                
                // Validation hint
            if viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                        Text("This is how you'll appear to your group")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                
                // Status
                if viewModel.isSavingName {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "ff4d8d"))
                        Text("Saving...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
            
            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                nameFieldFocused = true
            }
        }
    }
}

// MARK: - Group Step

private struct GroupStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var groupNameFieldFocused: Bool
    @FocusState private var joinInputFieldFocused: Bool
    @State private var animateIn = false
    @State private var selectedOption: GroupOption = .create
    
    enum GroupOption {
        case create, join
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Subtitle
                Text("Scheduling is better together")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                
                // Option selector
                HStack(spacing: 12) {
                    GroupOptionButton(
                        title: "Create",
                        icon: "plus.circle.fill",
                        isSelected: selectedOption == .create
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedOption = .create
                            viewModel.groupMode = .create
                        }
                    }
                    
                    GroupOptionButton(
                        title: "Join",
                        icon: "person.2.fill",
                        isSelected: selectedOption == .join
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedOption = .join
                            viewModel.groupMode = .join
                        }
                    }
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
                
                // Content based on selection
                if selectedOption == .create {
                    // Create group card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "ff4d8d").opacity(0.2), Color(hex: "8b5cf6").opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start a New Group")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Text("Invite friends after setup")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        TextField("", text: $viewModel.groupName, prompt: Text("Weekend Warriors").foregroundStyle(Color.secondary.opacity(0.6)))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    .focused($groupNameFieldFocused)
                    .onChange(of: viewModel.groupName) { _, val in
                        if !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.groupMode = .create
                        }
                    }
            }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    // Join group card
                    VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "06b6d4").opacity(0.2), Color(hex: "8b5cf6").opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "link")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "06b6d4"), Color(hex: "8b5cf6")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Join Existing Group")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                Text("Paste an invite link or code")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                        }
                        
                        TextField("", text: $viewModel.joinInput, prompt: Text("https://... or invite code").foregroundStyle(Color.secondary.opacity(0.6)))
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    .focused($joinInputFieldFocused)
                    .onChange(of: viewModel.joinInput) { _, val in
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        viewModel.groupMode = trimmed.isEmpty ? .create : .join
                    }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
                
                // Skip option
            Button(action: {
                viewModel.groupMode = .skip
                Task { await viewModel.next() }
            }) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                Text("Set up later")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                }
                .opacity(animateIn ? 1 : 0)
                
                // Status
            if viewModel.isHandlingGroup {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "ff4d8d"))
                        Text(viewModel.groupMode == .create ? "Creating..." : "Joining...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

private struct GroupOptionButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.clear
                    }
                }
            )
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ?
                        AnyShapeStyle(Color.clear) :
                        AnyShapeStyle(Color.secondary.opacity(0.3)),
                        lineWidth: 1
                    )
            )
        }
    }
}

// MARK: - Calendar Step

private struct CalendarStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var calendarSync: CalendarSyncManager
    @State private var animateIn = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Subtitle
                Text("Let your group see when you're available")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                
                // Calendar illustration
                ZStack {
                    // Background glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: "06b6d4").opacity(0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    // Calendar icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                        
                        VStack(spacing: 4) {
                            // Month bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "ff4d8d"), Color(hex: "8b5cf6")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 70, height: 16)
                            
                            // Day grid
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(8), spacing: 4), count: 7), spacing: 4) {
                                ForEach(0..<21, id: \.self) { index in
                                    Circle()
                                        .fill(index == 10 ? Color(hex: "ff4d8d") : Color.secondary.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .frame(width: 70)
                        }
                    }
                    .shadow(color: Color(hex: "06b6d4").opacity(0.15), radius: 12, x: 0, y: 6)
                }
                .scaleEffect(animateIn ? 1 : 0.8)
                .opacity(animateIn ? 1 : 0)
                
                // Sync toggle card
                VStack(spacing: 20) {
            Toggle(isOn: Binding(
                get: { viewModel.wantsCalendarSync },
                set: { newValue in
                    viewModel.wantsCalendarSync = newValue
                    if !newValue {
                        calendarSync.disableSync()
                    }
                }
            )) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "06b6d4").opacity(0.2), Color(hex: "8b5cf6").opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "06b6d4"), Color(hex: "8b5cf6")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync My Calendars")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Text("Show availability to group")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "ff4d8d")))
                    
                    // Authorization status
            Group {
                switch calendarSync.authorizationStatus {
                case .notDetermined:
                            StatusBadge(text: "We'll ask for permission", icon: "hand.raised", color: .secondary)
                case .authorized:
                    if calendarSync.syncEnabled && !calendarSync.upcomingEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                                    Text("UPCOMING EVENTS")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                        .tracking(1)
                                    
                            ForEach(Array(calendarSync.upcomingEvents.prefix(3))) { event in
                                        CalendarEventRow(event: event)
                            }
                                    
                            if calendarSync.upcomingEvents.count > 3 {
                                        Text("+\(calendarSync.upcomingEvents.count - 3) more events")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                                .padding(16)
                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if viewModel.wantsCalendarSync {
                                StatusBadge(text: "Events will sync when enabled", icon: "checkmark.circle", color: Color(hex: "10b981"))
                    }
                case .denied, .restricted:
                            StatusBadge(text: "Enable in Settings → Privacy → Calendars", icon: "exclamationmark.triangle", color: .orange)
                @unknown default:
                    EmptyView()
                }
            }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 30)
                
                // Loading states
            if calendarSync.isRequestingAccess {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "ff4d8d"))
                        Text("Requesting access...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
            } else if calendarSync.isRefreshing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "ff4d8d"))
                        Text("Syncing events...")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
            }

            if let error = viewModel.errorMessage, viewModel.step == .calendar {
                Text(error)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct CalendarEventRow: View {
    let event: CalendarSyncManager.SyncedEvent

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(
                    red: event.calendarColor.red,
                    green: event.calendarColor.green,
                    blue: event.calendarColor.blue
                ))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Busy" : event.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                
                Text(formattedDate)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            
            Spacer()
        }
    }

    private var formattedDate: String {
        if event.isAllDay {
            return "All day"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate)
    }
}

// MARK: - Done Step

private struct DoneStepView: View {
    var onFinish: () -> Void
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var animateIn = false
    @State private var showConfetti = false
    @State private var celebrationScale: CGFloat = 0.5
    
    var body: some View {
        ScrollView(showsIndicators: false) {
        VStack(spacing: 24) {
                // Celebration animation
                ZStack {
                    // Confetti particles
                    if showConfetti {
                        ConfettiView()
                    }
                    
                    // Success checkmark
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                        colors: [
                                        Color(hex: "10b981").opacity(0.3),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)
                        
                        // Main circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "10b981"), Color(hex: "059669")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)
                            .shadow(color: Color(hex: "10b981").opacity(0.2), radius: 12, x: 0, y: 6)
                        
                        // Checkmark
                        Image(systemName: "checkmark")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(celebrationScale)
            }
            .padding(.top, 8)
                
                // Title and message
                VStack(spacing: 10) {
                    Text("You're All Set!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Welcome to Schedulr. Your profile is ready and you can change these settings anytime.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
                
                // Pro upgrade prompt (for free users)
                if !subscriptionManager.isPro {
                    ProUpgradeCard(onUpgrade: { showPaywall = true })
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 30)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            // Staggered animations
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                celebrationScale = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
            
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.4)) {
                animateIn = true
            }
        }
    }
}

// MARK: - Confetti View

private struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    ConfettiPiece(particle: particle, containerSize: geometry.size)
                }
            }
        }
        .onAppear {
            particles = (0..<50).map { _ in ConfettiParticle() }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let startX: CGFloat
    let rotation: Double
    let scale: CGFloat
    let speed: Double
    let delay: Double
    
    init() {
        let colors: [Color] = [
            Color(hex: "ff4d8d"),
            Color(hex: "8b5cf6"),
            Color(hex: "06b6d4"),
            Color(hex: "10b981"),
            Color(hex: "f59e0b"),
            Color(hex: "ef4444")
        ]
        self.color = colors.randomElement()!
        self.startX = CGFloat.random(in: 0...1)
        self.rotation = Double.random(in: 0...360)
        self.scale = CGFloat.random(in: 0.5...1)
        self.speed = Double.random(in: 2...4)
        self.delay = Double.random(in: 0...0.5)
    }
}

private struct ConfettiPiece: View {
    let particle: ConfettiParticle
    let containerSize: CGSize
    
    @State private var offsetY: CGFloat = -50
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(particle.color)
            .frame(width: 8 * particle.scale, height: 12 * particle.scale)
            .rotationEffect(.degrees(rotation))
            .offset(
                x: containerSize.width * particle.startX - containerSize.width / 2,
                y: offsetY
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeIn(duration: particle.speed)
                    .delay(particle.delay)
                ) {
                    offsetY = containerSize.height + 50
                    rotation = particle.rotation + 720
                }
                
                withAnimation(
                    .easeIn(duration: particle.speed * 0.5)
                    .delay(particle.delay + particle.speed * 0.5)
                ) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Pro Upgrade Card

private struct ProUpgradeCard: View {
    let onUpgrade: () -> Void
    @State private var shimmer = false
    
    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "f59e0b").opacity(0.2), Color(hex: "ff4d8d").opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "f59e0b"), Color(hex: "ff4d8d")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unlock Pro")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Get the full experience")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Features
            VStack(spacing: 6) {
                ProFeatureItem(text: "AI scheduling assistant", icon: "brain")
                ProFeatureItem(text: "5 groups instead of 1", icon: "person.3")
                ProFeatureItem(text: "10 members per group", icon: "person.crop.circle.badge.plus")
            }
            
            // Upgrade button
            Button(action: onUpgrade) {
                HStack(spacing: 8) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                        .background(
                    ZStack {
                            LinearGradient(
                            colors: [Color(hex: "f59e0b"), Color(hex: "ff4d8d")],
                                startPoint: .leading,
                                endPoint: .trailing
                        )
                        
                        // Shimmer
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.3), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 0.5)
                            .offset(x: shimmer ? geometry.size.width : -geometry.size.width * 0.5)
                        }
                    }
                    .clipShape(Capsule())
                )
                .shadow(color: Color(hex: "ff4d8d").opacity(0.15), radius: 8, x: 0, y: 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hex: "f59e0b").opacity(0.3),
                            Color(hex: "ff4d8d").opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(
                .linear(duration: 2)
                .repeatForever(autoreverses: false)
            ) {
                shimmer = true
            }
        }
    }
}

private struct ProFeatureItem: View {
    let text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "10b981"))
            
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    let manager = CalendarSyncManager()
    return OnboardingFlowView(viewModel: OnboardingViewModel(calendarManager: manager, onFinished: {}))
        .environmentObject(manager)
}
