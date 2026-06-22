// ChurchNotesLiquidGlassMorphing.swift
// AMEN App — Signature Liquid Glass morphing behaviors for Church Notes.
// Elements morph, not appear/disappear. Interruptible spring animations.
// No .blur(radius:) — system materials only. 3-layer glass depth hierarchy.

import SwiftUI
import AVFoundation

// MARK: - Morph Namespace Key

/// Shared geometry namespace for glass morphs. Inject via @Namespace in parent views.
/// Use id: GlassMorphID.sermonCard, GlassMorphID.transcriptLine, etc.
enum GlassMorphID {
    static let sermonCard       = "glassMorph_sermonCard"
    static let transcriptLine   = "glassMorph_transcriptLine"
    static let worshipPill      = "glassMorph_worshipPill"
    static let waveformCapsule  = "glassMorph_waveformCapsule"
    static func transcript(_ id: String) -> String { "transcript_\(id)" }
}

// MARK: - Spring Presets

enum GlassMorphSpring {
    /// Primary morph spring — snappy but smooth.
    static let primary = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// Secondary detail spring — slightly bouncier for icon/text transforms.
    static let detail = Animation.interpolatingSpring(stiffness: 180, damping: 22)
    /// Dismiss spring — quick collapse.
    static let dismiss = Animation.spring(response: 0.32, dampingFraction: 0.90)
}

// MARK: - 1. Sermon Card → Player Expansion

/// Collapsible sermon card that morphs into a full-screen player sheet.
/// Parent injects `namespace` and `isExpanded` binding.
struct SermonGlassCard: View {
    let session: SermonCaptureSession
    @Binding var isExpanded: Bool
    var namespace: Namespace.ID

    var body: some View {
        if isExpanded {
            // Expanded state — full player overlay (use .fullScreenCover or ZStack in parent)
            EmptyView()
        } else {
            collapsedCard
        }
    }

    private var collapsedCard: some View {
        Button {
            withAnimation(GlassMorphSpring.primary) { isExpanded = true }
        } label: {
            HStack(spacing: 12) {
                // Waveform icon morphs into player waveform
                Image(systemName: "waveform")
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                    .matchedGeometryEffect(id: GlassMorphID.waveformCapsule, in: namespace)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.churchName ?? "Sermon Recording")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.black)
                        .matchedGeometryEffect(id: GlassMorphID.sermonCard + "_title", in: namespace)
                    Text(formatDuration(session.durationSeconds))
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                        .matchedGeometryEffect(id: GlassMorphID.sermonCard + "_time", in: namespace)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(Color(white: 0.65))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .matchedGeometryEffect(id: GlassMorphID.sermonCard, in: namespace)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Sermon Player Sheet (Expanded)

/// Full-screen glass player that the sermon card morphs into.
struct SermonGlassPlayerSheet: View {
    let session: SermonCaptureSession
    @Binding var isExpanded: Bool
    var namespace: Namespace.ID
    @State private var playbackProgress: Double = 0
    @State private var isPlaying: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Layer 1 — base glass background
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .matchedGeometryEffect(id: GlassMorphID.sermonCard, in: namespace)
                .shadow(color: Color.black.opacity(0.12), radius: 30, x: 0, y: 12)

            // Layer 2 — content
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color(white: 0.80))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                // Title region morphs from card
                VStack(spacing: 6) {
                    Text(session.churchName ?? "Sermon Recording")
                        .font(AMENFont.bold(20))
                        .foregroundColor(.black)
                        .matchedGeometryEffect(id: GlassMorphID.sermonCard + "_title", in: namespace)
                    Text(session.speakerName ?? "")
                        .font(AMENFont.regular(14))
                        .foregroundColor(Color(white: 0.50))
                }
                .padding(.top, 24)
                .padding(.bottom, 28)

                // Waveform display — morphs from collapsed icon
                WaveformGlassCapsule(amplitudes: Array(repeating: 0.5, count: 40), isActive: isPlaying)
                    .matchedGeometryEffect(id: GlassMorphID.waveformCapsule, in: namespace)
                    .frame(height: 60)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                // Progress bar
                ProgressView(value: playbackProgress)
                    .progressViewStyle(.linear)
                    .tint(.black)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)

