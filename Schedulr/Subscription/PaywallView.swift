//
//  PaywallView.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import SwiftUI
import RevenueCat
#if os(iOS)
import UIKit
#endif

struct PaywallView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProduct: SubscriptionProduct = .proYearly
    @State private var showLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 56, weight: .medium))
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
                            
                            Text("Upgrade to Pro")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Unlock advanced scheduling features")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)
                        
                        // Feature comparison
                        featureComparisonSection
                        
                        // Pricing options
                        pricingOptionsSection
                        
                        // Purchase button
                        purchaseButton
                        
                        // Restore purchases
                        restorePurchasesButton
                        
                        // Footer
                        footerText
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Purchase Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await subscriptionManager.configure()
            }
        }
    }
    
    private var featureComparisonSection: some View {
        VStack(spacing: 16) {
            Text("Everything you need")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                FeatureComparisonRow(
                    title: "Groups",
                    freeValue: "1",
                    proValue: "5",
                    icon: "person.3.fill"
                )
                
                FeatureComparisonRow(
                    title: "Members per group",
                    freeValue: "5",
                    proValue: "10",
                    icon: "person.2.fill"
                )
                
                FeatureComparisonRow(
                    title: "AI requests/month",
                    freeValue: "0",
                    proValue: "100",
                    icon: "sparkles"
                )
                
                FeatureComparisonRow(
                    title: "Calendar sync",
                    freeValue: "✓",
                    proValue: "✓",
                    icon: "calendar.badge.plus",
                    both: true
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var pricingOptionsSection: some View {
        VStack(spacing: 12) {
            Text("Choose your plan")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Yearly option
            Button {
                selectedProduct = .proYearly
            } label: {
                PricingOptionCard(
                    product: .proYearly,
                    isSelected: selectedProduct == .proYearly,
                    savings: "Save £15/year"
                )
            }
            
            // Monthly option
            Button {
                selectedProduct = .proMonthly
            } label: {
                PricingOptionCard(
                    product: .proMonthly,
                    isSelected: selectedProduct == .proMonthly
                )
            }
        }
    }
    
    private var purchaseButton: some View {
        Button {
            Task {
                await handlePurchase()
            }
        } label: {
            HStack {
                if showLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe to Pro")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
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
        .disabled(showLoading)
    }
    
    private var restorePurchasesButton: some View {
        Button {
            Task {
                showLoading = true
                let success = await subscriptionManager.restorePurchases()
                showLoading = false
                if success {
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private var footerText: some View {
        VStack(spacing: 4) {
            Text("Subscriptions auto-renew unless cancelled.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            HStack(spacing: 4) {
                Button("Terms of Service") {
                    if let url = URL(string: "https://schedulr.co.uk/terms") {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.tertiary)
                
                Button("Privacy Policy") {
                    if let url = URL(string: "https://schedulr.co.uk/privacy") {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    private func handlePurchase() async {
        showLoading = true
        
        // Get package from RevenueCat
        guard let offering = subscriptionManager.currentOffering else {
            errorMessage = "Subscription options not available"
            showError = true
            showLoading = false
            return
        }
        
        // Find the appropriate package
        let package: Package?
        switch selectedProduct {
        case .proMonthly:
            package = offering.availablePackages.first { $0.storeProduct.productIdentifier == SubscriptionProduct.proMonthly.rawValue }
        case .proYearly:
            package = offering.availablePackages.first { $0.storeProduct.productIdentifier == SubscriptionProduct.proYearly.rawValue }
        }
        
        guard let selectedPackage = package else {
            errorMessage = "Product not found"
            showError = true
            showLoading = false
            return
        }
        
        // Purchase
        let success = await subscriptionManager.purchaseSubscription(selectedPackage)
        showLoading = false
        
        if success {
            dismiss()
        } else {
            errorMessage = subscriptionManager.errorMessage ?? "Purchase failed"
            showError = true
        }
    }
}

private struct FeatureComparisonRow: View {
    let title: String
    let freeValue: String
    let proValue: String
    let icon: String
    var both: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(both ? .secondary : Color(red: 0.58, green: 0.41, blue: 0.87))
                .frame(width: 32)
            
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 20) {
                Text(freeValue)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                
                Text(proValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
            }
        }
    }
}

private struct PricingOptionCard: View {
    let product: SubscriptionProduct
    let isSelected: Bool
    var savings: String? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(product.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let savings = savings {
                        Text(savings)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.59, green: 0.85, blue: 0.34))
                            .cornerRadius(6)
                    }
                }
                
                Text(product.price + " " + product.period)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundColor(isSelected ? Color(red: 0.98, green: 0.29, blue: 0.55) : .secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color(red: 0.98, green: 0.29, blue: 0.55) : Color.clear, lineWidth: 2)
                )
        )
    }
}

#Preview {
    PaywallView()
}

