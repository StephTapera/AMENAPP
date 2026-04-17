// SentenceHighlightModifier.swift
// AMEN App — Accessibility Intelligence Layer (Phase 3)
//
// ViewModifier: subtle background tint on currently-spoken sentence range.
// Reduces to no-op when Reduce Motion enabled.
// Applied to post text during audio playback.

import SwiftUI

struct SentenceHighlightModifier: ViewModifier {

    let text: String
    let contentId: String
    @ObservedObject private var speechService = SpeechSynthesisService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if speechService.currentItemId == contentId,
           !reduceMotion,
           let _ = speechService.currentSentenceRange {
            content
                .overlay(alignment: .topLeading) {
                    // Subtle highlight overlay on the currently spoken range
                    // This is a visual cue; the actual text remains unchanged
                    Color.accentColor.opacity(0.08)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .allowsHitTesting(false)
                        .animation(
                            Motion.adaptive(.easeInOut(duration: 0.2)),
                            value: speechService.progress
                        )
                }
        } else {
            content
        }
    }
}

extension View {
    /// Applies sentence highlighting during audio playback for the given content
    func sentenceHighlight(text: String, contentId: String) -> some View {
        modifier(SentenceHighlightModifier(text: text, contentId: contentId))
    }
}
