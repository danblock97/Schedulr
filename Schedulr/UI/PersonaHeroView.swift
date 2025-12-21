import SwiftUI

struct PersonaHeroView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let upcomingEvents: [CalendarEventWithUser]
    let userName: String?
    
    @StateObject private var speaker = PersonaSpeaker()
    @State private var talkAnim: CGFloat = 0 // Keep as 0 for static mouth width
    @State private var blink: Bool = false
    @State private var animateIn = false
    
    // Pro state check
    private var isPro: Bool {
        SubscriptionManager.shared.isPro
    }
    
    // ... init for preview/usage flexibility if needed, but memberwise is fine
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Soft Glow
                Circle()
                    .fill(isPro ? themeManager.secondaryColor.opacity(0.18) : themeManager.primaryColor.opacity(0.12))
                    .frame(width: 400, height: 400) // Scaled up
                    .blur(radius: 60)
                    .offset(y: -40)
                
                VStack(spacing: 0) {
                    
                    // The Character Container
                    ZStack(alignment: .topTrailing) {
                        
                        
                        // Character Body Group
                        ZStack {
                            // 1. Pro Rotating Ring
                            if isPro {
                                Circle()
                                    .stroke(
                                        LinearGradient(colors: [.clear, themeManager.secondaryColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom),
                                        lineWidth: 4
                                    )
                                    .frame(width: 220, height: 220) // Scaled up
                                    .rotationEffect(.degrees(animateIn ? 360 : 0))
                                    .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: animateIn)
                                    .blur(radius: 2)
                            }
                            
                            // 2. Shadow
                            Circle()
                                .fill(themeManager.primaryColor.opacity(0.4))
                                .frame(width: 180, height: 180)
                                .blur(radius: 25)
                                .offset(y: 15)
                            
                            // 3. Main Body
                            ZStack {
                                MainBodyShape()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                themeManager.primaryColor,
                                                isPro ? themeManager.secondaryColor : themeManager.secondaryColor.opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 200, height: 200) // Scaled up significantly
                                    .overlay(
                                        MainBodyShape()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                            .padding(2)
                                    )
                                
                                // Pro Badge
                                if isPro {
                                    HStack(spacing: 3) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10))
                                        Text("AI")
                                            .font(.system(size: 11, weight: .black, design: .rounded))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(themeManager.secondaryColor, in: Capsule())
                                    .shadow(color: themeManager.secondaryColor.opacity(0.4), radius: 4, x: 0, y: 2)
                                    .offset(x: 70, y: -70)
                                }
                            }
                            
                            // Face Features
                            VStack(spacing: 12) { // Increased spacing
                                ZStack {
                                    // Blush
                                    HStack(spacing: 90) { // Wider blush
                                        Circle().fill(Color.red.opacity(0.2)).frame(width: 32, height: 20).blur(radius: 5)
                                        Circle().fill(Color.red.opacity(0.2)).frame(width: 32, height: 20).blur(radius: 5)
                                    }
                                    .offset(y: 20)
                                    .opacity(speaker.isSpeaking ? 1 : 0.4)
                                    
                                    // Eyes
                                    HStack(spacing: 45) { // Wider eyes
                                        PersonaEye(geoSize: geo.size, blink: blink)
                                        PersonaEye(geoSize: geo.size, blink: blink)
                                    }
                                }
                                
                                PersonaMouth(isSpeaking: speaker.isSpeaking)
                                    .offset(y: 8)
                            }
                        }
                        .onTapGesture {
                            if isPro {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                NotificationCenter.default.post(name: NSNotification.Name("NavigateToAIChat"), object: nil)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if speaker.isSpeaking {
                                TextBubbleView(text: speaker.currentPhrase)
                                    .transition(.scale(scale: 0.2, anchor: .bottomLeading).combined(with: .opacity))
                                    .offset(x: -20, y: -50) // Slightly left of anchor, overlapping character
                                    .zIndex(20)
                            }
                        }
                    }
                    
                    Spacer().frame(height: 30)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onAppear {
                speaker.updateData(events: upcomingEvents, isPro: isPro, userName: userName)
                animateIn = true // Instant appearance
                startBlinkCycle()
            }
            .onChange(of: upcomingEvents) { _, newValue in
                speaker.updateData(events: newValue, isPro: isPro, userName: userName)
            }
            .onChange(of: userName) { _, newName in
                speaker.updateData(events: upcomingEvents, isPro: isPro, userName: newName)
            }
        }
        .frame(height: 320) // Reduced height to close gap
        .opacity(animateIn ? 1 : 0)
    }
    
    // Blink Logic (Static eyes, just blink animation)
    private func startBlinkCycle() {
        let randomDelay = Double.random(in: 2...6)
        DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
            withAnimation(.easeInOut(duration: 0.1)) {
                blink = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    blink = false
                }
                startBlinkCycle()
            }
        }
    }
}

