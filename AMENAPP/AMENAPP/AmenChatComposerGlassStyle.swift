// AmenChatComposerGlassStyle.swift
// AMENAPP
//
// Subtle focus-glow modifier for the chat composer bar.
// Adds a soft white inner shadow when the text field is focused.
// Additive only — does not conflict with composerCompression or scroll-driven scale.

import SwiftUI

struct AmenComposerFocusGlassModifier: ViewModifier {
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .shadow(
                color: .white.opacity(isFocused && !reduceTransparency ? 0.40 : 0),
                radius: 5,
                y: -2
            )
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .spring(response: 0.32, dampingFraction: 0.72),
                value: isFocused
            )
    }
}

extension View {
    func amenComposerFocusGlass(isFocused: Bool) -> some View {
        modifier(AmenComposerFocusGlassModifier(isFocused: isFocused))
    }
}
