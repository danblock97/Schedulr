//
//  AIAssistantView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct AIAssistantView: View {
    @StateObject private var viewModel: AIAssistantViewModel
    @StateObject private var speechManager = SpeechRecognitionManager()
    @EnvironmentObject var themeManager: ThemeManager
    @FocusState private var isInputFocused: Bool
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var hasShownProPrompt = false
    @State private var startWithVoice: Bool = false
    
    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif
    
    init(dashboardViewModel: DashboardViewModel, calendarManager: CalendarSyncManager, startWithVoice: Bool = false) {
        _viewModel = StateObject(wrappedValue: AIAssistantViewModel(
            dashboardViewModel: dashboardViewModel,
            calendarManager: calendarManager
        ))
        _startWithVoice = State(initialValue: startWithVoice)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Dismiss keyboard when tapping background
                        isInputFocused = false
                    }
                
                // Bubbly background decoration
                BubblyAIBackground(themeManager: themeManager)
                    .ignoresSafeArea()
                
                if subscriptionManager.isPro {
                    // Pro users: Full chat interface
                    VStack(spacing: 0) {
                        // Messages list
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: isPad ? 16 : 20) {
                                    ForEach(viewModel.messages) { message in
                                        MessageBubble(message: message, isPad: isPad)
                                            .id(message.id)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                    
                                    // Loading indicator
                                    if viewModel.isLoading {
                                        LoadingBubble(isPad: isPad)
                                            .id("loading")
                                    }
                                }
                                .frame(maxWidth: isPad ? 600 : .infinity, alignment: .leading)
                                .padding(.horizontal, isPad ? 60 : 20)
                                .padding(.vertical, isPad ? 24 : 12)
                                .padding(.bottom, 140) // Space for input area + tab bar
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        // Dismiss keyboard when tapping on scroll view
                                        isInputFocused = false
                                    }
                            )
                            .onAppear {
                                // Scroll to bottom on initial load
                                if let lastMessage = viewModel.messages.last {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            .onChange(of: viewModel.messages.count) { _, _ in
                                if let lastMessage = viewModel.messages.last {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: viewModel.isLoading) { _, isLoading in
                                if isLoading {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo("loading", anchor: .bottom)
                                    }
                                }
                            }
                        }
                        
                        // Input area
                        VStack(spacing: 0) {
                            Divider()
                                .opacity(0.3)
                            
                            HStack(spacing: 12) {
                                // Microphone button
                                VoiceInputButton(
                                    isRecording: speechManager.isRecording,
                                    isPad: isPad
                                ) {
                                    Task {
                                        await speechManager.toggleRecording()
                                    }
                                }
                                
                                TextField("Ask me anything...", text: $viewModel.inputText, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: isPad ? 17 : 16, weight: .medium, design: .rounded))
                                    .padding(.horizontal, isPad ? 20 : 18)
                                    .padding(.vertical, isPad ? 16 : 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                                    .stroke(
                                                        speechManager.isRecording
                                                        ? LinearGradient(
                                                            colors: [
                                                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                                                Color(red: 0.58, green: 0.41, blue: 0.87)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                        : LinearGradient(
                                                            colors: [
                                                                Color.white.opacity(0.3),
                                                                Color.white.opacity(0.1)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: speechManager.isRecording ? 2 : 1
                                                    )
                                            )
                                    )
                                    .focused($isInputFocused)
                                    .onSubmit {
                                        Task {
                                            await viewModel.sendMessage()
                                        }
                                    }
                                
                                Button {
                                    Task {
                                        await viewModel.sendMessage()
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? AnyShapeStyle(Color.secondary.opacity(0.2))
                                                : AnyShapeStyle(LinearGradient(
                                                    colors: [
                                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ))
                                            )
                                            .frame(width: isPad ? 48 : 44, height: isPad ? 48 : 44)
                                            .shadow(
                                                color: viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? Color.clear
                                                : Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4),
                                                radius: 12,
                                                x: 0,
                                                y: 6
                                            )
                                        
                                        Image(systemName: "arrow.up")
                                            .font(.system(size: isPad ? 19 : 18, weight: .bold))
                                            .foregroundStyle(
                                                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                ? Color.secondary.opacity(0.6)
                                                : Color.white
                                            )
                                    }
                                }
                                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                                .buttonStyle(ScaleButtonStyle())
                            }
                            .frame(maxWidth: isPad ? 600 : .infinity)
                            .padding(.horizontal, isPad ? 60 : 20)
                            .padding(.vertical, isPad ? 18 : 16)
                            .padding(.bottom, 90) // Space for floating tab bar
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                            .background(Color(.systemGroupedBackground))
                        }
                    }
                    .onChange(of: speechManager.transcribedText) { _, newText in
                        // Update input text with transcription
                        if !newText.isEmpty {
                            viewModel.inputText = newText
                        }
                    }
                    .onAppear {
                        // Start voice input if requested (from deep link)
                        if startWithVoice {
                            startWithVoice = false
                            Task {
                                await speechManager.startRecording()
                            }
                        }
                    }
                } else {
                    // Free users: Show welcome message and inline upgrade prompt
                    ScrollView {
                        VStack(spacing: 24) {
                            // Welcome message
                            if let welcomeMessage = viewModel.messages.first(where: { $0.role == .assistant }) {
                                MessageBubble(message: welcomeMessage, isPad: isPad)
                                    .padding(.horizontal, isPad ? 40 : 20)
                                    .padding(.top, 12)
                            }
                            
                            // Inline upgrade prompt
                            AIInlineUpgradePrompt(onUpgrade: { showPaywall = true })
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            
                            Spacer()
                                .frame(height: 100)
                        }
                        .contentShape(Rectangle())
                    }
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                // Dismiss keyboard when tapping on scroll view
                                isInputFocused = false
                            }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Scheduly")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if subscriptionManager.isPro {
                        Button {
                            viewModel.clearMessages()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let isPad: Bool
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: isPad ? 14 : 12) {
            if isUser {
                Spacer(minLength: isPad ? 80 : 50)
            }
            
            // AI avatar for assistant messages (Scheduly)
            if !isUser {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.15),
                                    Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isPad ? 40 : 36, height: isPad ? 40 : 36)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.29, blue: 0.55),
                                            Color(red: 0.58, green: 0.41, blue: 0.87)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image("schedulr-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: isPad ? 26 : 24, height: isPad ? 26 : 24)
                        .clipShape(Circle())
                }
                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .font(.system(size: isPad ? 17 : 16, weight: .regular, design: .rounded))
                    .foregroundColor(isUser ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, isPad ? 20 : 18)
                    .padding(.vertical, isPad ? 16 : 14)
                    .background(
                        Group {
                            if isUser {
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color(.systemBackground)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(
                            color: isUser
                            ? Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.25)
                            : Color.black.opacity(0.08),
                            radius: isUser ? 12 : 8,
                            x: 0,
                            y: isUser ? 6 : 4
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isUser
                                ? AnyShapeStyle(Color.white.opacity(0.2))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )),
                                lineWidth: 1
                            )
                    )
            }
            
            if !isUser {
                Spacer(minLength: isPad ? 40 : 20)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: isPad ? 600 : .infinity)
    }
}

