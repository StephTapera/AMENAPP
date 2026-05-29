// AMENGlassMediaTokens.swift
// AMEN App — Media-surface layout constants for the Liquid Glass design layer.
// Extends AmenGlassMetrics/AmenGlassBehavior with media-specific sizing.

import SwiftUI

enum AMENGlassMediaTokens {

    // MARK: - Action Rail (right-edge vertical icon stack)
    static let railButtonSize: CGFloat  = 48
    static let railSpacing: CGFloat     = 8
    static let railTrailingInset: CGFloat = 10

    // MARK: - Category Chips (horizontal pill strip)
    static let chipHeight: CGFloat      = 34
    static let chipHPad: CGFloat        = 14
    static let chipVPad: CGFloat        = 8
    static let chipSpacing: CGFloat     = 8
    static let chipStripHPad: CGFloat   = 16

    // MARK: - Action Sheet
    static let sheetCornerRadius: CGFloat = 28
    static let sheetHandleWidth: CGFloat  = 36
    static let sheetHandleHeight: CGFloat = 4
    static let sheetRowHeight: CGFloat    = 52
    static let sheetHPad: CGFloat         = 20

    // MARK: - Shared Glass Appearance
    // Idle frosted tint — white over bright content (iOS-Photos style)
    static let idleFrostOpacity: Double   = 0.08
    // Selected amenGold tint layered over glass surface
    static let selectedGoldOpacity: Double = 0.28
    // Border opacity
    static let strokeOpacity: Double       = 0.30
    static let selectedStrokeOpacity: Double = 0.55
}
