import SwiftUI

struct ConsentBannerView: View {
    @ObservedObject var consentManager: ConsentManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingCustomize = false
    @State private var thirdPartyServicesEnabled = true
    
    var body: some View {
        VStack(spacing: 0) {
            if showingCustomize {
                customizeView
            } else {
                mainBanner
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingCustomize)
        .onChange(of: showingCustomize) { _, isShowing in
            // Initialize state variables from current preferences when showing customize view
            if isShowing {
                let prefs = consentManager.preferences
                thirdPartyServicesEnabled = prefs.thirdPartyServices
            }
        }
    }
    
    private var mainBanner: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                themeManager.primaryColor,
                                themeManager.secondaryColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Privacy Matters")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("We do not track you across apps or websites. Any cookies used on our website are strictly essential for website functionality (like keeping you logged in) and are never used for advertising, tracking, or data sharing with third parties. We use Supabase for authentication and data storage, and OpenAI for AI features. You can choose which services to allow.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    consentManager.rejectAll()
                } label: {
                    Text("Reject All")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                Button {
                    showingCustomize = true
                } label: {
                    Text("Customize")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                Button {
                    consentManager.acceptAll()
                } label: {
                    Text("Accept All")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    themeManager.primaryColor,
                                    themeManager.secondaryColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private var customizeView: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    showingCustomize = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("Customize Preferences")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Invisible button for balance
                Button { } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.clear)
                }
                .disabled(true)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                ConsentOptionView(
                    title: "Essential Services",
                    description: "Supabase for authentication and data storage, and OpenAI for AI features. Any cookies are strictly functional (like session management) and never used for cross-app/website tracking or advertising.",
                    isEnabled: $thirdPartyServicesEnabled,
                    themeManager: themeManager
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.primaryColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What We Don't Do")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("• No cross-app or cross-website tracking\n• No advertising or marketing cookies\n• No third-party analytics or usage tracking\n• No selling or sharing of your data\n• Cookies are only for essential functionality")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            
            Button {
                consentManager.saveCustomized(
                    thirdPartyServices: thirdPartyServicesEnabled
                )
            } label: {
                Text("Save Preferences")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [
                                themeManager.primaryColor,
                                themeManager.secondaryColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

struct ConsentOptionView: View {
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    @ObservedObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            
            Text(description)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            ConsentBannerView(consentManager: ConsentManager.shared)
                .environmentObject(ThemeManager.shared)
        }
    }
}