                // Timestamps
                HStack {
                    Text(formatDuration(Int(playbackProgress * Double(session.durationSeconds))))
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                    Spacer()
                    Text(formatDuration(session.durationSeconds))
                        .font(AMENFont.regular(12))
                        .foregroundColor(Color(white: 0.55))
                        .matchedGeometryEffect(id: GlassMorphID.sermonCard + "_time", in: namespace)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                // Playback controls
                HStack(spacing: 40) {
                    Button { withAnimation(GlassMorphSpring.detail) { playbackProgress = max(0, playbackProgress - 0.1) } } label: {
                        Image(systemName: "gobackward.15")
                            .font(.systemScaled(22, weight: .light))
                            .foregroundColor(.black)
                    }
                    Button { withAnimation(GlassMorphSpring.detail) { isPlaying.toggle() } } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 58, height: 58)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.systemScaled(22, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    Button { withAnimation(GlassMorphSpring.detail) { playbackProgress = min(1, playbackProgress + 0.1) } } label: {
                        Image(systemName: "goforward.15")
                            .font(.systemScaled(22, weight: .light))
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 36)
            }

            // Dismiss button
            Button {
                withAnimation(GlassMorphSpring.dismiss) { isExpanded = false }
            } label: {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.55)))
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundColor(Color(white: 0.45))
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 16)
        }
        .padding(.horizontal, 16)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 2. Transcript Line → Expandable Note

/// A single transcript paragraph that morphs/expands into an editable note inline.
struct TranscriptLineMorphView: View {
    let paragraph: SermonCaptureSession.TimestampedParagraph
    var namespace: Namespace.ID
    @Binding var expandedID: String?
    @State private var editedText: String = ""

    private var isExpanded: Bool { expandedID == paragraph.id }

    var body: some View {
        Group {
            if isExpanded {
                expandedNote
            } else {
                collapsedLine
            }
        }
        .animation(GlassMorphSpring.primary, value: isExpanded)
    }

    private var collapsedLine: some View {
        Button {
            editedText = paragraph.text
            withAnimation(GlassMorphSpring.primary) {
                expandedID = paragraph.id
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Timestamp pill
                Text(formatTimestamp(paragraph.audioTimestampSeconds))
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    )
                    .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id) + "_ts", in: namespace)

