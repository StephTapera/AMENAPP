import Foundation
import SwiftUI

/// How a viewer felt while engaging with a piece of media.
/// Used by Agent 7 (Faith Layer) to let users attach emotional context to reactions.
enum MoodTag: String, Codable, CaseIterable, Identifiable {
    case encouraged, convicted, grateful, joyful, prayerful, challenged, comforted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .encouraged:  return "Encouraged"
        case .convicted:   return "Convicted"
        case .grateful:    return "Grateful"
        case .joyful:      return "Joyful"
        case .prayerful:   return "Prayerful"
        case .challenged:  return "Challenged"
        case .comforted:   return "Comforted"
        }
    }

    var emoji: String {
        switch self {
        case .encouraged:  return "🌟"
        case .convicted:   return "🙏"
        case .grateful:    return "💛"
        case .joyful:      return "😊"
        case .prayerful:   return "🕊️"
        case .challenged:  return "💪"
        case .comforted:   return "🤍"
        }
    }

    /// Subtle tint color for the glass pill badge.
    var tintColor: Color {
        switch self {
        case .encouraged:  return Color.yellow.opacity(0.7)
        case .convicted:   return Color.purple.opacity(0.7)
        case .grateful:    return Color.orange.opacity(0.7)
        case .joyful:      return Color.green.opacity(0.7)
        case .prayerful:   return Color.blue.opacity(0.7)
        case .challenged:  return Color.red.opacity(0.7)
        case .comforted:   return Color.gray.opacity(0.7)
        }
    }
}
