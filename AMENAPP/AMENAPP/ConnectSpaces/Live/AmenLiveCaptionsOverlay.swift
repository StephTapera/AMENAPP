// AmenLiveCaptionsOverlay.swift
// AMEN Connect + Spaces — Live Captions Strip
// Built: 2026-06-02
//
// Must NOT use glass materials — overlay sits on top of video content and
// requires high-contrast treatment (Color.black.opacity(0.65)).

import SwiftUI

// MARK: - Caption Line

struct AmenCaptionLine: Identifiable {
    let id: UUID
    var text: String
    var speakerName: String?
    var timestamp: Date

    init(id: UUID = UUID(), text: String, speakerName: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.speakerName = speakerName
        self.timestamp = timestamp
    }
}

// MARK: - Overlay View

struct AmenLiveCaptionsOverlay: View {
    let captions: [AmenCaptionLine]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only the last 2 caption lines are shown.
    private var visibleLines: [AmenCaptionLine] {
        Array(captions.suffix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(visibleLines.enumerated()), id: \.element.id) { index, line in
                captionLine(line, isLatest: index == visibleLines.count - 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.65))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedAccessibilityText)
    }

    @ViewBuilder
    private func captionLine(_ line: AmenCaptionLine, isLatest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let speaker = line.speakerName {
                Text(speaker + ":")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }
            Text(line.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Older line fades to indicate recency — skip fade when reduce-motion is on.
        .opacity(isLatest ? 1.0 : (reduceMotion ? 0.45 : 0.45))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isLatest)
    }

    private var combinedAccessibilityText: String {
        visibleLines.map { line in
            if let speaker = line.speakerName {
                return "\(speaker): \(line.text)"
            }
            return line.text
        }.joined(separator: ". ")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()

        Image(systemName: "person.fill")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(0.05)

        VStack {
            Spacer()
            AmenLiveCaptionsOverlay(captions: [
                AmenCaptionLine(text: "…and that's what Paul means when he says we are co-heirs.", speakerName: "Pastor James"),
                AmenCaptionLine(text: "The Greek word there is synklēronómos, meaning joint inheritor.", speakerName: "Pastor James")
            ])
        }
    }
}
#endif