// MARK: - Loading Bubble

private struct LoadingBubble: View {
    @State private var animate = false
    let isPad: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: isPad ? 14 : 12) {
            // AI avatar (Scheduly)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.15),
                                Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isPad ? 40 : 36, height: isPad ? 40 : 36)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image("schedulr-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isPad ? 26 : 24, height: isPad ? 26 : 24)
                    .clipShape(Circle())
            }
            .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 8, x: 0, y: 4)
            
            // Loading dots
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
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
                        .frame(width: isPad ? 11 : 10, height: isPad ? 11 : 10)
                        .scaleEffect(animate ? 1.0 : 0.6)
                        .opacity(animate ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, isPad ? 20 : 18)
            .padding(.vertical, isPad ? 16 : 14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
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
            
            Spacer(minLength: isPad ? 40 : 50)
        }
        .frame(maxWidth: isPad ? 600 : .infinity, alignment: .leading)
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Bubbly Background

private struct BubblyAIBackground: View {
    @ObservedObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            // Large primary bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            themeManager.primaryColor.opacity(0.08),
                            themeManager.primaryColor.opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -150, y: -300)
                .blur(radius: 40)
            
            // Secondary bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            themeManager.secondaryColor.opacity(0.08),
                            themeManager.secondaryColor.opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 60,
                        endRadius: 180
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: 160, y: 200)
                .blur(radius: 35)
            
            // Small decorative sparkles
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            themeManager.primaryColor.opacity(0.3),
                            themeManager.secondaryColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: 100, y: -200)
                .blur(radius: 20)
        }
    }
}

// MARK: - AI Pro Paywall Modal

private struct AIProPaywallModal: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 24) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding(.horizontal, 20)
                
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("AI Scheduling Assistant")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Meet Scheduly, your AI assistant for finding the perfect meeting times with your group.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        AIFeatureRow(text: "Natural language queries")
                        AIFeatureRow(text: "300 AI requests per month")
                        AIFeatureRow(text: "Find free time slots instantly")
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: onUpgrade) {
                        Text("Upgrade to Pro")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.5), radius: 16, x: 0, y: 8)
                    }
                    .padding(.horizontal, 20)
                    
                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
                )
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct AIFeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.59, green: 0.85, blue: 0.34))
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

// MARK: - AI Inline Upgrade Prompt

private struct AIInlineUpgradePrompt: View {
    let onUpgrade: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55),
                            Color(red: 0.58, green: 0.41, blue: 0.87)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
            
            Text("Unlock AI Scheduling Assistant")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            Text("Upgrade to Pro to use Scheduly and find the perfect meeting times for your group.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            VStack(spacing: 10) {
                AIFeatureRow(text: "Natural language queries")
                AIFeatureRow(text: "300 AI requests per month")
                AIFeatureRow(text: "Find free time slots instantly")
            }
            .padding(.vertical, 8)
            
            Button(action: onUpgrade) {
                Text("Upgrade to Pro")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Voice Input Button

private struct VoiceInputButton: View {
    let isRecording: Bool
    let isPad: Bool
    let action: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Pulsing background when recording
                if isRecording {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                                    Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isPad ? 56 : 52, height: isPad ? 56 : 52)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                }
                
                Circle()
                    .fill(
                        isRecording
                        ? AnyShapeStyle(LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.29, blue: 0.55),
                                Color(red: 0.58, green: 0.41, blue: 0.87)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.secondary.opacity(0.15))
                    )
                    .frame(width: isPad ? 48 : 44, height: isPad ? 48 : 44)
                    .shadow(
                        color: isRecording
                        ? Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4)
                        : Color.clear,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: isPad ? 19 : 18, weight: .semibold))
                    .foregroundStyle(
                        isRecording
                        ? Color.white
                        : Color.secondary
                    )
                    .symbolEffect(.variableColor.iterative.reversing, isActive: isRecording)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            if isRecording {
                pulseScale = 1.15
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                pulseScale = 1.15
            } else {
                pulseScale = 1.0
            }
        }
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    let dashboardVM = DashboardViewModel(calendarManager: calendarManager)
    return AIAssistantView(dashboardViewModel: dashboardVM, calendarManager: calendarManager)
}

