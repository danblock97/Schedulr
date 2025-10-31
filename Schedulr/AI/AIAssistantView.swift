//
//  AIAssistantView.swift
//  Schedulr
//
//  Created by Daniel Block on 29/10/2025.
//

import SwiftUI

struct AIAssistantView: View {
    @StateObject private var viewModel: AIAssistantViewModel
    @FocusState private var isInputFocused: Bool
    
    init(dashboardViewModel: DashboardViewModel, calendarManager: CalendarSyncManager) {
        _viewModel = StateObject(wrappedValue: AIAssistantViewModel(
            dashboardViewModel: dashboardViewModel,
            calendarManager: calendarManager
        ))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                // Bubbly background decoration
                BubblyAIBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Messages list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                                
                                // Loading indicator
                                if viewModel.isLoading {
                                    LoadingBubble()
                                        .id("loading")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .padding(.bottom, 140) // Space for input area + tab bar
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
                            TextField("Ask me anything...", text: $viewModel.inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
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
                                        .frame(width: 44, height: 44)
                                        .shadow(
                                            color: viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? Color.clear
                                            : Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.4),
                                            radius: 12,
                                            x: 0,
                                            y: 6
                                        )
                                    
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 18, weight: .bold))
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 90) // Space for floating tab bar
                        .background(.ultraThinMaterial)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .navigationTitle("Scheduly")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 50)
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
                        .frame(width: 36, height: 36)
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
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
                .shadow(color: Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(isUser ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
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
            
            if isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

// MARK: - Loading Bubble

private struct LoadingBubble: View {
    @State private var animate = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                    .frame(width: 36, height: 36)
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
                    .frame(width: 24, height: 24)
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
                        .frame(width: 10, height: 10)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
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
            
            Spacer(minLength: 50)
        }
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Bubbly Background

private struct BubblyAIBackground: View {
    var body: some View {
        ZStack {
            // Large pink bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.08),
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -150, y: -300)
                .blur(radius: 40)
            
            // Purple bubble
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.08),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.02)
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
                            Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                            Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
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

// MARK: - Preview

#Preview {
    let calendarManager = CalendarSyncManager()
    let dashboardVM = DashboardViewModel(calendarManager: calendarManager)
    return AIAssistantView(dashboardViewModel: dashboardVM, calendarManager: calendarManager)
}

