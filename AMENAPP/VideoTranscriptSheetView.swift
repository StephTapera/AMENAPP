// VideoTranscriptSheetView.swift
// AMEN App — Glass bottom sheet for sermon/teaching video transcripts,
// key moments, and personal notes. iOS-only sheet APIs.

import SwiftUI

// MARK: - Models

struct TranscriptSegment: Identifiable {
    let id: String
    let offsetSeconds: TimeInterval
    let text: String
    let isKeyMoment: Bool
    let detectedVerses: [String]
}

struct VideoKeyMoment: Identifiable {
    let id: String
    let title: String
    let offsetSeconds: TimeInterval
    let type: KeyMomentType

    enum KeyMomentType: String {
        case scripture
        case mainPoint
        case storySummary
        case callToAction
        case prayer
    }
}

// MARK: - Tab Enum

enum TranscriptTab: String, CaseIterable {
    case transcript   = "Transcript"
    case keyMoments   = "Key Moments"
    case notes        = "Notes"
}

// MARK: - VideoTranscriptSheetView

struct VideoTranscriptSheetView: View {
    let videoTitle: String
    let preacherName: String
    let segments: [TranscriptSegment]
    let keyMoments: [VideoKeyMoment]
    let onJumpTo: (TimeInterval) -> Void
    let onSaveNote: (String) -> Void

    @State private var activeTab: TranscriptTab = .transcript
    @State private var noteText: String = ""
    @State private var savedNotes: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Sheet background
                Color(white: 0.97).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    sheetHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Segmented tab control ─────────────────────────────────
                    glassSegmentedControl
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    // ── Tab content ───────────────────────────────────────────
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            switch activeTab {
                            case .transcript:
                                transcriptTabContent
                            case .keyMoments:
                                keyMomentsTabContent
                            case .notes:
                                notesTabContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(videoTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)

                Text(preacherName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.black.opacity(0.50))
            }

            Spacer()

