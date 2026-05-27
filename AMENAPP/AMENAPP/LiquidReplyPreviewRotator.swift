import SwiftUI

// MARK: - LiquidReplyPreviewRotator

/// Displays the server-selected reply preview for a post.
///
/// The client never runs a carousel or chooses a new preview over time. Presence
/// is decided at fetch, and changes crossfade only when the server writes a new
/// preview (detected via a stable contentHash of postId + type + previewText).
///
/// Gated by `AMENFeatureFlags.shared.replyPreviewRotationEnabled`. When the flag
/// is off the rotator renders nothing (EmptyView).
struct LiquidReplyPreviewRotator: View {
    let candidates: [DynamicReplyPreview]
    let onOpenReplies: (DynamicReplyPreview) -> Void
    var onLongPress: (DynamicReplyPreview) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived

    private var safeCandidates: [DynamicReplyPreview] {
        candidates
            .filter { $0.isSafe && !$0.isExpired }
            .sorted { $0.score > $1.score }
    }

    private var current: DynamicReplyPreview? {
        safeCandidates.first
    }

    /// Stable identity string for SwiftUI `.id()` — crossfade fires only when
    /// server changes the post, type, or text. Timestamp changes alone do not
    /// trigger an animation unless the content itself changes.
    private var contentHash: String? {
        guard let preview = current else { return nil }
        return "\(preview.postId)|\(preview.type.rawValue)|\(preview.previewText)"
    }

    // MARK: - Body

    var body: some View {
        guard AMENFeatureFlags.shared.replyPreviewRotationEnabled else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Group {
                if let preview = current, let hash = contentHash {
                    LiquidReplyPreviewChip(
                        preview: preview,
                        onTap: { onOpenReplies(preview) },
                        onLongPress: { onLongPress(preview) }
                    )
                    .id(hash)
                    .transition(.opacity)
                }
            }
            .frame(height: 38, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                reduceMotion ? .none : .easeInOut(duration: LiquidGlassTokens.motionFast),
                value: contentHash
            )
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rotator – 4 candidates") {
    LiquidReplyPreviewRotator(
        candidates: [
            .previewTopReply,
            .previewPrayer,
            .previewBerean,
            .previewPulse
        ]
    ) { _ in }
    .padding()
    .background(Color(.systemBackground))
}

#Preview("Rotator – no safe candidates") {
    LiquidReplyPreviewRotator(candidates: []) { _ in }
        .padding()
        .background(Color(.systemBackground))
}
#endif
