import SwiftUI

/// Small overlay badge — used for "pinned reply", "view-once", or any secondary label on media.
/// Self-contained: apply via `.glassBadge(...)` on the parent view.
struct GlassBadge: View {
    var icon: String
    var label: String
    var tint: Color = .white
    var isVisible: Bool = true

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background { badgeBackground }
        .scaleEffect(isVisible ? 1 : 0.7, anchor: .center)
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast)
                         : .spring(response: 0.30, dampingFraction: 0.70),
            value: isVisible
        )
        .accessibilityLabel(label.isEmpty ? label : "\(label) badge")
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder private var badgeBackground: some View {
        let r = LiquidGlassTokens.capsuleRadius
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground).opacity(0.88))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }
        } else {
            Capsule(style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.75)
                }
        }
    }
}

// MARK: - Convenience overlay modifier

extension View {
    /// Pins a `GlassBadge` to the specified alignment of the modified view.
    func glassBadge(
        icon: String,
        label: String = "",
        tint: Color = .white,
        alignment: Alignment = .topTrailing,
        isVisible: Bool = true
    ) -> some View {
        overlay(alignment: alignment) {
            GlassBadge(icon: icon, label: label, tint: tint, isVisible: isVisible)
                .padding(6)
        }
    }
}
