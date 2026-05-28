// LinkedGlyph.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Interlocking-rings/chain mark indicating cross-community membership or sharing.
// Used on avatars, Space rows, and anywhere an external member appears.
// Import this — never re-implement. See CONTRACT_C.md for full API.

import SwiftUI

/// Interlocking-rings/chain mark indicating cross-community membership or sharing.
/// Used on avatars, Space rows, and anywhere an external member appears.
/// Import this — never re-implement.
struct LinkedGlyph: View {

    enum Size {
        case small
        case medium
        case large

        /// Font size for the SF Symbol glyph.
        var pointSize: CGFloat {
            switch self {
            case .small:  return 14
            case .medium: return 20
            case .large:  return 28
            }
        }

        /// Padding around the glyph inside the capsule background.
        var padding: EdgeInsets {
            switch self {
            case .small:  return EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5)
            case .medium: return EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
            case .large:  return EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
            }
        }
    }

    let size: Size
    var isInteractive: Bool = false
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed: Bool = false

    var body: some View {
        glyphContent
            .scaleEffect(isInteractive && !reduceMotion ? (isPressed ? 0.88 : 1.0) : 1.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
                value: isPressed
            )
            .gesture(
                isInteractive
                    ? DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in state = true }
                        .simultaneously(
                            with: TapGesture().onEnded { action?() }
                        )
                    : nil
            )
            .accessibilityLabel(
                isInteractive
                    ? "External member indicator"
                    : "Cross-community member"
            )
            .accessibilityHint(
                isInteractive
                    ? "Double-tap to view community."
                    : ""
            )
            .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    @ViewBuilder
    private var glyphContent: some View {
        Image(systemName: "link")
            .font(.system(size: size.pointSize, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.amenPurple)
            .padding(size.padding)
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(AmenTheme.Colors.surfaceChip)
                } else {
                    Capsule(style: .continuous)
                        .fill(LiquidGlassTokens.blurThin)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(AmenTheme.Colors.amenPurple.opacity(0.10))
                        }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        AmenTheme.Colors.amenPurple.opacity(0.30),
                        lineWidth: 0.5
                    )
            }
    }
}

#if DEBUG
#Preview("LinkedGlyph Sizes") {
    VStack(spacing: 16) {
        LinkedGlyph(size: .small)
        LinkedGlyph(size: .medium)
        LinkedGlyph(size: .large)
        LinkedGlyph(size: .medium, isInteractive: true, action: { print("tapped") })
    }
    .padding()
}
#endif
