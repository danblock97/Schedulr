//
//  SubscriptionBadge.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import SwiftUI

struct SubscriptionBadge: View {
    let tier: SubscriptionTier
    
    var body: some View {
        Text(tier.rawValue.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: tier == .pro
                                ? [Color(red: 0.98, green: 0.29, blue: 0.55), Color(red: 0.58, green: 0.41, blue: 0.87)]
                                : [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
    }
}

#Preview {
    HStack(spacing: 16) {
        SubscriptionBadge(tier: .free)
        SubscriptionBadge(tier: .pro)
    }
    .padding()
}

