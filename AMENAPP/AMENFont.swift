// AMENFont.swift
// AMENAPP
//
// Centralised typography helper that wraps every OpenSans usage with
// Dynamic Type scaling via Font.custom(_:size:relativeTo:).
//
// Usage:
//   .font(AMENFont.bold(24))          // scales relative to .title
//   .font(AMENFont.semiBold(15))      // scales relative to .subheadline
//   .font(AMENFont.regular(14))       // scales relative to .body
//
// Prefer these helpers over raw Font.custom calls throughout the codebase.

import SwiftUI

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

    // MARK: - Semantic text style mapping

    /// Maps a nominal point size to the closest Apple text style so that
    /// Dynamic Type scales it appropriately.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
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