                Text(paragraph.text)
                    .font(AMENFont.regular(14))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id) + "_text", in: namespace)

                Spacer()

                Image(systemName: "pencil")
                    .font(.systemScaled(11))
                    .foregroundColor(Color(white: 0.70))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.01))
                    .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id), in: namespace)
            )
        }
        .buttonStyle(.plain)
    }

    private var expandedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(formatTimestamp(paragraph.audioTimestampSeconds))
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    )
                    .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id) + "_ts", in: namespace)

                Spacer()

                Button {
                    withAnimation(GlassMorphSpring.dismiss) { expandedID = nil }
                } label: {
                    Text("Done")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.black)
                }
            }

            // Editable text area
            ZStack(alignment: .topLeading) {
                if editedText.isEmpty {
                    Text("Add a note...")
                        .font(AMENFont.regular(15))
                        .foregroundColor(Color(white: 0.65))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                TextEditor(text: $editedText)
                    .font(AMENFont.regular(15))
                    .foregroundColor(.black)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id) + "_text", in: namespace)
            }

            // Detected verses chips
            if !paragraph.detectedVerses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(paragraph.detectedVerses, id: \.self) { verse in
                            Text(verse)
                                .font(AMENFont.regular(12))
                                .foregroundColor(Color(white: 0.45))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.thinMaterial)
                                        .overlay(Capsule().fill(Color.white.opacity(0.55)))
                                )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .matchedGeometryEffect(id: GlassMorphID.transcript(paragraph.id), in: namespace)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func formatTimestamp(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 3. Worship Pill → Player Sheet

/// A compact worship/audio pill in the note header that expands into a mini player sheet.
struct WorshipPillMorph: View {
    let title: String
    let durationSeconds: Int
    var namespace: Namespace.ID
    @Binding var isExpanded: Bool
    @State private var progress: Double = 0
    @State private var isPlaying: Bool = false

    var body: some View {
        Group {
            if isExpanded {
                expandedPlayer
            } else {
                collapsedPill
            }
        }
    }

    private var collapsedPill: some View {
        Button {
            withAnimation(GlassMorphSpring.primary) { isExpanded = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
                    .matchedGeometryEffect(id: GlassMorphID.worshipPill + "_icon", in: namespace)
                Text(title)
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
                    .matchedGeometryEffect(id: GlassMorphID.worshipPill + "_title", in: namespace)
                Image(systemName: "chevron.up")
                    .font(.systemScaled(9))
                    .foregroundColor(Color(white: 0.65))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .matchedGeometryEffect(id: GlassMorphID.worshipPill, in: namespace)
            )
        }
        .buttonStyle(.plain)
    }

    private var expandedPlayer: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundColor(Color(white: 0.30))
                        .matchedGeometryEffect(id: GlassMorphID.worshipPill + "_icon", in: namespace)
                    Text(title)
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                        .matchedGeometryEffect(id: GlassMorphID.worshipPill + "_title", in: namespace)
                }
                Spacer()
                Button {
                    withAnimation(GlassMorphSpring.dismiss) { isExpanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundColor(Color(white: 0.55))
                }
            }

            // Mini waveform
            WaveformGlassCapsule(
                amplitudes: Array(repeating: 0.4, count: 24),
                isActive: isPlaying,
                barColor: Color(white: 0.30)
            )
            .frame(height: 32)

            // Scrubber
            Slider(value: $progress, in: 0...1)
                .tint(.black)

            // Controls
            HStack(spacing: 32) {
                Button { withAnimation(GlassMorphSpring.detail) { progress = max(0, progress - 0.1) } } label: {
                    Image(systemName: "gobackward.15")
                        .font(.systemScaled(18, weight: .light))
                        .foregroundColor(.black)
                }
                Button { withAnimation(GlassMorphSpring.detail) { isPlaying.toggle() } } label: {
                    ZStack {
                        Circle().fill(Color.black).frame(width: 44, height: 44)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                Button { withAnimation(GlassMorphSpring.detail) { progress = min(1, progress + 0.1) } } label: {
                    Image(systemName: "goforward.15")
                        .font(.systemScaled(18, weight: .light))
                        .foregroundColor(.black)
                }
            }
        }
        .padding(16)
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
                .matchedGeometryEffect(id: GlassMorphID.worshipPill, in: namespace)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
    }
}

// MARK: - 4. Waveform Glass Capsule (Recording Indicator)

/// Animated waveform capsule shown while recording is active.
/// Used as standalone pill in note header + inside expanded player.
struct WaveformGlassCapsule: View {
    let amplitudes: [Float]
    var isActive: Bool = true
    var barColor: Color = Color(white: 0.35)
    var showBackground: Bool = false

    @State private var phase: Double = 0

    var body: some View {
        Group {
            if showBackground {
                capsuleContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    )
            } else {
                capsuleContent
            }
        }
        .onAppear { if isActive { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { phase = 1 } } }
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { phase = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { phase = 0 }
            }
        }
    }

    private var capsuleContent: some View {
        HStack(spacing: 3) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { i, amplitude in
                ChurchNotesWaveformBar(
                    amplitude: amplitude,
                    index: i,
                    phase: phase,
                    isActive: isActive,
                    barColor: barColor
                )
            }
        }
    }
}

private struct ChurchNotesWaveformBar: View {
    let amplitude: Float
    let index: Int
    let phase: Double
    let isActive: Bool
    let barColor: Color

