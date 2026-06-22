//
//  ChurchNoteDesignTokens.swift
//  AMENAPP
//
//  Shared design tokens for the Church Notes expressive formatting system.
//  Defines spacing, corner radii, shadows, block tints, animation presets,
//  and glass styles specific to the Church Notes editor.
//

import SwiftUI

// MARK: - Church Note Tokens

enum CNToken {

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: - Corner Radius

    enum Radius {
        static let chip: CGFloat = 100    // Full capsule
        static let button: CGFloat = 10
        static let card: CGFloat = 16
        static let editor: CGFloat = 20
        static let block: CGFloat = 12
    }

    // MARK: - Shadows

    enum Shadow {
        static let card = (color: Color.black.opacity(0.04), radius: CGFloat(8), y: CGFloat(2))
        static let capsule = (color: Color.black.opacity(0.08), radius: CGFloat(12), y: CGFloat(4))
        static let block = (color: Color.black.opacity(0.03), radius: CGFloat(4), y: CGFloat(1))
    }

    // MARK: - Block Background Tints

    enum BlockTint {
        static let quote      = Color(red: 0.894, green: 0.890, blue: 0.918).opacity(0.5) // lavender-gray
        static let takeaway   = Color(red: 0.957, green: 0.906, blue: 0.631).opacity(0.35) // warm yellow
        static let prayer     = Color(red: 0.953, green: 0.855, blue: 0.875).opacity(0.4)  // soft rose
        static let action     = Color(red: 0.867, green: 0.914, blue: 0.847).opacity(0.4)  // muted sage
        static let reflection = Color(red: 0.890, green: 0.870, blue: 0.930).opacity(0.35) // misty violet
        static let scripture  = Color(red: 0.863, green: 0.906, blue: 0.969).opacity(0.4)  // dusty blue

        static func tint(for type: ChurchNoteBlockType) -> Color {
            switch type {
            case .paragraph:    return Color.clear
            case .quote:        return quote
            case .takeaway:     return takeaway
            case .prayer:       return prayer
            case .action:       return action
            case .reflection:   return reflection
            case .scripture:    return scripture
            // NIS placeholder — Lane F/G/H replaces in Wave 2
            case .scriptureLive: return scripture
            case .prayerCard:    return prayer
            case .wrestling:     return Color(red: 0.957, green: 0.906, blue: 0.780).opacity(0.35) // warm amber
            }
        }
    }

    // MARK: - Block Border Colors

    enum BlockBorder {
        static func color(for type: ChurchNoteBlockType) -> Color {
            switch type {
            case .paragraph:    return Color.clear
            case .quote:        return Color(red: 0.776, green: 0.769, blue: 0.816).opacity(0.5)
            case .takeaway:     return Color(red: 0.847, green: 0.765, blue: 0.424).opacity(0.4)
            case .prayer:       return Color(red: 0.867, green: 0.725, blue: 0.761).opacity(0.4)
            case .action:       return Color(red: 0.725, green: 0.820, blue: 0.690).opacity(0.4)
            case .reflection:   return Color(red: 0.780, green: 0.740, blue: 0.850).opacity(0.4)
            case .scripture:    return Color(red: 0.725, green: 0.796, blue: 0.906).opacity(0.4)
            // NIS placeholder — Lane F/G/H replaces in Wave 2
            case .scriptureLive: return Color(red: 0.725, green: 0.796, blue: 0.906).opacity(0.4)
            case .prayerCard:    return Color(red: 0.867, green: 0.725, blue: 0.761).opacity(0.4)
            case .wrestling:     return Color(red: 0.847, green: 0.785, blue: 0.550).opacity(0.4) // warm amber
            }
        }
    }

    // MARK: - Animation Presets

    enum Anim {
        /// Quick ease for button taps (0.15s).
        static let quickTap = Animation.easeOut(duration: 0.15)

        /// Smooth spring for section expand/collapse.
        static let smoothExpand = Animation.spring(response: 0.4, dampingFraction: 0.78)

        /// Gentle transition for sticky header material.
        static let headerTransition = Animation.easeInOut(duration: 0.25)

        /// Subtle insertion/removal for chips and blocks.
        static let chipInsert = Animation.spring(response: 0.3, dampingFraction: 0.8)

        /// Transition for review mode toggle.
        static let reviewToggle = Animation.spring(response: 0.35, dampingFraction: 0.85)

        /// Subtle autosave pulse.
        static let autosavePulse = Animation.easeInOut(duration: 0.6)

        /// Formatting bar reveal.
        static let barReveal = Animation.spring(response: 0.3, dampingFraction: 0.85)
    }

    // MARK: - Glass Background

    enum Glass {
        /// Standard glass card background for Church Notes sections.
        static func cardBackground() -> some View {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }

        /// Block-level glass background with semantic tint.
        static func blockBackground(type: ChurchNoteBlockType) -> some View {
            RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                .fill(BlockTint.tint(for: type))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                        .strokeBorder(BlockBorder.color(for: type), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Review Mode

    enum Review {
        /// Slightly stronger highlight opacity in review mode for better scanning.
        static let highlightBoost: Double = 0.15
    }
}
