// MusicContentLayerEntryPoints.swift
// AMENAPP — Music Content Layer
//
// FROZEN v1.0 · 2026-06-10
// Non-destructive entry points for wiring MusicContentLayer into existing views.
//
// Usage in CreatePostView:
//   .modifier(PostComposerMusicLayerModifier(draftText: $postText))
//
// Usage in CommentsView:
//   CommentContextBanner(context: .sermonNote)
//     .padding(.horizontal)

import SwiftUI
import FirebaseRemoteConfig

// MARK: - Feature Gate

struct MusicContentFeatureGate {
    /// Primary gate: Firebase Remote Config `ff_music_content_layer`.
    /// Default OFF (false) — flip in Firebase Console after verification.
    /// DEBUG override: set UserDefaults key "ff_music_content_layer_debug" = true locally.
    static var isEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ff_music_content_layer_debug") { return true }
        #endif
        return RemoteConfig.remoteConfig().configValue(forKey: "ff_music_content_layer").boolValue
    }
}

// MARK: - PostComposerMusicLayerModifier

struct PostComposerMusicLayerModifier: ViewModifier {
    @Binding var draftText: String

    @StateObject private var intentService = SmartComposerIntentService()
    @State private var pendingAttachment: ContentAttachment?
    @State private var showAttachmentPicker = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        guard MusicContentFeatureGate.isEnabled else { return AnyView(content) }
        return AnyView(
            VStack(spacing: 0) {
                content

                // Intent suggestion chips
                if !intentService.suggestedChips.isEmpty || intentService.confidence > 0.3 {
                    SmartComposerSuggestionsBar(
                        chips: intentService.suggestedChips,
                        intent: intentService.detectedIntent,
                        confidence: intentService.confidence,
                        onChipTap: { _ in }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.8),
                        value: intentService.suggestedChips.isEmpty
                    )
                    .padding(.top, 4)
                }

                // Pending attachment preview
                if let attachment = pendingAttachment {
                    HStack {
                        LiquidGlassAttachmentCard(attachment: attachment, mode: .compact)
                            .frame(maxWidth: .infinity)
                        Button {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.25, dampingFraction: 0.85)) {
                                pendingAttachment = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                        }
                        .accessibilityLabel("Remove attachment")
                        .padding(.trailing, 8)
                    }
                    .padding(.horizontal).padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Music attach button
                HStack {
                    Button { showAttachmentPicker = true } label: {
                        Label("Attach Music / Resource", systemImage: "music.note")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("Opens music and resource attachment picker")
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .sheet(isPresented: $showAttachmentPicker) {
                // MusicAttachmentPickerView uses @Environment(\.dismiss) to dismiss itself.
                MusicAttachmentPickerView(onSelect: { attachment in
                    pendingAttachment = attachment
                    showAttachmentPicker = false
                })
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

struct CommentContextBanner: View {
    let context: PostContextHint

    @State private var isDismissed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        guard !isDismissed && MusicContentFeatureGate.isEnabled else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 8) {
                Image(systemName: context.sfSymbol).font(.caption.weight(.semibold)).foregroundStyle(context.tintColor)
                Text(context.guidanceText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.25, dampingFraction: 0.85)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Dismiss guidance")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(context.tintColor.opacity(0.06)) }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(context.tintColor.opacity(0.18), lineWidth: 0.5) }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        )
    }
}

// MARK: - PostContextHint

struct PostContextHint {
    let guidanceText: String
    let sfSymbol: String
    let tintColor: Color

    static let sermonNote  = PostContextHint(guidanceText: "Respond with care — this is a teaching discussion.", sfSymbol: "book.closed.fill", tintColor: .indigo)
    static let prayerRequest = PostContextHint(guidanceText: "This is a prayer request. Supportive words are appreciated.", sfSymbol: "hands.sparkles.fill", tintColor: .purple)
    static let worshipRelease = PostContextHint(guidanceText: "This is a worship release — share what moves you.", sfSymbol: "music.note", tintColor: .pink)
    static let grief       = PostContextHint(guidanceText: "This post touches on grief. Please respond with compassion.", sfSymbol: "heart.fill", tintColor: .orange)
    static let testimony   = PostContextHint(guidanceText: "This is someone's testimony. Encouragement is welcome.", sfSymbol: "star.fill", tintColor: .yellow)
    static let general     = PostContextHint(guidanceText: "Keep it kind and uplifting.", sfSymbol: "bubble.left.fill", tintColor: .secondary)
}

// MARK: - View Extension

extension View {
    func musicContentLayer(draftText: Binding<String>) -> some View {
        modifier(PostComposerMusicLayerModifier(draftText: draftText))
    }
}

// MARK: - MusicAttachButton

struct MusicAttachButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                Text("Music").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary).padding(.horizontal, 10).frame(minHeight: 32)
            .background {
                if reduceTransparency { Capsule(style: .continuous).fill(Color(.systemBackground)) }
                else { Capsule(style: .continuous).fill(.ultraThinMaterial) }
            }
            .overlay { Capsule(style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.5) }
        }
        .accessibilityLabel("Attach music or resource")
    }
}

// MARK: - Previews

#Preview("Composer modifier (flag ON)") {
    let _ = UserDefaults.standard.set(true, forKey: "ff_music_content_layer_debug")
    return NavigationStack {
        VStack {
            Text("Post composer content here")
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding().background(Color(.systemBackground))
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
    }.padding()
}