// MARK: - Subviews

struct PersonaEye: View {
    let geoSize: CGSize
    let blink: Bool
    
    var body: some View {
        ZStack {
            // Sclera - Larger
            Circle()
                .fill(.white)
                .frame(width: 34, height: 34)
            
            // Pupil with a little glint
            ZStack {
                Circle()
                    .fill(Color(white: 0.15))
                
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 5, height: 5)
                    .offset(x: -4, y: -4)
            }
            .frame(width: 18, height: 18)
        }
        .scaleEffect(y: blink ? 0.05 : 1.0)
    }
}

struct PersonaMouth: View {
    let isSpeaking: Bool
    @State private var talkAnim: CGFloat = 0
    
    var body: some View {
        ZStack {
            if isSpeaking {
                // Animated "Speaking" Mouth - Smoother, more natural shape
                GeometryReader { g in
                    Path { path in
                        let w = g.size.width
                        let h = g.size.height
                        
                        // Draw a smoother "D" / Open Smile shape
                        path.move(to: CGPoint(x: 2, y: 2))
                        
                        // Top curve (slightly curved down for natural look)
                        path.addQuadCurve(
                            to: CGPoint(x: w-2, y: 2),
                            control: CGPoint(x: w/2, y: 4)
                        )
                        
                        // Bottom curve (deep open mouth)
                        path.addCurve(
                            to: CGPoint(x: 2, y: 2),
                            control1: CGPoint(x: w, y: h),
                            control2: CGPoint(x: 0, y: h)
                        )
                        
                        path.closeSubpath()
                    }
                    .fill(Color(white: 0.15))
                }
                .frame(width: 26, height: 18) // Static height (18)
                .scaleEffect(y: 1.0 + (talkAnim / 20.0)) // Scale-based wobble
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                        talkAnim = 8
                    }
                }
            } else {
                // Contented Small Smile
                Path { path in
                    path.addArc(center: CGPoint(x: 12, y: 0), radius: 12, startAngle: .degrees(30), endAngle: .degrees(150), clockwise: false)
                }
                .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 24, height: 12)
            }
        }
    }
}

struct TextBubbleView: View {
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    @State private var displayedText: String = ""
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main Bubble
            Text(displayedText)
                .font(.system(size: 13, weight: .bold, design: .rounded)) // Smaller font (13pt)
                .multilineTextAlignment(.center)
                .lineLimit(nil) // Allow unlimited lines for summaries
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
                .frame(minWidth: 160, maxWidth: 250) // Variable width: min 160, grows to 250
                .fixedSize(horizontal: true, vertical: true) // Respect content size
            
            // Comic dots
            VStack(spacing: 3) {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 8, height: 8)
                    .offset(x: -4, y: 4)
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 5, height: 5)
                    .offset(x: -10, y: 10)
            }
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
        }
        .onAppear {
            displayedText = ""
            typeText()
        }
        .onChange(of: text) { _, _ in
            displayedText = ""
            typeText()
        }
    }
    
    private func typeText() {
        // Typing effect
        // Faster typing for longer text so it doesn't take forever
        let speed = text.count > 50 ? 0.015 : 0.03
        
        // Reset
        displayedText = ""
        let chars = Array(text)
        for (index, char) in chars.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * speed) {
                displayedText.append(char)
            }
        }
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct MainBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // A more organic, soft-cornered rounded "square-blob"
        path.move(to: CGPoint(x: w * 0.2, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: 0), control: CGPoint(x: w/2, y: -h * 0.05))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w * 1.05, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 1.1, y: h/2))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h), control: CGPoint(x: w * 1.05, y: h))
        path.addQuadCurve(to: CGPoint(x: w * 0.2, y: h), control: CGPoint(x: w/2, y: h * 1.05))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.8), control: CGPoint(x: -w * 0.05, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h * 0.2), control: CGPoint(x: -w * 0.1, y: h/2))
        path.addQuadCurve(to: CGPoint(x: w * 0.2, y: 0), control: CGPoint(x: -w * 0.05, y: 0))
        
        return path
    }
}

#Preview {
    PersonaHeroView(upcomingEvents: [], userName: "Daniel")
        .environmentObject(ThemeManager.shared)
        .background(Color(.systemGroupedBackground))
}
