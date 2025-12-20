import SwiftUI

struct InteractiveHeroView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) var colorScheme
    @State private var touchLocation: CGPoint = .zero
    @State private var isInteracting: Bool = false
    @State private var animateIn = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background base color
                Color(.systemBackground)
                    .opacity(0.1)
                
                // Fluid Mesh Layer
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        
                        // We'll draw 3-4 glowing orbs that move subtly
                        // One orb follows the touch location
                        
                        let orbs: [(Color, CGFloat, CGFloat, CGFloat)] = [
                            (themeManager.primaryColor.opacity(0.4), 0.2, 0.3, 0.6),
                            (themeManager.secondaryColor.opacity(0.35), 0.8, 0.1, 0.5),
                            (Color(hex: "06b6d4").opacity(0.3), 0.5, 0.6, 0.4),
                            (themeManager.primaryColor.opacity(0.25), 0.9, 0.9, 0.3)
                        ]
                        
                        // Blur the whole canvas
                        context.addFilter(.blur(radius: 40))
                        
                        for (index, (color, baseX, baseY, baseRadius)) in orbs.enumerated() {
                            let offset = Double(index) * 2.0
                            let xBase = size.width * (baseX + 0.1 * sin(time * 0.4 + offset))
                            let yBase = size.height * (baseY + 0.08 * cos(time * 0.35 + offset))
                            
                            var x = xBase
                            var y = yBase
                            
                            // Interaction influence
                            if isInteracting {
                                let dist = sqrt(pow(touchLocation.x - xBase, 2) + pow(touchLocation.y - yBase, 2))
                                let influence = max(0, 1 - dist / (size.width * 0.6))
                                x = xBase + (touchLocation.x - xBase) * influence * 0.4
                                y = yBase + (touchLocation.y - yBase) * influence * 0.4
                            }
                            
                            let radius = size.width * baseRadius
                            
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                with: .radialGradient(
                                    Gradient(colors: [color, color.opacity(0)]),
                                    center: CGPoint(x: x, y: y),
                                    startRadius: 0,
                                    endRadius: radius
                                )
                            )
                        }
                    }
                }
                
                // Glassmorphism Overlay elements
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: [.clear, Color(.systemBackground)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touchLocation = value.location
                        isInteracting = true
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                            isInteracting = false
                        }
                    }
            )
            .onAppear {
                touchLocation = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                withAnimation(.easeOut(duration: 1.2)) {
                    animateIn = true
                }
            }
        }
        .frame(height: 280)
        .mask(
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
            }
        )
        .opacity(animateIn ? 1 : 0)
    }
}

#Preview {
    InteractiveHeroView()
        .environmentObject(ThemeManager.shared)
}
