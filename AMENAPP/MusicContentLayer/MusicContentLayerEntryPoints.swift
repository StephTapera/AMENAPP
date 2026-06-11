// MusicContentLayerEntryPoints.swift
// AMENAPP — Music Content Layer
//
// FROZEN v1.0 · 2026-06-10
// Provides non-destructive entry points for wiring the MusicContentLayer
// into existing AMEN views without modifying their internals.
//
// Pattern: ViewModifiers and standalone components that can be layered
// onto any existing view with a single .modifier() / .overlay() call.
//
// Usage in CreatePostView:
//   .modifier(PostComposerMusicLayerModifier(draftText: $postText))
//
// Usage in CommentsView:
//   CommentContextBanner(postType: .sermonNote)
//     .padding(.horizontal)

import SwiftUI

// MARK: - Feature Gate

/// Single check point for the entire MusicContentLayer feature.
/// Controlled by Remote Config flag `ff_music_content_layer`.
/// Default: false (safe — feature is invisible until flag is flipped).
struct MusicContentFeatureGate {
    static var isEnabled: Bool {
        // In v1 we read from UserDefaults so the flag can be set locally for testing.
        // Replace with your Remote Config lookup when wiring production flags:
        //   RemoteConfig.remoteConfig().configValue(forKey: "ff_music_content_layer").boolValue
        UserDefaults.standard.bool(forKey: "ff_music_content_layer")
    }
}

// MARK: - PostComposerMusicLayerModifier

/// Non-destructive ViewModifier that layers Music Attachment + Intent Detection
/// onto any post composer view.
///
/// Drop onto CreatePostView or AmenAdaptiveComposerView with:
///   `.modifier(PostComposerMusicLayerModifier(draftText: $postText))`
struct PostComposerMusicLayerModifier: ViewModifier {
    @Binding var draftText: String

    @StateObject private var intentService = SmartComposerIntentService()
    @State private var pendingAttachment: ContentAttachment?
    @State private var showAttachmentPicker = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        guard MusicContentFeatureGate.isEnabled else {
            return AnyView(content)
        }
        return AnyView(
            VStack(spacing: 0) {
                content

                // Intent suggestion chips appear below the composer body
                if !intentService.suggestedChips.isEmpty || intentService.confidence > 0.3 {
                    SmartComposerSuggestionsBar(
                        chips: intentService.suggestedChips,
                        intent: intentService.detectedIntent,
                        confidence: intentService.confidence,
                        onChipTap: { _ in /* Future: handle chip actions */ }
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.12)
                            : .spring(response: 0.3, dampingFraction: 0.8),
                        value: intentService.suggestedChips.isEmpty
                    )
                    .padding(.top, 4)
                }

                // Pending attachment preview card
                if let attachment = pendingAttachment {
                    HStack {
                        LiquidGlassAttachmentCard(
                            attachment: attachment,
                            mode: .compact
                        )
                        .frame(maxWidth: .infinity)

                        Button {
                            withAnimation(
                                reduceMotion
                                    ? .easeOut(duration: 0.12)
                                    : .spring(response: 0.25, dampingFraction: 0.85)
                            ) {
                                pendingAttachment = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                        .accessibilityLabel("Remove attachment")
                        .padding(.trailing, 8)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Music attach button row
                HStack {
                    Button {
                        showAttachmentPicker = true
                    } label: {
                        Label("Attach Music / Resource", systemImage: "music.note")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("Opens music and resource attachment picker")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showAttachmentPicker) {
                MusicAttachmentPickerView(
                    onSelect: { attachment in
                        pendingAttachment = attachment
                        showAttachmentPicker = false
                    },
                    onDismiss: {
                        showAttachmentPicker = false
                    }
                )
            }
            .onChange(of: draftText) { _, newValue in
                let attachments: [ContentAttachment] = pendingAttachment.map { [$0] } ?? []
                Task {
                    await intentService.analyzeIntent(
                        draftText: newValue,
                        attachments: attachments,
                        accountType: "personal",
                        communityContext: nil
                    )
                }
            }
        )
    }
}

// MARK: - CommentContextBanner

/// A lightweight, non-destructive banner that CommentsView can place above
/// its existing comment input to surface context-aware guidance.
///
/// Usage (add above existing comment TextField in CommentsView):
///   CommentContextBanner(postType: inferredPostType)
///
/// This does NOT replace the existing comment input — it adds a cue above it.
struct CommentContextBanner: View {
    let context: PostContextHint

    @State private var isDismissed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        guard !isDismissed && MusicContentFeatureGate.isEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: context.sfSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.tintColor)

                Text(context.guidanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Button {
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: 0.12)
                            : .spring(response: 0.25, dampingFraction: 0.85)
                    ) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Dismiss guidance")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(context.tintColor.opacity(0.06))
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(context.tintColor.opacity(0.18), lineWidth: 0.5)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        )
    }
}

/// Lightweight hint type inferred from a post's content type.
/// Separate from the heavier `CommentContentContext` in ContextAwareCommentComposer
/// so this banner can be added without pulling in the full composer.
struct PostContextHint {
    let guidanceText: String
    let sfSymbol: String
    let tintColor: Color

    static let sermonNote = PostContextHint(
        guidanceText: "Respond with care — this is a teaching discussion.",
        sfSymbol: "book.closed.fill",
        tintColor: .indigo
    )
    static let prayerRequest = PostContextHint(
        guidanceText: "This is a prayer request. Supportive words are appreciated.",
        sfSymbol: "hands.sparkles.fill",
        tintColor: .purple
    )
    static let worshipRelease = PostContextHint(
        guidanceText: "This is a worship release — share what moves you.",
        sfSymbol: "music.note",
        tintColor: .pink
    )
    static let grief = PostContextHint(
        guidanceText: "This post touches on grief. Please respond with compassion.",
        sfSymbol: "heart.fill",
        tintColor: .orange
    )
    static let testimony = PostContextHint(
        guidanceText: "This is someone's testimony. Encouragement is welcome.",
        sfSymbol: "star.fill",
        tintColor: .yellow
    )
    static let general = PostContextHint(
        guidanceText: "Keep it kind and uplifting.",
        sfSymbol: "bubble.left.fill",
        tintColor: .secondary
    )
}

// MARK: - View Extensions

extension View {
    /// Layers Music Attachment + Intent Detection onto any post composer.
    /// Gated by `ff_music_content_layer` Remote Config flag (default OFF).
    func musicContentLayer(draftText: Binding<String>) -> some View {
        modifier(PostComposerMusicLayerModifier(draftText: draftText))
    }
}

// MARK: - MusicAttachButtonStyle (reusable)

/// A small toolbar button for triggering the attachment picker.
/// Matches AMEN's existing glass pill style.
struct MusicAttachButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                Text("Music")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous).fill(Color(.systemBackground))
                } else {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            }
        }
        .accessibilityLabel("Attach music or resource")
    }
}

// MARK: - Preview

#Preview("Composer modifier (flag ON)") {
    let _ = UserDefaults.standard.set(true, forKey: "ff_music_content_layer")
    return NavigationStack {
        VStack {
            Text("Post composer content here")
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding()
                .background(Color(.systemBackground))
        }
        .musicContentLayer(draftText: .constant("Just heard an amazing sermon on John 3:16"))
        .padding()
    }
}

#Preview("Comment context banner") {
    VStack(spacing: 12) {
        CommentContextBanner(context: .sermonNote)
        CommentContextBanner(context: .prayerRequest)
        CommentContextBanner(context: .worshipRelease)
        CommentContextBanner(context: .grief)
    }
    .padding()
}
