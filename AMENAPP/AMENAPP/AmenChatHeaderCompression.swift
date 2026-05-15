// AmenChatHeaderCompression.swift
// AMENAPP
//
// Current state: UnifiedChatView's liquidGlassHeader already uses
// SoftStickyHeaderModifier driven by headerSofteningProgress (scrollOffset / 80).
// That modifier reduces header opacity 0–12% and adds a white backing as content
// scrolls behind it.
//
// Future: messagingFloatingHeaderPrototypeEnabled (default OFF) will replace the
// system nav bar with a detached floating capsule that compresses its avatar stack,
// status text, and action buttons on scroll. Implementation deferred.
//
// This file provides AmenHeaderCompressionState — a composable value type that
// expresses scroll-driven compression progress. Ready for the prototype build.

import SwiftUI

/// Composable compression state for the chat header.
/// Derive from the scroll view's PreferenceKey offset value.
struct AmenHeaderCompressionState {
    let scrollOffset: CGFloat

    /// 0 = fully expanded, 1 = fully compressed.
    var progress: CGFloat {
        min(max(-scrollOffset / 80, 0), 1)
    }

    var isActive: Bool { progress > 0.01 }

    /// Avatar scale: 1.0 → 0.82 as header compresses.
    var avatarScale: CGFloat { 1.0 - 0.18 * progress }

    /// Title opacity: 1.0 → 0.75 as header compresses.
    var titleOpacity: CGFloat { 1.0 - 0.25 * progress }
}
