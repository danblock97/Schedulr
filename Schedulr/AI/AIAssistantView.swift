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
    private let userAvatarURL: String?
    
    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif
    
    init(dashboardViewModel: DashboardViewModel, calendarManager: CalendarSyncManager, startWithVoice: Bool = false, userAvatarURL: String? = nil) {
        _viewModel = StateObject(wrappedValue: AIAssistantViewModel(
            dashboardViewModel: dashboardViewModel,
            calendarManager: calendarManager
        ))
        _startWithVoice = State(initialValue: startWithVoice)
        self.userAvatarURL = userAvatarURL
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
                                        MessageBubble(message: message, isPad: isPad, userAvatarURL: userAvatarURL)
                                            .id(message.id)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                    
                                    // Context hint - show only when there's just the welcome message
                                    if viewModel.messages.count == 1, 
                                       let welcomeMessage = viewModel.messages.first,
                                       welcomeMessage.role == .assistant {
                                        VStack(spacing: isPad ? 6 : 4) {
                                            Text("I remember our conversation, so feel free to ask follow-up questions like \"what's next?\" or \"what about tomorrow?\"")
                                                .font(.system(size: isPad ? 13 : 12, weight: .regular, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                            
                                            Text("Note: My context is limited and I may occasionally make mistakes. Please verify important information.")
                                                .font(.system(size: isPad ? 11 : 10, weight: .regular, design: .rounded))
                                                .foregroundColor(.secondary.opacity(0.7))
                                                .multilineTextAlignment(.center)
                                        }
                                        .padding(.horizontal, isPad ? 60 : 40)
                                        .padding(.top, isPad ? 8 : 4)
                                        .frame(maxWidth: isPad ? 600 : .infinity, alignment: .center)
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
                            // Quick prompts - only show when input is empty and no messages yet
                            if viewModel.inputText.isEmpty && viewModel.messages.count <= 1 {
                                QuickPromptsView(isPad: isPad) { prompt in
                                    viewModel.inputText = prompt
                                    Task {
                                        await viewModel.sendMessage()
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                            
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
                                MessageBubble(message: welcomeMessage, isPad: isPad, userAvatarURL: userAvatarURL)
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
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if subscriptionManager.isPro {
                        Button {
                            viewModel.showConversationHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if subscriptionManager.isPro {
                        HStack(spacing: 16) {
                            Button {
                                viewModel.startNewConversation()
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $viewModel.showConversationHistory) {
                ConversationHistorySheet(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let isPad: Bool
    let userAvatarURL: String?
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: isPad ? 14 : 12) {
            // AI avatar for assistant messages (Scheduly) - on left
            if !isUser {
                aiAvatar
            }
            
            if isUser {
                Spacer(minLength: isPad ? 80 : 50)
            }
            
            // Message content
            messageBubble
            
            if !isUser {
                Spacer(minLength: isPad ? 40 : 20)
            }
            
            // User avatar for user messages - on right
            if isUser {
                userAvatar
            }
        }
        .frame(maxWidth: isPad ? 600 : .infinity)
    }
    
    private var aiAvatar: some View {
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
    
    private var userAvatar: some View {
        Group {
            if let avatarURLString = userAvatarURL, let url = URL(string: avatarURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        defaultUserAvatar
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: isPad ? 40 : 36, height: isPad ? 40 : 36)
                            .clipShape(Circle())
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
                    case .failure:
                        defaultUserAvatar
                    @unknown default:
                        defaultUserAvatar
                    }
                }
            } else {
                defaultUserAvatar
            }
        }
        .shadow(color: Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    private var defaultUserAvatar: some View {
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
                .frame(width: isPad ? 40 : 36, height: isPad ? 40 : 36)
            
            Image(systemName: "person.fill")
                .font(.system(size: isPad ? 18 : 16, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    private var messageBubble: some View {
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
            
            Text("Upgrade to Pro to use Scheduly, propose times with natural language, and find the perfect meeting slots for your group.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            VStack(spacing: 10) {
                AIFeatureRow(text: "Natural language queries")
                AIFeatureRow(text: "300 AI requests per month")
                AIFeatureRow(text: "AI-assisted propose times")
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

// MARK: - Quick Prompts View

private struct QuickPromptsView: View {
    let isPad: Bool
    let onPromptSelected: (String) -> Void
    
    private let quickPrompts = [
        "📅 What's on my schedule today?",
        "🔍 Find a free hour this week",
        "⏰ When am I free tomorrow?",
        "📊 Show my busiest day this week",
        "🗓️ What meetings do I have this week?",
        "✅ Find time for a 30-min meeting"
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    QuickPromptChip(prompt: prompt, isPad: isPad) {
                        onPromptSelected(prompt)
                    }
                }
            }
            .padding(.horizontal, isPad ? 60 : 20)
        }
    }
}

// MARK: - Quick Prompt Chip

private struct QuickPromptChip: View {
    let prompt: String
    let isPad: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(prompt)
                .font(.system(size: isPad ? 15 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, isPad ? 16 : 14)
                .padding(.vertical, isPad ? 12 : 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4),
                                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    let calendarManager = CalendarSyncManager()
    let dashboardVM = DashboardViewModel(calendarManager: calendarManager)
    return AIAssistantView(dashboardViewModel: dashboardVM, calendarManager: calendarManager)
}

// MARK: - Conversation History Sheet

private struct ConversationHistorySheet: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingConversations {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No conversations yet")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Start chatting with Scheduly to see your history here")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            ConversationRow(conversation: conversation) {
                                Task {
                                    await viewModel.loadConversation(conversation)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    await viewModel.deleteConversation(viewModel.conversations[index])
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.startNewConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadConversations()
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: DBAIConversation
    let onTap: () -> Void
    
    private var formattedDate: String {
        guard let date = conversation.updated_at ?? conversation.created_at else {
            return ""
        }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

