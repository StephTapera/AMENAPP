// AMENMediaViewer.swift
// AMEN App — Immersive Liquid Glass media viewer.
//
// AMENImmersiveMediaViewer wraps the existing FullscreenMediaViewer and adds:
//   • AMENActionRail   — right-edge vertical action buttons
//   • AMENActionSheet  — glass bottom sheet (triggered by "more" in the rail)
//
// Usage: replace fullScreenCover { FullscreenMediaViewer(...) }
// with   fullScreenCover { AMENImmersiveMediaViewer(...) }
// when AMENFeatureFlags.shared.liquidGlassMediaViewer is true.

import SwiftUI

// MARK: - AMENImmersiveMediaViewer

struct AMENImmersiveMediaViewer: View {
    let media: PostMediaContainer
    let startIndex: Int
    var postId: String? = nil

    // Rail action counts / states
    var likeCount:    Int  = 0
    var commentCount: Int  = 0
    var shareCount:   Int  = 0
    var isLiked:  Bool = false
    var isSaved:  Bool = false

    // Rail action callbacks
    var onLike:    (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onShare:   (() -> Void)? = nil
    var onSave:    (() -> Void)? = nil

    // Action sheet items (caller supplies contextual list)
    var actionItems: [AMENActionSheetItem] = []
    var actionChips: [AMENCategoryChip]    = []
    var onChipSelected: ((String?) -> Void)? = nil

    @State private var showActions = false
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        ZStack(alignment: .trailing) {
            // Base viewer — all existing zoom / swipe / chrome logic unchanged
            FullscreenMediaViewer(
                media:      media,
                startIndex: startIndex,
                postId:     postId
            )

            // Action rail — anchored to the right edge, vertically centered
            AMENActionRail(
                likeCount:    likeCount,
                commentCount: commentCount,
                shareCount:   shareCount,
                isLiked:      isLiked,
                isSaved:      isSaved,
                onLike:    onLike,
                onComment: onComment,
                onShare:   onShare,
                onSave:    onSave,
                onMore:    { showActions = true }
            )
            .padding(.trailing, AMENGlassMediaTokens.railTrailingInset)
            // Keep rail clear of the home indicator
            .safeAreaPadding(.bottom, 60)
        }
        .sheet(isPresented: $showActions) {
            AMENActionSheet(
                items:          actionItems,
                chips:          flags.liquidGlassCategoryChips ? actionChips : [],
                onChipSelected: onChipSelected
            )
        }
    }
}

// MARK: - Preview

#Preview {
    Text("AMENImmersiveMediaViewer — run on device with a real PostMediaContainer.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
}
