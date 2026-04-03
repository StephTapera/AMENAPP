// AMENFont.swift
// AMENAPP
//
// Centralised typography helper that wraps every font usage with
// Dynamic Type scaling via Font.custom(_:size:relativeTo:).
//
// Usage:
//   .font(AMENFont.bold(24))          // OpenSans-Bold, scales relative to .title
//   .font(AMENFont.semiBold(15))      // OpenSans-SemiBold, scales relative to .subheadline
//   .font(AMENFont.regular(14))       // OpenSans-Regular, scales relative to .body
//   .font(.systemScaled(size: 14))    // System font, Dynamic Type scaled
//
// Prefer these helpers over raw .font(.systemScaled()) throughout the codebase.

import SwiftUI
import UIKit

// MARK: - Dynamic Type System Font Extension

/// Drop-in replacement for .font(.systemScaled(X)) that respects Dynamic Type.
///
/// SwiftUI's `.system(size:)` uses a fixed point size — it does NOT scale when
/// the user increases their text size in Settings → Accessibility → Larger Text.
/// This extension wraps the call with a scaled metric so every size responds
/// to the user's Dynamic Type preference.
///
///   Before:  .font(.systemScaled(14))
///   After:   .font(.systemScaled(size: 14))
extension Font {
    static func systemScaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let style = AMENFont.textStyle(for: size)
        // Use a UIFont scaled by UIFontMetrics so the point size grows with the
        // user's preferred content size category.
        let descriptor = UIFont.systemFont(ofSize: size, weight: weight.uiWeight).fontDescriptor
        let scaledSize = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size)
        let uiFont = UIFont(descriptor: descriptor, size: scaledSize)
        return Font(uiFont)
    }
}

private extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle:   return .largeTitle
        case .title:        return .title1
        case .title2:       return .title2
        case .title3:       return .title3
        case .headline:     return .headline
        case .subheadline:  return .subheadline
        case .body:         return .body
        case .callout:      return .callout
        case .footnote:     return .footnote
        case .caption:      return .caption1
        case .caption2:     return .caption2
        @unknown default:   return .body
        }
    }
}

// MARK: - AMENFont (OpenSans custom font, Dynamic Type aware)

enum AMENFont {

    // MARK: - Weights

    static func bold(_ size: CGFloat) -> Font {
        Font.custom("OpenSans-Bold", size: size, relativeTo: textStyle(for: size))
    }

    static func semiBold(_ size: CGFloat) -> Font {
        Font.custom("OpenSans-SemiBold", size: size, relativeTo: textStyle(for: size))
    }

    static func medium(_ size: CGFloat) -> Font {
        Font.custom("OpenSans-Medium", size: size, relativeTo: textStyle(for: size))
    }

    static func regular(_ size: CGFloat) -> Font {
        Font.custom("OpenSans-Regular", size: size, relativeTo: textStyle(for: size))
    }

    static func light(_ size: CGFloat) -> Font {
        Font.custom("OpenSans-Light", size: size, relativeTo: textStyle(for: size))
    }

    // MARK: - Semantic text style mapping (internal + used by Font extension)

    /// Maps a nominal point size to the closest Apple text style so that
    /// Dynamic Type scales it appropriately.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case 12..<13: return .caption
        case 13..<15: return .footnote
        case 15..<17: return .subheadline
        case 17..<20: return .body
        case 20..<24: return .title3
        case 24..<28: return .title2
        case 28..<34: return .title
        default:       return .largeTitle
        }
    }
}
