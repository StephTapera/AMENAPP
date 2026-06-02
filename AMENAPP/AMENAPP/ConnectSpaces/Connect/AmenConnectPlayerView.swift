// AmenConnectPlayerView.swift
// AMEN Connect
//
// Immersive teaching video player.
// Aegis rules enforced:
//   - syntheticMediaLabelsNonRemovable: AmenSyntheticMediaLabelView always visible
//   - noScriptureWithoutProvenance: scripture refs only rendered when
//     verified (scriptureRefs from contract always carry provenance); empty → stub message

import SwiftUI
import AVKit

// MARK: - Stub chapter model

private struct ConnectChapter: Identifiable {
    let id: Int
    let title: String
}

private let defaultChapters: [ConnectChapter] = [
    ConnectChapter(id: 0, title: "Introduction"),
    ConnectChapter(id: 1, title: "Main Teaching"),
    ConnectChapter(id: 2, title: "Application"),
    ConnectChapter(id: 3, title: "Prayer")
]

// MARK: - View

struct AmenConnectPlayerView: View {
    let video: AmenConnectSpacesConnectVideo

    @State private var player: AVPlayer = AVPlayer()
    @State private var showTranscript = false
    @State private var showContextSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Provenance summary string (passed to glass controls badge)
    private var provenanceSummary: String {
        let p = video.provenance
        if p.deepfakeRisk > 0.7 { return "High deepfake risk" }
        if p.synthFace            { return "Synthetic face" }
        if p.synthVoice           { return "Synthetic voice" }
        if p.aiGenerated          { return "AI-Generated" }
        if p.humanRecorded && p.aiEdited { return "Human · AI-Edited" }
        if p.humanRecorded        { return "Human Original" }
        return "Provenance Unknown"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Video area — MATTE black (#070607), never glass-on-glass
                ZStack(alignment: .top) {
                    videoRegion

                    // MARK: Synthetic media label — NON-REMOVABLE, shown above video title
                    // (Aegis rule: syntheticMediaLabelsNonRemovable)
                    VStack {
                        HStack {
                            Spacer()
                            AmenSyntheticMediaLabelView(provenance: video.provenance)
                                .padding(10)
                        }
                        Spacer()
                    }
                }

                // MARK: Below player (matte) — all content on matte background
                VStack(alignment: .leading, spacing: 24) {

                    // Chapter list
                    chapterList

                    // Transcript toggle
                    transcriptSection

                    // Scripture references
                    scriptureSection
                }
                .padding(16)
                .background(Color(hex: "070607"))
            }
        }
        .background(Color(hex: "070607").ignoresSafeArea())
        .sheet(isPresented: $showContextSheet) {
            NavigationStack {
                AmenConnectContextBeforeWatchingView(video: video) {
                    showContextSheet = false
                }
                .navigationTitle("About this video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showContextSheet = false }
                    }
                }
            }
        }
    }

    // MARK: Video region (MATTE)

    @ViewBuilder
    private var videoRegion: some View {
        ZStack {
            // Matte background — #070607
            Color(hex: "070607")

            // AVKit VideoPlayer
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)

            // Glass controls overlay floats above the matte video
            AmenConnectGlassControlsView(
                player: player,
                chapterCount: defaultChapters.count,
                provenanceSummary: provenanceSummary,
                onTranscriptToggle: { isOn in
                    withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.30, dampingFraction: 0.80)) {
                        showTranscript = isOn
                    }
                },
                onContextSheetToggle: { isOn in
                    showContextSheet = isOn
                }
            )
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }

    // MARK: Chapter list

    @ViewBuilder
    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CHAPTERS")
            VStack(spacing: 6) {
                ForEach(defaultChapters) { chapter in
                    HStack(spacing: 10) {
                        Text("\(chapter.id + 1)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(hex: "D9A441"))
                            .frame(width: 22, alignment: .center)
                        Text(chapter.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.80))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.30))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Chapter \(chapter.id + 1): \(chapter.title)")
                }
            }
        }
    }

    // MARK: Transcript toggle

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.80)) {
                    showTranscript.toggle()
                }
            } label: {
                HStack {
                    sectionHeader("TRANSCRIPT")
                    Spacer()
                    Image(systemName: showTranscript ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
            }
            .accessibilityLabel("Transcript: \(showTranscript ? "expanded" : "collapsed")")

            if showTranscript {
                Text("Transcript is not yet available for this video. Check back after processing is complete.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
            }
        }
    }

    // MARK: Scripture references
    // Aegis rule: noScriptureWithoutProvenance
    // Only references from video.scriptureRefs (which carry full AmenConnectSpacesScriptureRefProvenance)
    // are rendered. If the list is empty, we show a stub — never show unverified refs.

    @ViewBuilder
    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("VERIFIED SCRIPTURE REFERENCES")

            if video.scriptureRefs.isEmpty {
                Text("No scripture verified yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(video.scriptureRefs) { ref in
                        scriptureRefRow(ref)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scriptureRefRow(_ ref: AmenConnectSpacesScriptureRefProvenance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // Reference + translation
                HStack(spacing: 6) {
                    Text(ref.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text(ref.translation)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "D9A441").opacity(0.15))
                        .clipShape(Capsule())
                }

                // Confidence
                Text(String(format: "%.0f%% confidence", ref.confidence * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            // Provenance layer badge
            provenanceLayerBadge(ref.sourceLayer)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ref.reference) \(ref.translation), \(Int(ref.confidence * 100)) percent confidence, source: \(ref.sourceLayer.rawValue)")
    }

    @ViewBuilder
    private func provenanceLayerBadge(_ layer: AmenConnectSpacesScriptureProvenanceLayer) -> some View {
        let (label, color): (String, Color) = {
            switch layer {
            case .canonicalReference: return ("Canonical", Color(hex: "5DD178"))
            case .translationSource:  return ("Translation", Color(hex: "D9A441"))
            case .contextWindow:      return ("Context", Color.white.opacity(0.50))
            case .bereanStudySheet:   return ("Berean", Color(hex: "6E4BB5"))
            }
        }()

        Text(label)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .overlay {
                Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1)
            }
            .clipShape(Capsule())
    }

    // MARK: Section header helper

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .kerning(1.0)
            .foregroundStyle(Color.white.opacity(0.35))
    }
}

