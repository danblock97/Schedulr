//
//  UpgradeInlineView.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import SwiftUI

struct UpgradeInlineView: View {
    let message: String
    let onUpgrade: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.29, blue: 0.55),
                                        Color(red: 0.58, green: 0.41, blue: 0.87)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.29, blue: 0.55).opacity(0.3),
                                    Color(red: 0.58, green: 0.41, blue: 0.87).opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        UpgradeInlineView(
            message: "Upgrade to create more groups",
            onUpgrade: {}
        )
        
        UpgradeInlineView(
            message: "Get unlimited AI requests with Pro",
            onUpgrade: {}
        )
    }
    .padding()
}

