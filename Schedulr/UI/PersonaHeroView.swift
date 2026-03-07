import SwiftUI

struct PersonaHeroView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let upcomingEvents: [CalendarEventWithUser]
    let userName: String?

    private var isPro: Bool {
        SubscriptionManager.shared.isPro
    }

    var body: some View {
        heroCard
            .padding(.horizontal, 20)
            .frame(height: 232)
    }

    private var heroCard: some View {
        Button(action: openChatIfAvailable) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    if isPro {
                        Label("Scheduly", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(themeManager.secondaryColor)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(userName.map { "Hi \($0)" } ?? "Hi there")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(summaryText)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isPro {
                        Text("Tap to chat with Scheduly")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(themeManager.primaryColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SchedulyIllustrationView(style: .hero, showsBadge: isPro)
                    .frame(width: 164, height: 164)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemBackground),
                                Color(red: 0.99, green: 0.96, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isPro)
    }

    private var summaryText: String {
        guard let firstEvent = upcomingEvents.first else {
            return "Your plans are looking calm right now."
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: firstEvent.start_date)

        let calendar = Calendar.current
        let dayLabel: String
        if calendar.isDateInToday(firstEvent.start_date) {
            dayLabel = "today"
        } else if calendar.isDateInTomorrow(firstEvent.start_date) {
            dayLabel = "tomorrow"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            dayLabel = dayFormatter.string(from: firstEvent.start_date)
        }

        if upcomingEvents.count == 1 {
            return "You have 1 upcoming plan. Next is \(firstEvent.title) on \(dayLabel) at \(timeString)."
        }

        return "You have \(upcomingEvents.count) upcoming plans. Next is \(firstEvent.title) on \(dayLabel) at \(timeString)."
    }

    private func openChatIfAvailable() {
        guard isPro else { return }
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #endif
        NotificationCenter.default.post(name: NSNotification.Name("NavigateToAIChat"), object: nil)
    }
}

#Preview {
    PersonaHeroView(upcomingEvents: [], userName: "Daniel")
        .environmentObject(ThemeManager.shared)
        .background(Color(.systemGroupedBackground))
}
