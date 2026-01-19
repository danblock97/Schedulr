import Foundation
import SwiftUI

/// Preset event theme templates with emojis and suggested colors
struct EventThemeTemplate: Identifiable, Equatable {	
    let id: String
    let name: String
    let emoji: String
    let suggestedColor: ColorComponents
    let presetI44 tmageName: String? // Name of bundled asset image
    
    static let movieNight = EventThemeTemplate(
        id: "movie_night",
        name: "Movie Night",
        emoji: "🎬",
        suggestedColor: ColorComponents(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0),
        presetImageName: nil // Can be added later with bundled assets
    )
    
    static let dinner = EventThemeTemplate(
        id: "dinner",
        name: "Dinner",
        emoji: "🍕",
        suggestedColor: ColorComponents(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0),
        presetImageName: nil
    )
    
    static let party = EventThemeTemplate(
        id: "party",
        name: "Party",
        emoji: "🎉",
        suggestedColor: ColorComponents(red: 0.9, green: 0.3, blue: 0.5, alpha: 1.0),
        presetImageName: nil
    )
    
    static let trip = EventThemeTemplate(
        id: "trip",
        name: "Trip",
        emoji: "✈️",
        suggestedColor: ColorComponents(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0),
        presetImageName: nil
    )
    
    static let gameNight = EventThemeTemplate(
        id: "game_night",
        name: "Game Night",
        emoji: "🎮",
        suggestedColor: ColorComponents(red: 0.5, green: 0.3, blue: 0.9, alpha: 1.0),
        presetImageName: nil
    )
    
    static let custom = EventThemeTemplate(
        id: "custom",
        name: "Custom",
        emoji: "✨",
        suggestedColor: ColorComponents(red: 0.58, green: 0.41, blue: 0.87, alpha: 1.0),
        presetImageName: nil
    )
    
    static let allTemplates: [EventThemeTemplate] = [
        .movieNight,
        .dinner,
        .party,
        .trip,
        .gameNight,
        .custom
    ]
}

/// Helper for emoji selection
struct EmojiPicker {
    static let popularEmojis: [String] = [
        "🎬", "🍕", "🎉", "✈️", "🎮", "🎂", "🎪", "🏖️", "⛷️", "🏄",
        "🎨", "🎭", "🎤", "🎧", "🎸", "🎹", "🥳", "🎊", "🎈", "🎁",
        "🏋️", "⚽", "🏀", "🎾", "🏐", "🏓", "🏸", "🏒", "⛳", "🏌️",
        "🍔", "🍟", "🍕", "🌮", "🌯", "🍜", "🍱", "🍣", "🍰", "🍪",
        "☕", "🍷", "🍸", "🍹", "🍺", "🍻", "🥂", "🧃", "🧉", "🧊",
        "🎓", "📚", "✏️", "📝", "📖", "📕", "📗", "📘", "📙", "📔",
        "🎯", "🎲", "🃏", "🀄", "🎴", "🎰", "🎳", "🎪", "🎭", "🎨"
    ]
    
    static let categories: [(name: String, emojis: [String])] = [
        ("Activities", ["🎬", "🎮", "🎨", "🎭", "🎤", "🎧", "🎸", "🎹", "🎯", "🎲"]),
        ("Food & Drink", ["🍕", "🍔", "🍟", "🌮", "🌯", "🍜", "🍱", "🍣", "🍰", "☕", "🍷", "🍸"]),
        ("Celebrations", ["🎉", "🎂", "🥳", "🎊", "🎈", "🎁", "🎪", "🎭"]),
        ("Travel", ["✈️", "🏖️", "⛷️", "🏄", "🚗", "🚂", "🚢", "🚁"]),
        ("Sports", ["⚽", "🏀", "🎾", "🏐", "🏓", "🏸", "🏒", "⛳", "🏋️"]),
        ("Education", ["🎓", "📚", "✏️", "📝", "📖", "🎯"])
    ]
}