// MARK: - Hex color helper (module-scoped, used across all 4 files via single definition)
// Note: AmenSyntheticMediaLabelView.swift defines a private Color(hex:) extension.
// This one is also private and scoped to this file only to avoid redeclaration.
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenConnectPlayerView(
        video: AmenConnectSpacesConnectVideo(
            id: "preview-video-1",
            provenance: AmenConnectSpacesVideoProvenance(
                humanRecorded: true, aiEdited: true, aiGenerated: false,
                synthVoice: false, synthFace: false, deepfakeRisk: 0.2, verifiedOriginal: false),
            teacherId: "pastor_james",
            transcriptRef: "transcripts/preview-video-1",
            claims: [
                AmenConnectSpacesTeachingClaim(
                    id: "c1",
                    text: "Faith without works is dead.",
                    timestampSeconds: 120,
                    sourceTranscriptRange: "00:02:00–00:03:15",
                    opposingFaithfulViews: ["Salvation is by grace alone (Ephesians 2:8-9)"])
            ],
            scriptureRefs: [
                AmenConnectSpacesScriptureRefProvenance(
                    id: "s1", reference: "James 2:17", translation: "ESV",
                    sourceLayer: .canonicalReference, verifiedAt: Date(), confidence: 0.97),
                AmenConnectSpacesScriptureRefProvenance(
                    id: "s2", reference: "Romans 3:28", translation: "NIV",
                    sourceLayer: .bereanStudySheet, verifiedAt: Date(), confidence: 0.88)
            ],
            sponsored: false,
            createdAt: Date(),
            updatedAt: Date())
    )
}
#endif
