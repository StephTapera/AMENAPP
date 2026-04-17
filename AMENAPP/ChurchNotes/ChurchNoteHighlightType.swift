//
//  ChurchNoteHighlightType.swift
//  AMENAPP
//
//  Semantic highlight types for Church Notes with approved soft color palette.
//  Each type represents a spiritual meaning, not just a visual style.
//

import SwiftUI
import UIKit

// MARK: - Highlight Type

enum ChurchNoteHighlightType: String, Codable, CaseIterable, Hashable, Identifiable {
    case takeaway   // Key Takeaway — warm butter
    case scripture  // Scripture Insight — dusty sky
    case prayer     // Prayer — rose mist
    case action     // Action Step — muted sage
    case quote      // Pastor Quote — stone lavender

    var id: String { rawValue }

    // MARK: - Display

    var displayTitle: String {
        switch self {
        case .takeaway:  return "Key Takeaway"
        case .scripture: return "Scripture"
        case .prayer:    return "Prayer"
        case .action:    return "Action Step"
        case .quote:     return "Quote"
        }
    }

    var icon: String {
        switch self {
        case .takeaway:  return "lightbulb.fill"
        case .scripture: return "book.fill"
        case .prayer:    return "hands.sparkles.fill"
        case .action:    return "checkmark.circle.fill"
        case .quote:     return "quote.opening"
        }
    }

    var shortLabel: String {
        switch self {
        case .takeaway:  return "Takeaway"
        case .scripture: return "Scripture"
        case .prayer:    return "Prayer"
        case .action:    return "Action"
        case .quote:     return "Quote"
        }
    }

    // MARK: - Content Highlight Colors (applied to text background)

    var fillColor: Color {
        switch self {
        case .takeaway:  return Color(cnHex: "F4E7A1")
        case .scripture: return Color(cnHex: "DCE7F7")
        case .prayer:    return Color(cnHex: "F3DADF")
        case .action:    return Color(cnHex: "DDE9D8")
        case .quote:     return Color(cnHex: "E4E3EA")
        }
    }

    var uiFillColor: UIColor {
        switch self {
        case .takeaway:  return UIColor(red: 0.957, green: 0.906, blue: 0.631, alpha: 1.0)
        case .scripture: return UIColor(red: 0.863, green: 0.906, blue: 0.969, alpha: 1.0)
        case .prayer:    return UIColor(red: 0.953, green: 0.855, blue: 0.875, alpha: 1.0)
        case .action:    return UIColor(red: 0.867, green: 0.914, blue: 0.847, alpha: 1.0)
        case .quote:     return UIColor(red: 0.894, green: 0.890, blue: 0.918, alpha: 1.0)
        }
    }

    // MARK: - Selected Button Colors (soft tint, never bright)

    var selectedButtonFill: Color {
        switch self {
        case .takeaway:  return Color(cnHex: "F8F1CB")
        case .scripture: return Color(cnHex: "E8EFF9")
        case .prayer:    return Color(cnHex: "F7E7EA")
        case .action:    return Color(cnHex: "E7F0E3")
        case .quote:     return Color(cnHex: "ECEBF0")
        }
    }

    var selectedButtonBorder: Color {
        switch self {
        case .takeaway:  return Color(cnHex: "D8C36C")
        case .scripture: return Color(cnHex: "B9CBE7")
        case .prayer:    return Color(cnHex: "DDB9C2")
        case .action:    return Color(cnHex: "B9D1B0")
        case .quote:     return Color(cnHex: "C6C4D0")
        }
    }

    /// Text on selected buttons is always near-black for readability.
    var selectedButtonTextColor: Color {
        Color.primary.opacity(0.85)
    }

    // MARK: - Mapping to existing HighlightCategory

    var highlightCategory: HighlightCategory {
        switch self {
        case .takeaway:  return .conviction
        case .scripture: return .scripture
        case .prayer:    return .prayer
        case .action:    return .action
        case .quote:     return .quote
        }
    }

    init?(from category: HighlightCategory) {
        switch category {
        case .conviction: self = .takeaway
        case .scripture:  self = .scripture
        case .prayer:     self = .prayer
        case .action:     self = .action
        case .quote:      self = .quote
        }
    }
}

// MARK: - Color hex init (scoped to avoid redeclaration)

private extension Color {
    init(cnHex: String) {
        let hex = cnHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
