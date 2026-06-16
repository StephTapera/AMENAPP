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
import FirebaseAnalytics

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
    @State private var showSessionIntentSheet = true
    @State private var sessionGoal: String = ""
    @State private var sessionTimeLimitMinutes: Int = 30
    @State private var sessionStartedAt: Date? = nil
    @State private var showSessionRecap = false
    @State private var sessionReflection: String = ""
    @State private var sessionElapsedMinutes: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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

                    // End session button — visible once session has started
                    sessionEndButton
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
        .sheet(isPresented: $showSessionIntentSheet) {
            ConnectSessionIntentSheet(
                goal: $sessionGoal,
                timeLimitMinutes: $sessionTimeLimitMinutes
            ) {
                sessionStartedAt = Date()
                sessionElapsedMinutes = 0
                showSessionIntentSheet = false
            }
        }
        .sheet(isPresented: $showSessionRecap) {
            ConnectSessionRecapView(
                video: video,
                goal: sessionGoal,
                elapsedMinutes: sessionElapsedMinutes,
                reflection: $sessionReflection
            ) {
                showSessionRecap = false
            }
        }
        .onReceive(minuteTimer) { _ in
            guard sessionStartedAt != nil else { return }
            sessionElapsedMinutes += 1
            if sessionTimeLimitMinutes > 0 && sessionElapsedMinutes >= sessionTimeLimitMinutes {
                player.pause()
                showSessionRecap = true
            }
        }
        .onAppear {
            Analytics.logEvent("connect_video_viewed", parameters: [
                "video_id": video.id,
                "teacher_id": video.teacherId
            ])
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
                            .font(.systemScaled(11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(hex: "D9A441"))
                            .frame(width: 22, alignment: .center)
                        Text(chapter.title)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.80))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(10, weight: .semibold))
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
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                }
            }
            .accessibilityLabel("Transcript: \(showTranscript ? "expanded" : "collapsed")")

            if showTranscript {
                Text("Transcript is not yet available for this video. Check back after processing is complete.")
                    .font(.systemScaled(13))
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
                    .font(.systemScaled(13))
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
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text(ref.translation)
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "D9A441").opacity(0.15))
                        .clipShape(Capsule())
                }

                // Confidence
                Text(String(format: "%.0f%% confidence", ref.confidence * 100))
                    .font(.systemScaled(10))
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
            .font(.systemScaled(9, weight: .bold))
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

    // MARK: End session button

    @ViewBuilder
    private var sessionEndButton: some View {
        if sessionStartedAt != nil {
            Button {
                player.pause()
                showSessionRecap = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle")
                    Text("End Session")
                }
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("End session and see recap")
        }
    }

    // MARK: Section header helper

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(10, weight: .bold))
            .kerning(1.0)
            .foregroundStyle(Color.white.opacity(0.35))
    }
}

// MARK: - Session Intent Sheet

private struct ConnectSessionIntentSheet: View {
    @Binding var goal: String
    @Binding var timeLimitMinutes: Int
    let onStart: () -> Void

    private let timeLimitOptions: [(label: String, value: Int)] = [
        ("15 min", 15), ("30 min", 30), ("45 min", 45), ("60 min", 60), ("No limit", 0)
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What do you want to learn?")
                        .font(.systemScaled(16, weight: .semibold))
                    Text("Setting an intention helps you stay focused and makes it easier to reflect afterward.")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    intentSectionHeader("MY GOAL FOR THIS SESSION")
                    TextField("e.g. Understand how faith and works connect", text: $goal, axis: .vertical)
                        .font(.systemScaled(14))
                        .lineLimit(3, reservesSpace: true)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    intentSectionHeader("SESSION LENGTH")
                    HStack(spacing: 8) {
                        ForEach(timeLimitOptions, id: \.value) { option in
                            Button {
                                timeLimitMinutes = option.value
                            } label: {
                                Text(option.label)
                                    .font(.systemScaled(12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(timeLimitMinutes == option.value ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundStyle(timeLimitMinutes == option.value ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .accessibilityLabel("\(option.label) session")
                            .accessibilityValue(timeLimitMinutes == option.value ? "Selected" : "Not selected")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }

                Spacer()

                Button(action: onStart) {
                    Text("Start Watching")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Start watching")
            }
            .padding(20)
            .navigationTitle("Before You Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func intentSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Session Recap View

private struct ConnectSessionRecapView: View {
    let video: AmenConnectSpacesConnectVideo
    let goal: String
    let elapsedMinutes: Int
    @Binding var reflection: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Elapsed summary
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session complete")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if elapsedMinutes > 0 {
                                Text("\(elapsedMinutes) min watched")
                                    .font(.systemScaled(22, weight: .bold))
                            }
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(36))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Session goal
                    if !goal.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            recapSectionHeader("YOUR GOAL")
                            Text(goal)
                                .font(.systemScaled(14))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    // Key claims
                    if !video.claims.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            recapSectionHeader("KEY CLAIMS IN THIS VIDEO")
                            VStack(spacing: 6) {
                                ForEach(video.claims) { claim in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "quote.opening")
                                            .font(.systemScaled(11))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.top, 2)
                                        Text(claim.text)
                                            .font(.systemScaled(13))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityLabel("Claim: \(claim.text)")
                                }
                            }
                        }
                    }

                    // Scripture refs
                    if !video.scriptureRefs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            recapSectionHeader("SCRIPTURE REFERENCED")
                            FlowLayout(items: video.scriptureRefs) { ref in
                                Text(ref.reference)
                                    .font(.systemScaled(12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                                    .accessibilityLabel(ref.reference)
                            }
                        }
                    }

                    // "What did I learn?" reflection
                    VStack(alignment: .leading, spacing: 8) {
                        recapSectionHeader("WHAT DID I LEARN?")
                        Text("Take a moment to write down what stood out to you.")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                        TextField("Write your reflection here…", text: $reflection, axis: .vertical)
                            .font(.systemScaled(14))
                            .lineLimit(5, reservesSpace: true)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button(action: onDone) {
                        Text("Done")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 8)
                    .accessibilityLabel("Done with recap")
                }
                .padding(20)
            }
            .navigationTitle("Session Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDone)
                }
            }
        }
    }

    @ViewBuilder
    private func recapSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
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
                // TODO(legal): was ESV/NIV — changed to KJV/WEB (public domain) per AMEN-CONTENT-001
                AmenConnectSpacesScriptureRefProvenance(
                    id: "s1", reference: "James 2:17", translation: "KJV",
                    sourceLayer: .canonicalReference, verifiedAt: Date(), confidence: 0.97),
                AmenConnectSpacesScriptureRefProvenance(
                    id: "s2", reference: "Romans 3:28", translation: "WEB",
                    sourceLayer: .bereanStudySheet, verifiedAt: Date(), confidence: 0.88)
            ],
            sponsored: false,
            createdAt: Date(),
            updatedAt: Date())
    )
}
#endif
