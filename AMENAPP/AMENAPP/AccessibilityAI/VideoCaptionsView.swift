// VideoCaptionsView.swift
// AMEN Universal Accessibility Engine — A1 Caption Overlay + Chapter Navigator
// Phase 2: Real-time word-window captions and chapter navigation for video content.

import SwiftUI

// MARK: - Caption Style

struct CaptionStyle: Equatable {
    var fontSize: CGFloat = 16
    var fontWeight: String = "regular"       // "regular", "medium", "bold"
    var backgroundColor: String = "dark"     // "black", "dark", "none"
    var showNonSpeech: Bool = true

    static let standard = CaptionStyle()
    static let highContrast = CaptionStyle(
        fontSize: 18, fontWeight: "bold", backgroundColor: "black", showNonSpeech: true
    )
    static let minimal = CaptionStyle(
        fontSize: 14, fontWeight: "regular", backgroundColor: "none", showNonSpeech: false
    )
}

// MARK: - Caption Background Helper

private extension CaptionStyle {
    var resolvedBackgroundColor: Color {
        switch backgroundColor {
        case "black":  return Color.black.opacity(0.85)
        case "dark":   return Color.black.opacity(0.60)
        case "none":   return Color.clear
        default:       return Color.black.opacity(0.60)
        }
    }

    var resolvedFontWeight: Font.Weight {
        switch fontWeight {
        case "bold":   return .bold
        case "medium": return .medium
        default:       return .regular
        }
    }
}

// MARK: - VideoCaptionsOverlay

/// Drop this overlay onto a video player view.
/// Pass `currentTimeMs` from the player's time observer so captions stay in sync.
struct VideoCaptionsOverlay: View {
    let transcript: TranscriptionResult?
    let currentTimeMs: Int

    /// If no profile is supplied the standard caption style is used.
    var captionStyle: CaptionStyle = .standard

    // ±500 ms window around the current playback position
    private static let windowMs = 500

    private var currentWords: [String] {
        guard let transcript else { return [] }
        return transcript.wordTimings
            .filter { timing in
                timing.startMs <= currentTimeMs + Self.windowMs &&
                timing.endMs   >= currentTimeMs - Self.windowMs
            }
            .map(\.word)
    }

    private var currentAnnotation: String? {
        guard let transcript, captionStyle.showNonSpeech else { return nil }
        // Show a non-speech annotation whenever there are no spoken words in the window
        guard currentWords.isEmpty else { return nil }
        // Find the annotation whose implied timing bracket overlaps the current position.
        // Annotations are stored as plain strings without explicit timestamps; we surface
        // them when there is no active speech in the window so they appear as fill-in cues.
        return transcript.nonSpeechAnnotations.first
    }

    var body: some View {
        // Only render when the feature is enabled
        if TrustAccessibilityFeatureFlags.shared.a11yTranscribeEnabled {
            GeometryReader { geo in
                VStack {
                    Spacer()
                    captionBubble
                        .padding(.bottom, geo.size.height * 0.20)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var captionBubble: some View {
        let text: String? = currentWords.isEmpty ? currentAnnotation : currentWords.joined(separator: " ")

        if let displayText = text, !displayText.isEmpty {
            Text(displayText)
                .font(.system(size: captionStyle.fontSize, weight: captionStyle.resolvedFontWeight))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(captionStyle.resolvedBackgroundColor)
                )
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(displayText))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: displayText)
        }
    }
}

// MARK: - TranscriptChaptersView

/// A scrollable list of chapters from a TranscriptionResult.
/// Tapping a chapter fires `onSelectChapter` so the caller can seek the player.
struct TranscriptChaptersView: View {
    let chapters: [TranscriptChapter]
    let onSelectChapter: (TranscriptChapter) -> Void

    var body: some View {
        List(chapters, id: \.startMs) { chapter in
            Button {
                onSelectChapter(chapter)
            } label: {
                ChapterRowView(chapter: chapter)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text("Chapter: \(chapter.title), starts at \(formattedTime(chapter.startMs))")
            )
            .accessibilityHint(Text("Double-tap to jump to this chapter"))
        }
        .listStyle(.plain)
    }

    private func formattedTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Chapter Row

private struct ChapterRowView: View {
    let chapter: TranscriptChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chapter.title)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formattedTime(chapter.startMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(chapter.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func formattedTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