            // Dismiss X
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.60))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: - Glass Segmented Control

    private var glassSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(TranscriptTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTab == tab ? Color.white : Color.black.opacity(0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if activeTab == tab {
                                Capsule().fill(Color.black)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                        .background {
                            if activeTab != tab {
                                Capsule().fill(Color.white.opacity(0.55))
                            }
                        }
                        .overlay {
                            if activeTab != tab {
                                Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Transcript Tab

    private var transcriptTabContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(segments) { segment in
                transcriptSegmentRow(segment)
            }
        }
        .padding(.top, 4)
    }

    private func transcriptSegmentRow(_ segment: TranscriptSegment) -> some View {
        Button {
            onJumpTo(segment.offsetSeconds)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Key moment amber accent bar
                if segment.isKeyMoment {
                    Rectangle()
                        .fill(Color.orange.opacity(0.5))
                        .frame(width: 2)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // Timestamp pill
                        Text(formatTimestamp(segment.offsetSeconds))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.70))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                            )

                        if segment.isKeyMoment {
                            Text("Key moment")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.80))
                        }
                    }

                    // Segment text
                    Text(segment.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.black.opacity(0.80))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Detected verse pills
                    if !segment.detectedVerses.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(segment.detectedVerses, id: \.self) { verse in
                                    HStack(spacing: 4) {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.black.opacity(0.55))
                                        Text(verse)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.black.opacity(0.65))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                segment.isKeyMoment
                                    ? Color.orange.opacity(0.3)
                                    : Color(white: 0.88).opacity(0.5),
                                lineWidth: segment.isKeyMoment ? 1.0 : 0.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Moments Tab

    private var keyMomentsTabContent: some View {
        LazyVStack(spacing: 10) {
            ForEach(keyMoments) { moment in
                keyMomentCard(moment)
            }
        }
        .padding(.top, 4)
    }

    private func keyMomentCard(_ moment: VideoKeyMoment) -> some View {
        HStack(spacing: 14) {
            // Type icon circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .frame(width: 40, height: 40)

                Image(systemName: keyMomentIcon(moment.type))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(keyMomentColor(moment.type))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(moment.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)

                Text(formatTimestamp(moment.offsetSeconds))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.45))
            }

            Spacer()

            // Jump to button
            Button {
                onJumpTo(moment.offsetSeconds)
            } label: {
                Text("Jump to")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    )
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: - Notes Tab

    private var notesTabContent: some View {
        VStack(spacing: 12) {
            // Saved notes list
            if !savedNotes.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(Array(savedNotes.enumerated()), id: \.offset) { _, note in
                        savedNoteCard(note)
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.black.opacity(0.25))

                    Text("No notes yet")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.black.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }

            // Note input area
            noteInputArea
        }
        .padding(.top, 4)
    }

    private func savedNoteCard(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(note)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.black.opacity(0.80))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Copy button
            Button {
                #if os(iOS)
                UIPasteboard.general.string = note
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.40))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var noteInputArea: some View {
        VStack(spacing: 10) {
            // Text input
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .frame(minHeight: 90)

                if noteText.isEmpty {
                    Text("Write a note from this clip…")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.black.opacity(0.30))
                        .padding(.top, 12)
                        .padding(.horizontal, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $noteText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.black.opacity(0.80))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 90)
            }

            // Save Note button
            Button {
                let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    savedNotes.insert(trimmed, at: 0)
                    onSaveNote(trimmed)
                    noteText = ""
                }
            } label: {
                Text("Save Note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .fill(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? Color.black.opacity(0.25)
                                  : Color.black)
                    )
            }
            .buttonStyle(.plain)
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: noteText)
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func keyMomentIcon(_ type: VideoKeyMoment.KeyMomentType) -> String {
        switch type {
        case .scripture:     return "book.fill"
        case .mainPoint:     return "lightbulb.fill"
        case .storySummary:  return "text.bubble.fill"
        case .callToAction:  return "arrow.forward.circle.fill"
        case .prayer:        return "hands.sparkles.fill"
        }
    }

    private func keyMomentColor(_ type: VideoKeyMoment.KeyMomentType) -> Color {
        switch type {
        case .scripture:     return .black.opacity(0.75)
        case .mainPoint:     return Color.blue.opacity(0.75)
        case .storySummary:  return .black.opacity(0.60)
        case .callToAction:  return Color.blue.opacity(0.65)
        case .prayer:        return Color(hue: 0.09, saturation: 0.6, brightness: 0.75).opacity(0.85)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct VideoTranscriptSheetView_Previews: PreviewProvider {
    static let sampleSegments: [TranscriptSegment] = [
        TranscriptSegment(
            id: "s1",
            offsetSeconds: 12,
            text: "Today we're going to talk about the peace that surpasses all understanding — the kind of peace that holds you steady even in the storm.",
            isKeyMoment: false,
            detectedVerses: ["Philippians 4:7"]
        ),
        TranscriptSegment(
            id: "s2",
            offsetSeconds: 45,
            text: "Jesus said 'Peace I leave with you, my peace I give you. Not as the world gives do I give to you.' That word peace here — shalom — means completeness. Wholeness.",
            isKeyMoment: true,
            detectedVerses: ["John 14:27"]
        ),
        TranscriptSegment(
            id: "s3",
            offsetSeconds: 112,
            text: "So how do we access that peace? Paul tells us in Philippians — through prayer, through thanksgiving, through bringing every anxious thought to God.",
            isKeyMoment: false,
            detectedVerses: ["Philippians 4:6", "Philippians 4:7"]
        )
    ]

    static let sampleKeyMoments: [VideoKeyMoment] = [
        VideoKeyMoment(
            id: "k1",
            title: "The meaning of shalom",
            offsetSeconds: 45,
            type: .scripture
        ),
        VideoKeyMoment(
            id: "k2",
            title: "Three steps to access peace",
            offsetSeconds: 112,
            type: .mainPoint
        )
    ]

    static var previews: some View {
        Text("Transcript Sheet")
            .sheet(isPresented: .constant(true)) {
                VideoTranscriptSheetView(
                    videoTitle: "Peace That Passes Understanding",
                    preacherName: "Pastor Marcus Webb",
                    segments: sampleSegments,
                    keyMoments: sampleKeyMoments,
                    onJumpTo: { offset in
                        print("Jump to: \(offset)s")
                    },
                    onSaveNote: { note in
                        print("Saved note: \(note)")
                    }
                )
            }
            .previewDisplayName("Video Transcript Sheet")
    }
}
#endif
