// LiquidGlassContract.swift
// AMEN Intelligence Layer Phase 0
//
// FROZEN CONTRACT: Liquid Glass token and component rules for all Intelligence Layer surfaces.

import SwiftUI

enum AmenIntelligenceGlassContract {
    static let matteContentRule = "Content surfaces stay matte; Liquid Glass is reserved for chrome, navigation, ambient Berean panels, toolbars, and temporary controls."
    static let animationRule = "All Intelligence Layer animations must use Motion.adaptive."
}

enum AmenIntelligenceGlassRole: String, Codable, CaseIterable, Hashable, Sendable {
    case chromeBar
    case floatingBereanPanel
    case contextCapsule
    case toolCluster
    case confirmationPreview
    case matteContent
}

enum AmenIntelligenceGlassProminence: String, Codable, CaseIterable, Hashable, Sendable {
    case quiet
    case regular
    case prominent
}

struct AmenIntelligencePalette: Hashable, Sendable {
    let amenGold: Color
    let amenPurple: Color
    let amenBlue: Color
    let amenBlack: Color

    static let canonical = AmenIntelligencePalette(
        amenGold: AmenTheme.Colors.amenGold,
        amenPurple: AmenTheme.Colors.amenPurple,
        amenBlue: AmenTheme.Colors.amenBlue,
        amenBlack: AmenTheme.Colors.amenBlack
    )
}

struct AmenIntelligenceGlassStyle: Hashable, Sendable {
    var role: AmenIntelligenceGlassRole
    var prominence: AmenIntelligenceGlassProminence
    var cornerRadius: CGFloat
    var isInteractive: Bool

    static let chromeBar = AmenIntelligenceGlassStyle(
        role: .chromeBar,
        prominence: .regular,
        cornerRadius: 28,
        isInteractive: false
    )

    static let floatingBereanPanel = AmenIntelligenceGlassStyle(
        role: .floatingBereanPanel,
        prominence: .prominent,
        cornerRadius: 24,
        isInteractive: true
    )

    static let contextCapsule = AmenIntelligenceGlassStyle(
        role: .contextCapsule,
        prominence: .quiet,
        cornerRadius: 18,
        isInteractive: true
    )

    static let matteContent = AmenIntelligenceGlassStyle(
        role: .matteContent,
        prominence: .quiet,
        cornerRadius: 12,
        isInteractive: false
    )
}

struct AmenIntelligenceMatteContentModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
            }
    }
}

@available(iOS 26.0, *)
struct AmenIntelligenceGlassChromeModifier: ViewModifier {
    var style: AmenIntelligenceGlassStyle

    func body(content: Content) -> some View {
        let glass = style.isInteractive ? Glass.regular.interactive() : Glass.regular

        content
            .glassEffect(glass, in: .rect(cornerRadius: style.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: borderWidth)
            }
    }

    private var borderWidth: CGFloat {
        switch style.prominence {
        case .quiet: 0.5
        case .regular: 0.75
        case .prominent: 1.0
        }
    }
}

extension View {
    func amenIntelligenceMatteContent(cornerRadius: CGFloat = 12) -> some View {
        modifier(AmenIntelligenceMatteContentModifier(cornerRadius: cornerRadius))
    }

    @available(iOS 26.0, *)
    func amenIntelligenceGlassChrome(_ style: AmenIntelligenceGlassStyle) -> some View {
        modifier(AmenIntelligenceGlassChromeModifier(style: style))
    }
}

struct AmenIntelligenceMotionContract: Hashable, Sendable {
    var purpose: AmenIntelligenceMotionPurpose
    var duration: Double
    var reduceMotionFallbackDuration: Double

    static let panelAppear = AmenIntelligenceMotionContract(
        purpose: .panelAppear,
        duration: 0.24,
        reduceMotionFallbackDuration: 0.16
    )

    static let confirmationPreview = AmenIntelligenceMotionContract(
        purpose: .confirmationPreview,
        duration: 0.20,
        reduceMotionFallbackDuration: 0.16
    )
}

enum AmenIntelligenceMotionPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case panelAppear
    case panelDismiss
    case contextShift
    case confirmationPreview
    case navigationNudge
}
