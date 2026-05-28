// LinkedCommunityGlyph.swift
// AMENAPP — Spaces v2 Shared Components (Agent C)
//
// Canonical cross-community badge for the CONTRACT_C public API.
// Wraps LinkedGlyph with the spec-defined parameter surface.
// Import this name — B/D/E/F never re-implement.
// See CONTRACT_C.md for the full API.

import SwiftUI

/// Interlocking-rings/chain badge indicating cross-community membership or sharing.
/// amenPurple glyph over ultraThinMaterial. Tappable when `onTap` is provided.
///
/// Usage:
/// ```swift
/// LinkedCommunityGlyph(size: 22, communityName: "Hillside Community") {
///     showCommunityDetail()
/// }
/// ```
struct LinkedCommunityGlyph: View {

    // MARK: - Parameters (CONTRACT_C public API)

    /// Point size for the SF Symbol.  Pass 14 (small), 20 (medium), or 28 (large).
    let size: CGFloat

    /// Display name of the linked community — shown in the popover label.
    let communityName: String

    /// If non-nil, the glyph is tappable and shows a popover on tap.
    var onTap: (() -> Void)?

    // MARK: - Private state

    @State private var showPopover: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @GestureState private var isPressed: Bool = false

    // MARK: - Body

    var body: some View {
        glyphContent
            .scaleEffect(onTap != nil && !reduceMotion ? (isPressed ? 0.88 : 1.0) : 1.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : Motion.liquidSpring,
                value: isPressed
            )
            .gesture(
                onTap != nil
                    ? DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in state = true }
                        .simultaneously(
                            with: TapGesture().onEnded {
                                showPopover = true
                                onTap?()
                            }
                        )
                    : nil
            )
            .popover(isPresented: $showPopover) {
                communityPopover
            }
            .accessibilityLabel("Shared community")
            .accessibilityHint(onTap != nil ? "Tap to see details" : "")
            .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    // MARK: - Glyph content

    @ViewBuilder
    private var glyphContent: some View {
        let padding: EdgeInsets = {
            if size <= 14 { return EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5) }
            if size <= 20 { return EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8) }
            return EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
        }()

        Image(systemName: "link")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.amenPurple)
            .padding(padding)
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

    // MARK: - Popover

    private var communityPopover: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
            Text("Shared with \(communityName)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .presentationCompactAdaptation(.popover)
    }
}

#if DEBUG
#Preview("LinkedCommunityGlyph") {
    VStack(spacing: 20) {
        LinkedCommunityGlyph(size: 14, communityName: "Hillside Community")
        LinkedCommunityGlyph(size: 20, communityName: "Grace Fellowship")
        LinkedCommunityGlyph(size: 28, communityName: "Cornerstone", onTap: { print("tapped") })
    }
    .padding()
}
#endif