    private var animatedHeight: CGFloat {
        let base = CGFloat(amplitude)
        let modifier = 0.6 + 0.4 * sin(Double(index) * 0.5 + phase * .pi * 2)
        let value = isActive ? base * modifier : base * 0.3
        return max(3, value * 40)
    }

    var body: some View {
        Capsule()
            .fill(barColor)
            .frame(width: 2, height: animatedHeight)
            .animation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.04),
                value: phase
            )
    }
}

// MARK: - 5. Active Recording Badge

/// Small glass pill with live waveform shown in note list row when capture is active.
struct SermonCaptureLiveBadge: View {
    var namespace: Namespace.ID
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            Text("REC")
                .font(AMENFont.semiBold(10))
                .foregroundColor(Color(white: 0.35))

            WaveformGlassCapsule(
                amplitudes: Array(repeating: 0.5, count: 10),
                isActive: true,
                barColor: Color(white: 0.50)
            )
            .frame(width: 30, height: 16)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .matchedGeometryEffect(id: GlassMorphID.waveformCapsule, in: namespace)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        .onAppear { pulse = true }
    }
}

// MARK: - 6. Gesture-Driven Morph Container

/// Wraps any card in a drag-to-expand/collapse gesture layer.
/// On upward drag > 40pt, triggers expansion; downward > 40pt triggers collapse.
struct GestureMorphContainer<Content: View, Expanded: View>: View {
    @Binding var isExpanded: Bool
    var namespace: Namespace.ID
    @ViewBuilder var collapsed: () -> Content
    @ViewBuilder var expanded: () -> Expanded

    @State private var dragOffset: CGFloat = 0
    private let threshold: CGFloat = 40

    var body: some View {
        ZStack {
            if isExpanded {
                expanded()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .scale(scale: 0.94).combined(with: .opacity)
                    ))
            } else {
                collapsed()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.04).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let dy = value.translation.height
                    withAnimation(GlassMorphSpring.primary) {
                        if !isExpanded && dy < -threshold {
                            isExpanded = true
                        } else if isExpanded && dy > threshold {
                            isExpanded = false
                        }
                    }
                    dragOffset = 0
                }
        )
    }
}

// MARK: - 7. Transcript Morph List

/// Full transcript panel using TranscriptLineMorphView with coordinated expand/collapse.
struct TranscriptMorphList: View {
    let paragraphs: [SermonCaptureSession.TimestampedParagraph]
    var namespace: Namespace.ID
    @State private var expandedID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(paragraphs) { paragraph in
                TranscriptLineMorphView(
                    paragraph: paragraph,
                    namespace: namespace,
                    expandedID: $expandedID
                )
                if paragraph.id != paragraphs.last?.id {
                    Divider()
                        .padding(.leading, 44)
                        .foregroundColor(Color(white: 0.92))
                }
            }
        }
    }
}

// MARK: - Preview

struct ChurchNotesLiquidGlassMorphing_Previews: PreviewProvider {
    @Namespace static var ns

    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Waveform capsule standalone
                WaveformGlassCapsule(
                    amplitudes: Array(stride(from: 0, to: 1, by: 0.05).map { Float($0) }),
                    isActive: true,
                    showBackground: true
                )
                .frame(height: 40)
                .padding(.horizontal, 24)

                // Live badge
                SermonCaptureLiveBadge(namespace: ns)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                // Transcript morph list sample
                TranscriptMorphList(
                    paragraphs: [
                        SermonCaptureSession.TimestampedParagraph(
                            text: "The fear of the Lord is the beginning of wisdom.",
                            audioTimestampSeconds: 120,
                            detectedVerses: ["Proverbs 9:10"]
                        ),
                        SermonCaptureSession.TimestampedParagraph(
                            text: "Paul writes to the church at Philippi with joy despite his imprisonment.",
                            audioTimestampSeconds: 340,
                            detectedVerses: ["Philippians 1:3", "Philippians 4:4"]
                        ),
                    ],
                    namespace: ns
                )
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 24)
        }
        .background(Color.white)
    }
}
