// VoicePrayerCommentRowView.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Published voice comment row.
// White base surface, Liquid Glass playback pill, collapsed transcript,
// spiritual actions, report button.
// Supports Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency.

import SwiftUI
import AVFoundation

struct VoicePrayerCommentRowView: View {
    let comment: VoiceComment
    let currentUserId: String
    let onReact: (VoiceCommentReaction) -> Void
    let onReport: () -> Void
    let onDelete: (() -> Void)?
    let onSaveToPrayerList: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @StateObject private var playerState = VoicePrayerPlayerState()
    @State private var transcriptExpanded = false
    @State private var showReportSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row
            authorRow

            // Playback pill (Liquid Glass)
            playbackPill

            // Transcript (collapsed by default)
            if comment.hasTranscript {
                transcriptRow
            }

            // AI summary (only when backend returns one)
            if comment.hasSummary {
                summaryRow
            }

            // Spiritual actions
            spiritualActionsRow
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .onDisappear { playerState.stop() }
    }

    // MARK: - Author row

    private var authorRow: some View {
        HStack(spacing: 10) {
            // Type badge
            Label(comment.type.displayName, systemImage: comment.type.systemIcon)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(comment.type == .prayer ? .blue : .purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        comment.type == .prayer
                            ? Color.blue.opacity(0.1)
                            : Color.purple.opacity(0.1)
                    )
                )
                .accessibilityLabel("\(comment.type.displayName) voice comment")

            Spacer()

            // Duration
            Text(comment.durationString)
                .font(.systemScaled(12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .monospacedDigit()
                .accessibilityLabel("Duration \(comment.durationString)")

            // Report / Delete menu
            Menu {
                if comment.authorUid == currentUserId, let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button {
                        showReportSheet = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(reduceTransparency
                                      ? AnyShapeStyle(Color(uiColor: .tertiarySystemBackground))
                                      : AnyShapeStyle(.thinMaterial))
                    )
            }
            .accessibilityLabel("More options")
        }
    }

    // MARK: - Playback Pill (Liquid Glass)

    private var playbackPill: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button {
                if playerState.isPlaying {
                    playerState.pause()
                } else {
                    playerState.play(storagePath: comment.audioStoragePath)
                    AMENAnalyticsService.shared.track(.voiceCommentReacted(postId: comment.postId, reaction: "play"))
                }
            } label: {
                Image(systemName: playerState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.systemScaled(34, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .symbolEffect(.bounce, value: playerState.isPlaying)
            }
            .accessibilityLabel(playerState.isPlaying ? "Pause" : "Play voice \(comment.type.displayName)")

            VStack(alignment: .leading, spacing: 4) {
                // Waveform preview (static from stored samples)
                staticWaveform
                    .frame(height: 24)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(height: 2)
                        Capsule()
                            .fill(Color(uiColor: .label))
                            .frame(
                                width: geo.size.width * max(0, min(1, playerState.progress)),
                                height: 2
                            )
                    }
                }
                .frame(height: 2)
            }

            // Error state
            if playerState.hasError {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Playback error")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                      : AnyShapeStyle(.thinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Static waveform from stored samples

    @ViewBuilder
    private var staticWaveform: some View {
        GeometryReader { geo in
            let samples = comment.waveform.isEmpty
                ? Array(repeating: 0.3, count: 30)
                : Array(comment.waveform.prefix(30))
            let barCount = samples.count
            let spacing: CGFloat = 2
            let barW = max(2, (geo.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = max(3, CGFloat(samples[i]) * geo.size.height)
                    RoundedRectangle(cornerRadius: barW / 2)
                        .fill(playerState.isPlaying
                              ? Color(uiColor: .label)
                              : Color(uiColor: .secondaryLabel).opacity(0.5))
                        .frame(width: barW, height: h)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Transcript

    private var transcriptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    transcriptExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.systemScaled(11))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Text(transcriptExpanded ? "Hide transcript" : "Show transcript")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Image(systemName: transcriptExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(10))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(transcriptExpanded ? "Hide transcript" : "Show transcript")

            if transcriptExpanded {
                Text(comment.transcript)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.systemScaled(11))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .padding(.top, 2)
            Text(comment.summary)
                .font(.systemScaled(12))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Spiritual actions

    private var spiritualActionsRow: some View {
        HStack(spacing: 8) {
            ForEach(VoiceCommentReaction.allCases, id: \.rawValue) { reaction in
                reactionButton(reaction)
            }

            Spacer()

            // Save to Prayer List
            Button {
                onSaveToPrayerList()
                HapticManager.impact(style: .light)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark")
                        .font(.systemScaled(13, weight: .medium))
                    Text("Save")
                        .font(.systemScaled(12, weight: .medium))
                }
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(uiColor: .tertiarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save to Prayer List")
        }
    }

    @ViewBuilder
    private func reactionButton(_ reaction: VoiceCommentReaction) -> some View {
        let count: Int = {
            switch reaction {
            case .prayed:    return comment.counts.prayed
            case .amen:      return comment.counts.amen
            case .encourage: return comment.counts.encourage
            }
        }()

        Button {
            onReact(reaction)
            HapticManager.impact(style: .light)
            AMENAnalyticsService.shared.track(.voiceCommentReacted(postId: comment.postId, reaction: reaction.rawValue))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: reaction.systemIcon)
                    .font(.systemScaled(13, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.systemScaled(12, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(reduceTransparency
                               ? AnyShapeStyle(Color(uiColor: .tertiarySystemBackground))
                               : AnyShapeStyle(.thinMaterial))
            )
            .overlay(
                Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.displayLabel), \(count) reactions")
    }

    // MARK: - Report sheet

    @ViewBuilder
    private var reportMenu: some View {
        if showReportSheet {
            VoicePrayerReportSheet(voiceCommentId: comment.id, postId: comment.postId) {
                showReportSheet = false
                onReport()
            }
        }
    }
}

// MARK: - VoicePrayerPlayerState

@MainActor
final class VoicePrayerPlayerState: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var hasError = false

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var downloadTask: Task<Void, Never>?

    func play(storagePath: String) {
        // Download audio URL from backend service then play
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let url = try await VoicePrayerUploadService.getPlaybackURL(storagePath: storagePath)
                guard !Task.isCancelled else { return }
                let data = try Data(contentsOf: url)
                guard !Task.isCancelled else { return }
                let p = try AVAudioPlayer(data: data)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                p.play()
                self.player = p
                self.isPlaying = true
                self.hasError = false
                self.startProgressTimer(duration: p.duration)
            } catch {
                self.hasError = true
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        stopProgressTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startProgressTimer(duration: TimeInterval) {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.progress = p.currentTime / duration
                if !p.isPlaying && p.currentTime >= duration * 0.98 {
                    self.isPlaying = false
                    self.progress = 0
                    self.stopProgressTimer()
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Report Sheet

struct VoicePrayerReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let voiceCommentId: String
    let postId: String
    let onDone: () -> Void

    @State private var isSubmitting = false
    @State private var submitted = false

    private let reasons = [
        "Off-topic or unrelated",
        "Hateful or threatening",
        "Explicit content",
        "Spam or scam",
        "Harassment",
        "False or misleading",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Report Voice Comment") {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            submit(reason: reason)
                        } label: {
                            HStack {
                                Text(reason)
                                    .font(.systemScaled(15))
                                    .foregroundStyle(Color(uiColor: .label))
                                Spacer()
                                if isSubmitting {
                                    ProgressView().scaleEffect(0.75)
                                }
                            }
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit(reason: String) {
        isSubmitting = true
        Task {
            try? await VoicePrayerUploadService.report(voiceCommentId: voiceCommentId, postId: postId, reason: reason)
            await MainActor.run {
                isSubmitting = false
                onDone()
                dismiss()
            }
        }
    }
}
