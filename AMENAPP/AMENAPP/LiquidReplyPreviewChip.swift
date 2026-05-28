import SwiftUI

struct LiquidReplyPreviewTint: Equatable {
    let overlayColor: Color
    let overlayOpacity: Double
    let strokeOpacity: Double

    static func style(for type: ReplyPreviewType, reduceTransparency: Bool) -> LiquidReplyPreviewTint {
        let tintOpacity = reduceTransparency ? 0.0 : 0.12

        switch type {
        case .topReply, .followedReply:
            return LiquidReplyPreviewTint(
                overlayColor: .white,
                overlayOpacity: reduceTransparency ? 0 : 0.02,
                strokeOpacity: 0.20
            )
        case .prayerMomentum:
            return LiquidReplyPreviewTint(
                overlayColor: Color(red: 0.86, green: 0.92, blue: 1.0),
                overlayOpacity: tintOpacity,
                strokeOpacity: 0.22
            )
        case .bereanInsight:
            return LiquidReplyPreviewTint(
                overlayColor: Color(red: 0.92, green: 0.88, blue: 1.0),
                overlayOpacity: tintOpacity,
                strokeOpacity: 0.22
            )
        case .communityPulse:
            return LiquidReplyPreviewTint(
                overlayColor: Color(red: 1.0, green: 0.94, blue: 0.82),
                overlayOpacity: tintOpacity,
                strokeOpacity: 0.22
            )
        case .trustedCommunitySignal:
            return LiquidReplyPreviewTint(
                overlayColor: Color(red: 0.87, green: 0.96, blue: 0.89),
                overlayOpacity: tintOpacity,
                strokeOpacity: 0.22
            )
        }
    }
}

// MARK: - LiquidReplyPreviewChip

/// Threads-inspired inline reply preview row, styled with AMEN Liquid Glass.
///
/// Layout: [avatar cluster / type icon] [translucent capsule pill with author + preview text]
///
/// The chip must feel embedded in the PostCard — not a separate floating widget.
/// Visual tone: calm, premium, translucent, connected to the post below it.
struct LiquidReplyPreviewChip: View {
    let preview: DynamicReplyPreview
    let onTap: () -> Void
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            leadingVisual
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            glassTextPill
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AMENAnalyticsService.shared.track(
                .replyPreviewTapped(
                    postId: preview.postId,
                    type: preview.type.rawValue,
                    replyId: preview.replyId ?? ""
                )
            )
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            AMENAnalyticsService.shared.track(
                .replyPreviewShown(postId: preview.postId, type: preview.type.rawValue)
            )
            AMENAnalyticsService.shared.track(
                .replyPreviewType(type: preview.type.rawValue)
            )
        }
    }

    // MARK: - Leading Visual

    @ViewBuilder
    private var leadingVisual: some View {
        switch preview.type {
        case .followedReply, .topReply:
            if !preview.avatarURLs.isEmpty {
                DynamicAvatarCluster(urls: preview.avatarURLs)
            }
        case .bereanInsight:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .frame(width: 28, height: 28)
        default:
            if !preview.avatarURLs.isEmpty {
                DynamicAvatarCluster(urls: preview.avatarURLs)
            }
        }
    }

    // MARK: - Glass Pill

    private var glassTextPill: some View {
        let tint = LiquidReplyPreviewTint.style(for: preview.type, reduceTransparency: reduceTransparency)
        return HStack(spacing: 4) {
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
                .fill(reduceTransparency ? AnyShapeStyle(LiquidGlassTokens.blurRegular) : AnyShapeStyle(LiquidGlassTokens.blurThin))
                .opacity(reduceTransparency ? 1.0 : 0.84)
                .overlay {
                    Capsule()
                        .fill(tint.overlayColor.opacity(tint.overlayOpacity))
                }
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
        }
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 14,
            y: 6
        )
    }

    // MARK: - Accessibility

    private var voiceOverLabel: String {
        let name = preview.authorDisplayName ?? ""
        let text = preview.previewText

        switch preview.type {
        case .topReply, .followedReply:
            if !name.isEmpty {
                return "Reply from \(name): \(text). Double-tap to open thread."
            }
            return "Reply: \(text). Double-tap to open thread."
        case .prayerMomentum:
            return "Reply: \(text). Double-tap to open thread."
        case .bereanInsight:
            return "Reply from Berean: \(text). Double-tap to open thread."
        case .communityPulse:
            return "Reply from Community: \(text). Double-tap to open thread."
        case .trustedCommunitySignal:
            return "Reply: \(text). Double-tap to open thread."
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
