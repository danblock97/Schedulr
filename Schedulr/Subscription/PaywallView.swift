//
//  PaywallView.swift
//  Schedulr
//
//  Created by Daniel Block on [Date].
//

import SwiftUI
import RevenueCat
import StoreKit
#if os(iOS)
import UIKit
import SafariServices
#endif

struct PaywallView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPackage: Package?
    @State private var monthlyPackage: Package?
    @State private var yearlyPackage: Package?
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
                if errorMessage.contains("test account") || errorMessage.contains("restore") {
                    Button("Restore Purchases") {
                        Task {
                            showLoading = true
                            let success = await subscriptionManager.restorePurchases()
                            showLoading = false
                            if success {
                                dismiss()
                            } else {
                                errorMessage = subscriptionManager.errorMessage ?? "Failed to restore purchases"
                                showError = true
                            }
                        }
                    }
                }
            } message: {
                Text(errorMessage)
            }
            .task {
                await subscriptionManager.configure()
                await loadPackages()
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
                    proValue: "Unlimited",
                    icon: "person.3.fill"
                )
                
                FeatureComparisonRow(
                    title: "Members per group",
                    freeValue: "5",
                    proValue: "Unlimited",
                    icon: "person.2.fill"
                )
                
                FeatureComparisonRow(
                    title: "AI requests/month",
                    freeValue: "0",
                    proValue: "300",
                    icon: "sparkles"
                )
                
                FeatureComparisonRow(
                    title: "Propose times",
                    freeValue: "Standard (manual)",
                    proValue: "AI assist + natural language",
                    icon: "wand.and.stars"
                )
                
                FeatureComparisonRow(
                    title: "Share when you're free",
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your plan")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Text("Auto-renewing subscription")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Yearly option
            if let yearlyPackage = yearlyPackage {
                Button {
                    selectedPackage = yearlyPackage
                } label: {
                    PricingOptionCard(
                        package: yearlyPackage,
                        monthlyPackage: monthlyPackage,
                        isSelected: selectedPackage?.identifier == yearlyPackage.identifier
                    )
                }
            }
            
            // Monthly option
            if let monthlyPackage = monthlyPackage {
                Button {
                    selectedPackage = monthlyPackage
                } label: {
                    PricingOptionCard(
                        package: monthlyPackage,
                        monthlyPackage: nil,
                        isSelected: selectedPackage?.identifier == monthlyPackage.identifier
                    )
                }
            }
            
            // Loading state if packages aren't available yet
            if monthlyPackage == nil && yearlyPackage == nil {
                HStack {
                    ProgressView()
                    Text("Loading subscription options...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding()
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
        .disabled(showLoading || selectedPackage == nil)
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
                Button("Terms of Use (EULA)") {
                    Task {
                        await openURL(urlString: "https://schedulr.co.uk/terms")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.tertiary)
                
                Button("Privacy Policy") {
                    Task {
                        await openURL(urlString: "https://schedulr.co.uk/privacy")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    /// Opens a URL in SFSafariViewController
    /// No tracking is performed - cookies are only used for essential website functionality
    private func openURL(urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        #if os(iOS)
        // Use SFSafariViewController for better in-app experience
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredControlTintColor = UIColor(red: 0.98, green: 0.29, blue: 0.55, alpha: 1.0)
        safariVC.preferredBarTintColor = .systemBackground
        if #available(iOS 11.0, *) {
            safariVC.dismissButtonStyle = .close
        }
        
        // Present the Safari view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var presentingVC = rootViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(safariVC, animated: true)
        }
        #else
        await UIApplication.shared.open(url)
        #endif
    }
    
    private func loadPackages() async {
        guard let offering = subscriptionManager.currentOffering else {
            return
        }
        
        // Find monthly and yearly packages
        monthlyPackage = offering.availablePackages.first { package in
            package.storeProduct.productIdentifier == SubscriptionProduct.proMonthly.rawValue
        }
        
        yearlyPackage = offering.availablePackages.first { package in
            package.storeProduct.productIdentifier == SubscriptionProduct.proYearly.rawValue
        }
        
        // Set default selection to yearly if available, otherwise monthly
        selectedPackage = yearlyPackage ?? monthlyPackage
    }
    
    private func handlePurchase() async {
        showLoading = true
        
        guard let selectedPackage = selectedPackage else {
            errorMessage = "Please select a subscription plan"
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
            // Only show error if there's a message (user cancellation won't have a message)
            if let message = subscriptionManager.errorMessage, !message.isEmpty {
                errorMessage = message
                showError = true
            }
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
                    .frame(minWidth: 80, alignment: .trailing)
                
                Text(proValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.29, blue: 0.55))
                    .frame(minWidth: 100, alignment: .leading)
            }
        }
    }
}

private struct PricingOptionCard: View {
    let package: Package
    let monthlyPackage: Package?
    let isSelected: Bool
    
    private var productTitle: String {
        package.storeProduct.localizedTitle
    }
    
    private var productPrice: String {
        package.storeProduct.localizedPriceString
    }
    
    /// Extracts the currency locale from the localizedPriceString
    /// Since priceLocale is unavailable on iOS, we detect the currency symbol
    /// This ensures calculated prices (monthly equivalent, savings) use the same currency as displayed prices
    private var currencyLocale: Locale {
        let priceString = package.storeProduct.localizedPriceString
        
        // Check for common currency symbols and return appropriate locale
        // StoreKit's localizedPriceString already uses the correct currency for the user's App Store region
        if priceString.contains("£") {
            return Locale(identifier: "en_GB")
        } else if priceString.contains("€") {
            // Euro - try to detect country from device locale, default to Ireland
            if Locale.current.identifier.contains("FR") {
                return Locale(identifier: "fr_FR")
            } else if Locale.current.identifier.contains("DE") {
                return Locale(identifier: "de_DE")
            } else {
                return Locale(identifier: "en_IE")
            }
        } else if priceString.contains("$") {
            // Dollar - could be USD, CAD, AUD, NZD, etc.
            // Try to detect from device locale
            let deviceLocale = Locale.current.identifier
            if deviceLocale.contains("CA") {
                return Locale(identifier: "en_CA")
            } else if deviceLocale.contains("AU") {
                return Locale(identifier: "en_AU")
            } else if deviceLocale.contains("NZ") {
                return Locale(identifier: "en_NZ")
            } else {
                return Locale(identifier: "en_US")
            }
        } else if priceString.contains("¥") {
            // Yen - could be JPY or CNY
            if Locale.current.identifier.contains("CN") {
                return Locale(identifier: "zh_CN")
            } else {
                return Locale(identifier: "ja_JP")
            }
        } else if priceString.contains("kr") || priceString.contains("KR") {
            // Krona - could be SEK, NOK, DKK
            if Locale.current.identifier.contains("SE") {
                return Locale(identifier: "sv_SE")
            } else if Locale.current.identifier.contains("NO") {
                return Locale(identifier: "nb_NO")
            } else {
                return Locale(identifier: "da_DK")
            }
        }
        
        // Fallback: use device locale if available, otherwise default to GBP
        // Note: This ensures the formatter uses the correct currency formatting
        if !Locale.current.identifier.isEmpty {
            return Locale.current
        }
        return Locale(identifier: "en_GB")
    }
    
    private var subscriptionPeriod: String {
        guard let subscriptionPeriod = package.storeProduct.subscriptionPeriod else {
            return ""
        }
        
        switch subscriptionPeriod.unit {
        case .day:
            return subscriptionPeriod.value == 1 ? "per day" : "per \(subscriptionPeriod.value) days"
        case .week:
            return subscriptionPeriod.value == 1 ? "per week" : "per \(subscriptionPeriod.value) weeks"
        case .month:
            return subscriptionPeriod.value == 1 ? "per month" : "per \(subscriptionPeriod.value) months"
        case .year:
            return subscriptionPeriod.value == 1 ? "per year" : "per \(subscriptionPeriod.value) years"
        @unknown default:
            return ""
        }
    }
    
    private var monthlyEquivalent: String? {
        // Show the actual monthly package price for yearly subscriptions
        guard let subscriptionPeriod = package.storeProduct.subscriptionPeriod,
              subscriptionPeriod.unit == .year,
              subscriptionPeriod.value == 1,
              let monthlyPackage = monthlyPackage else {
            return nil
        }
        
        // Use the actual monthly package price, not a calculated division
        let monthlyPrice = NSDecimalNumber(decimal: monthlyPackage.storeProduct.price).doubleValue
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        // Use currency locale extracted from localizedPriceString to match App Store currency
        formatter.locale = currencyLocale
        
        if let formattedPrice = formatter.string(from: NSNumber(value: monthlyPrice)) {
            return "\(formattedPrice)/month"
        }
        
        return nil
    }
    
    private var savingsText: String? {
        guard let subscriptionPeriod = package.storeProduct.subscriptionPeriod,
              subscriptionPeriod.unit == .year,
              subscriptionPeriod.value == 1,
              let monthlyPackage = monthlyPackage else {
            return nil
        }
        
        let yearlyPrice = NSDecimalNumber(decimal: package.storeProduct.price).doubleValue
        let monthlyPrice = NSDecimalNumber(decimal: monthlyPackage.storeProduct.price).doubleValue
        let yearlyEquivalent = monthlyPrice * 12.0
        let savings = yearlyEquivalent - yearlyPrice
        
        guard savings > 0 else { return nil }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        // Use currency locale extracted from localizedPriceString to match App Store currency
        formatter.locale = currencyLocale
        
        if let formattedSavings = formatter.string(from: NSNumber(value: savings)) {
            return "Save \(formattedSavings)/year"
        }
        
        return nil
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(productTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let savings = savingsText {
                        Text(savings)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.59, green: 0.85, blue: 0.34))
                            .cornerRadius(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(productPrice) \(subscriptionPeriod)")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    
                    if let monthlyEquivalent = monthlyEquivalent {
                        Text(monthlyEquivalent)
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                }
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

