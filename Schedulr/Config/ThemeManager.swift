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
            return (
                Color(red: 0.98, green: 0.29, blue: 0.55),
                Color(red: 0.58, green: 0.41, blue: 0.87)
            )
        case .blueTeal:
            return (
                Color(red: 0.27, green: 0.63, blue: 0.98),
                Color(red: 0.18, green: 0.80, blue: 0.74)
            )
        case .greenMint:
            return (
                Color(red: 0.20, green: 0.78, blue: 0.35),
                Color(red: 0.00, green: 0.98, blue: 0.60)
            )
        case .orangeRed:
            return (
                Color(red: 1.00, green: 0.58, blue: 0.00),
                Color(red: 0.96, green: 0.26, blue: 0.21)
            )
        case .purpleBlue:
            return (
                Color(red: 0.58, green: 0.41, blue: 0.87),
                Color(red: 0.27, green: 0.63, blue: 0.98)
            )
        case .tealGreen:
            return (
                Color(red: 0.18, green: 0.80, blue: 0.74),
                Color(red: 0.20, green: 0.78, blue: 0.35)
            )
        case .dark:
            // Dark theme accent colors: dark gray to black gradient
            return (
                Color(red: 0.25, green: 0.25, blue: 0.25),
                Color(red: 0.15, green: 0.15, blue: 0.15)
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
        if case .preset = currentTheme.type,
           let name = currentTheme.name,
           name == PresetTheme.dark.rawValue {
            return .dark
        }
        return nil
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

