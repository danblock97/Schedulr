import SwiftUI
import Foundation
import UIKit

// MARK: - Theme Models

enum ThemeType: String, Codable {
    case preset
    case custom
}

struct ColorTheme: Codable, Equatable {
    var type: ThemeType
    var name: String? // For preset themes
    var colors: [ColorComponents]? // For custom themes (2 colors for gradient)
    
    struct ColorComponents: Codable, Equatable {
        var r: Double
        var g: Double
        var b: Double
        
        var color: Color {
            Color(red: r, green: g, blue: b)
        }
        
        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
        
        init(color: Color) {
            // Convert SwiftUI Color to RGB components via UIColor
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            
            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                self.r = Double(red)
                self.g = Double(green)
                self.b = Double(blue)
            } else {
                // Fallback to default pink color if conversion fails
                self.r = 0.98
                self.g = 0.29
                self.b = 0.55
            }
        }
    }
}

enum PresetTheme: String, CaseIterable {
    case pinkPurple = "pink_purple"
    case blueTeal = "blue_teal"
    case greenMint = "green_mint"
    case orangeRed = "orange_red"
    case purpleBlue = "purple_blue"
    case tealGreen = "teal_green"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .pinkPurple: return "Pink & Purple"
        case .blueTeal: return "Blue & Teal"
        case .greenMint: return "Green & Mint"
        case .orangeRed: return "Orange & Red"
        case .purpleBlue: return "Purple & Blue"
        case .tealGreen: return "Teal & Green"
        case .dark: return "Dark Mode"
        }
    }
    
    var colors: (Color, Color) {
        switch self {
        case .pinkPurple:
            // Softer rose to lavender
            return (
                Color(red: 0.85, green: 0.45, blue: 0.65),
                Color(red: 0.65, green: 0.55, blue: 0.80)
            )
        case .blueTeal:
            // Softer sky blue to teal
            return (
                Color(red: 0.40, green: 0.65, blue: 0.85),
                Color(red: 0.35, green: 0.70, blue: 0.75)
            )
        case .greenMint:
            // Softer sage green to mint
            return (
                Color(red: 0.45, green: 0.70, blue: 0.50),
                Color(red: 0.50, green: 0.80, blue: 0.70)
            )
        case .orangeRed:
            // Softer peach to coral
            return (
                Color(red: 0.90, green: 0.65, blue: 0.45),
                Color(red: 0.85, green: 0.50, blue: 0.50)
            )
        case .purpleBlue:
            // Softer periwinkle to sky
            return (
                Color(red: 0.65, green: 0.55, blue: 0.80),
                Color(red: 0.50, green: 0.65, blue: 0.85)
            )
        case .tealGreen:
            // Softer teal to sage
            return (
                Color(red: 0.40, green: 0.70, blue: 0.75),
                Color(red: 0.50, green: 0.70, blue: 0.60)
            )
        case .dark:
            // Dark theme accent colors: very dark gray to black for true dark mode
            return (
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.10, green: 0.10, blue: 0.10)
            )
        }
    }
    
    var colorTheme: ColorTheme {
        ColorTheme(type: .preset, name: rawValue, colors: nil)
    }
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: ColorTheme = ColorTheme(type: .preset, name: "pink_purple", colors: nil)
    
    private init() {}
    
    // MARK: - Computed Properties
    
    var primaryColor: Color {
        colors.0
    }
    
    var secondaryColor: Color {
        colors.1
    }
    
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Subtle background gradient overlay (low opacity for backgrounds)
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                primaryColor.opacity(0.08),
                secondaryColor.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Radial gradient for background depth effects
    var backgroundRadialGradient1: RadialGradient {
        RadialGradient(
            colors: [
                primaryColor.opacity(0.06),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 300
        )
    }
    
    var backgroundRadialGradient2: RadialGradient {
        RadialGradient(
            colors: [
                secondaryColor.opacity(0.05),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 350
        )
    }
    
    var colors: (Color, Color) {
        switch currentTheme.type {
        case .preset:
            if let name = currentTheme.name,
               let preset = PresetTheme(rawValue: name) {
                return preset.colors
            }
            // Fallback to default
            return PresetTheme.pinkPurple.colors
            
        case .custom:
            guard let colorComps = currentTheme.colors,
                  colorComps.count >= 2 else {
                return PresetTheme.pinkPurple.colors
            }
            return (colorComps[0].color, colorComps[1].color)
        }
    }
    
    var preferredColorScheme: ColorScheme? {
        // Respect system dark mode preference - return nil to use system default
        // Only override if explicitly set to dark theme
        if case .preset = currentTheme.type,
           let name = currentTheme.name,
           name == PresetTheme.dark.rawValue {
            return .dark
        }
        // Return nil to respect system color scheme preference
        return nil
    }
    
    // Helper to detect system color scheme
    var systemColorScheme: ColorScheme {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let traitCollection = windowScene.windows.first?.traitCollection {
            return traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        // Fallback: check UITraitCollection directly
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }
    
    // MARK: - Theme Management
    
    func setTheme(_ theme: ColorTheme) {
        currentTheme = theme
    }
    
    func setPresetTheme(_ preset: PresetTheme) {
        currentTheme = preset.colorTheme
    }
    
    func setCustomTheme(colors: [ColorTheme.ColorComponents]) {
        guard colors.count >= 2 else { return }
        currentTheme = ColorTheme(type: .custom, name: nil, colors: colors)
    }
}

