import SwiftUI

// MARK: - LiquidReplyPreviewChip

/// Threads-inspired inline reply preview row, styled with AMEN Liquid Glass.
///
/// Layout: [avatar cluster] [translucent capsule pill with author + preview text]
///
/// The chip must feel embedded in the PostCard — not a separate floating widget.
/// Visual tone: calm, premium, translucent, connected to the post below it.
struct LiquidReplyPreviewChip: View {
    let preview: DynamicReplyPreview
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            if !preview.avatarURLs.isEmpty {
                DynamicAvatarCluster(urls: preview.avatarURLs)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            glassTextPill
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityHint("Double tap to open replies")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Glass Pill

    private var glassTextPill: some View {
        HStack(spacing: 4) {
            if let name = preview.authorDisplayName, !name.isEmpty {
                Text(name)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(preview.previewText)
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.footnote)
        .minimumScaleFactor(0.88)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(LiquidGlassTokens.blurRegular)
                        : AnyShapeStyle(LiquidGlassTokens.blurThin)
                )
                .opacity(reduceTransparency ? 1.0 : 0.80)
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
        }
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius * 0.4,
            y: LiquidGlassTokens.shadowSoft.y * 0.4
        )
    }

    // MARK: - Accessibility

    private var voiceOverLabel: String {
        switch preview.type {
        case .topReply, .followedReply:
            if let name = preview.authorDisplayName, !name.isEmpty {
                return "\(name) said \(preview.previewText)"
            }
            return preview.previewText

        case .prayerMomentum:
            return preview.previewText

        case .bereanInsight:
            return "Berean: \(preview.previewText)"

        case .communityPulse:
            return "Community: \(preview.previewText)"

        case .trustedCommunitySignal:
            return preview.previewText
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Chip variants") {
    VStack(alignment: .leading, spacing: 16) {
        LiquidReplyPreviewChip(preview: .previewTopReply) {}
        LiquidReplyPreviewChip(preview: .previewPrayer) {}
        LiquidReplyPreviewChip(preview: .previewBerean) {}
        LiquidReplyPreviewChip(preview: .previewPulse) {}
    }
    .padding()
    .background(Color(.systemBackground))
}
#endif
