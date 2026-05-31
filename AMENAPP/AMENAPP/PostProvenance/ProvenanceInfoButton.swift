// ProvenanceInfoButton.swift
// AMENAPP/PostProvenance
//
// Small ⓘ button that can be overlaid on any post cell.
// Tapping it presents PostProvenanceSheet for the given post.
//
// Phase 3 — "Why you're seeing this" transparency feature.
// Feature-flagged under MasterRunFeatureFlags.whySeeingThis.
// When the flag is OFF this view renders nothing — zero layout impact.

import SwiftUI

// MARK: - ProvenanceInfoButton

/// A small info button (`info.circle`) that overlays a post cell.
/// Renders nothing when `MasterRunFeatureFlags.whySeeingThis` is `false`.
///
/// Usage — place inside a `ZStack` or `overlay` on any post cell:
/// ```swift
/// PostCell(post: post)
///     .overlay(alignment: .topTrailing) {
///         ProvenanceInfoButton(postId: post.id)
///             .padding(8)
///     }
/// ```
struct ProvenanceInfoButton: View {

    // MARK: Inputs

    let postId: String

    // MARK: State

    @State private var showSheet = false

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        // Feature flag gate — render nothing when the flag is OFF.
        // This must be the outermost check so the button contributes
        // zero layout space and zero hit-test area when disabled.
        if MasterRunFeatureFlags.whySeeingThis {
            buttonContent
        }
    }

    // MARK: Button content

    private var buttonContent: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSheet = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(GlassKitPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Why you're seeing this post")
        .accessibilityHint("Double tap to learn why this post is in your feed")
        .sheet(isPresented: $showSheet) {
            PostProvenanceSheet(postId: postId, isPresented: $showSheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ProvenanceInfoButton — on dark background") {
    ZStack {
        Color(red: 0.1, green: 0.1, blue: 0.15)
            .ignoresSafeArea()
        VStack(spacing: 20) {
            Text("Post cell placeholder")
                .foregroundStyle(.white)
            ProvenanceInfoButton(postId: "preview_post_001")
        }
    }
}
#endif
