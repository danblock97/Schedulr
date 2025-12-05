//
//  UpgradePromptModal.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import SwiftUI

struct UpgradePromptModal: View {
    let onDismiss: () -> Void
    let onUpgrade: () -> Void
    let limitType: LimitType
    
    enum LimitType {
        case groups
        case members
        case ai
        
        var title: String {
            switch self {
            case .groups: return "Group Limit Reached"
            case .members: return "Member Limit Reached"
            case .ai: return "AI Usage Limit Reached"
            }
        }
        
        var message: String {
            switch self {
            case .groups:
                return "You've reached your group limit. Upgrade to Pro to create up to 5 groups!"
            case .members:
                return "You've reached your member limit. Upgrade to Pro to add up to 10 members per group!"
            case .ai:
                return "You've used up your AI requests this month. Upgrade to Pro for AI-assisted propose times, Scheduly, and 300 requests per month!"
            }
        }
        
        var icon: String {
            switch self {
            case .groups: return "person.3.fill"
            case .members: return "person.2.fill"
            case .ai: return "sparkles"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: limitType.icon)
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
                
                Text(limitType.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(limitType.message)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Feature comparison
            VStack(spacing: 16) {
                FeatureRow(icon: "person.3.fill", 
                          feature: "Groups", 
                          freeValue: "1", 
                          proValue: "5")
                FeatureRow(icon: "person.2.fill", 
                          feature: "Members per group", 
                          freeValue: "5", 
                          proValue: "10")
                FeatureRow(icon: "sparkles", 
                          feature: "AI requests/month", 
                          freeValue: "0", 
                          proValue: "300")
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: onUpgrade) {
                    Text("Upgrade to Pro")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55),
                                    Color(red: 0.58, green: 0.41, blue: 0.87)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                
                Button(action: onDismiss) {
                    Text("Maybe Later")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}

private struct FeatureRow: View {
    let icon: String
    let feature: String
    let freeValue: String
    let proValue: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(red: 0.58, green: 0.41, blue: 0.87))
                .frame(width: 32)
            
            Text(feature)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 20) {
                Text("Free: \(freeValue)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                
                Text("Pro: \(proValue)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
            }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        UpgradePromptModal(
            onDismiss: {},
            onUpgrade: {},
            limitType: .groups
        )
    }
}

