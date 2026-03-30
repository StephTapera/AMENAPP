// AnimationTokens.swift
// AMEN App — Shared animation tokens for Liquid Glass design language

import SwiftUI

// ─── MARK: Animation Tokens ──────────────────────────────────────────────────

extension Animation {
    /// Standard spring for most transitions — composer lift, chip tap, bubble entry
    static let amenSpringStandard = Animation
        .spring(response: 0.45, dampingFraction: 0.70)

    /// Slightly bouncier spring for action chip stagger and tap feedback
    static let amenSpringBouncy = Animation
        .spring(response: 0.4, dampingFraction: 0.64)

    /// Entry spring — view appears, composer slides in from below
    static let amenSpringEntry = Animation
        .spring(response: 0.5, dampingFraction: 0.72)

    /// Quick ease for state switches (active chip color, icon swap)
    static let amenEaseQuick = Animation
        .easeInOut(duration: 0.18)

    /// Medium ease for paywall banner, mode pill text transitions
    static let amenEaseMedium = Animation
        .easeInOut(duration: 0.28)
}

// ─── MARK: Design Tokens ─────────────────────────────────────────────────────

enum AmenRadius {
    static let chip: CGFloat     = 100   // pill-shaped chips
    static let composer: CGFloat = 28    // large composer card
    static let bubble: CGFloat   = 18    // message bubbles
    static let button: CGFloat   = 100   // circular quick-action buttons
    static let modePill: CGFloat = 100   // mode/context pill
    static let card: CGFloat     = 20    // glass card surfaces
}

enum AmenOpacity {
    static let glassFill: CGFloat       = 0.72  // base glass fill (idle)
    static let glassFillFocused: CGFloat = 0.90  // elevated glass (focused)
    static let glassBorder: CGFloat     = 0.22  // glass border
    static let shadowIdle: CGFloat      = 0.07  // shadow idle
    static let shadowFocused: CGFloat   = 0.13  // shadow focused
    static let placeholderText: CGFloat = 0.35  // placeholder color
    static let supportText: CGFloat     = 0.55  // support / secondary text
}

enum AmenSpacing {
    static let chipH: CGFloat         = 14
    static let chipV: CGFloat         = 9
    static let composerH: CGFloat     = 18
    static let composerV: CGFloat     = 16
    static let quickActionSize: CGFloat = 34
    static let sectionGap: CGFloat    = 16
}

enum AmenColor {
    static let background       = Color(red: 0.973, green: 0.969, blue: 0.961) // #F8F7F5
    static let surface          = Color.white
    static let titleText        = Color(red: 0.08, green: 0.08, blue: 0.08)    // near-black
    static let bodyText         = Color(red: 0.25, green: 0.25, blue: 0.27)    // charcoal
    static let mutedText        = Color(red: 0.52, green: 0.52, blue: 0.54)    // muted gray
    static let userBubble       = Color(red: 0.08, green: 0.08, blue: 0.08)    // black bubble
    static let userBubbleText   = Color.white
    static let bereanBubble     = Color.white
    static let bereanBubbleText = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let accent           = Color(red: 0.788, green: 0.659, blue: 0.298) // AMEN gold
    static let accentMuted      = Color(red: 0.788, green: 0.659, blue: 0.298).opacity(0.15)
    static let chipActive       = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let chipActiveText   = Color.white
    static let border           = Color.white.opacity(AmenOpacity.glassBorder)
    static let divider          = Color.black.opacity(0.06)
}
