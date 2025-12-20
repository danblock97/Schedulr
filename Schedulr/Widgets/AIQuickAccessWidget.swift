//
//  AIQuickAccessWidget.swift
//  Schedulr
//
//  Created by Daniel Block on 28/11/2025.
//

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct AIQuickAccessEntry: TimelineEntry {
    let date: Date
    let theme: AIWidgetTheme
}

struct AIWidgetTheme {
    let primary: Color
    let secondary: Color
    
    static let defaultTheme = AIWidgetTheme(
        primary: Color(red: 0.98, green: 0.29, blue: 0.55),
        secondary: Color(red: 0.58, green: 0.41, blue: 0.87)
    )
}

// MARK: - Timeline Provider

struct AIQuickAccessProvider: TimelineProvider {
    let appGroupId = "group.uk.co.schedulr.Schedulr"
    let themeKey = "widget_theme_colors"
    
    func placeholder(in context: Context) -> AIQuickAccessEntry {
        AIQuickAccessEntry(date: Date(), theme: .defaultTheme)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (AIQuickAccessEntry) -> ()) {
        let entry = AIQuickAccessEntry(date: Date(), theme: loadTheme())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<AIQuickAccessEntry>) -> ()) {
        let theme = loadTheme()
        let entry = AIQuickAccessEntry(date: Date(), theme: theme)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadTheme() -> AIWidgetTheme {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            return .defaultTheme
        }
        
        struct WidgetThemeColors: Codable {
            let primaryData: Data
            let secondaryData: Data
        }
        
        if let themeData = userDefaults.data(forKey: themeKey),
           let decodedTheme = try? JSONDecoder().decode(WidgetThemeColors.self, from: themeData) {
            
            let primaryUi = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: decodedTheme.primaryData)) ?? UIColor.systemPink
            let secondaryUi = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: decodedTheme.secondaryData)) ?? UIColor.systemPurple
            
            return AIWidgetTheme(primary: Color(primaryUi), secondary: Color(secondaryUi))
        }
        
        return .defaultTheme
    }
}

// MARK: - Widget View

struct AIQuickAccessWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AIQuickAccessEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(theme: entry.theme)
        case .systemMedium:
            MediumWidgetView(theme: entry.theme)
        default:
            SmallWidgetView(theme: entry.theme)
        }
    }
}

// MARK: - Small Widget View

private struct SmallWidgetView: View {
    let theme: AIWidgetTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.secondary)
                Text("AI ASSISTANT") // More descriptive than "Schedulr AI"
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 12)
            
            // Main content
            Text("How can I help you today?") // More descriptive prompt
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(2)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Action button-like indicator
            HStack {
                Text("Ask Schedulr")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [theme.primary, theme.secondary], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(12)
        }
        .padding(12)
        .widgetURL(URL(string: "schedulr://ai-chat"))
    }
}

// MARK: - Medium Widget View

private struct MediumWidgetView: View {
    let theme: AIWidgetTheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side: Branding & Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.primary)
                    Text("AI ASSISTANT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                
                Text("How can I help you today?")
                    .font(.system(size: 22, weight: .bold, design: .rounded)) // Increased size
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Text("Select a mode")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right side: Actions
            VStack(alignment: .leading, spacing: 8) {
                // Chat action
                Link(destination: URL(string: "schedulr://ai-chat")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Text Chat")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Type your question") // Restored context
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.primary)
                    .cornerRadius(14)
                }
                
                // Voice action
                Link(destination: URL(string: "schedulr://ai-chat?voice=true")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Voice Mode")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Speak your question") // Restored context
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.secondary)
                    .cornerRadius(14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

// MARK: - Widget Definition

struct AIQuickAccessWidget: Widget {
    let kind: String = "AIQuickAccessWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AIQuickAccessProvider()) { entry in
            AIQuickAccessWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ask Scheduly")
        .description("Quick access to your AI scheduling assistant.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    AIQuickAccessWidget()
} timeline: {
    AIQuickAccessEntry(date: Date(), theme: .defaultTheme)
}

#Preview("Medium", as: .systemMedium) {
    AIQuickAccessWidget()
} timeline: {
    AIQuickAccessEntry(date: Date(), theme: .defaultTheme)
}

