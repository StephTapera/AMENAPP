// VoicePrayerRecorderView.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Full recording + review + upload flow.
// Liquid Glass capsule controls. White base surface.
// Supports Reduce Motion, Dynamic Type, VoiceOver, Reduce Transparency.

import SwiftUI

struct VoicePrayerRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let commentType: VoiceCommentType
    let postId: String
    let onPublished: (VoiceComment) -> Void

    @StateObject private var engine = VoicePrayerAudioEngine()
    @StateObject private var uploadService = VoicePrayerUploadService()

    @State private var visibility: VoiceCommentVisibility = .public
    @State private var showVisibilityPicker = false
    @State private var showSensitiveWarning = false
    @State private var transcriptExpanded = false
    @State private var confirmBeforePublish = false
    @State private var appeared = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    Spacer(minLength: 0)

                    switch engine.state {
                    case .idle:
                        idleView
                    case .requestingPermission:
                        statusMessageView(icon: "mic.fill", message: "Requesting microphone access…")
                    case .recording, .paused:
                        recordingView
                    case .finishedRecording:
                        reviewView
                    case .playingPreview:
                        reviewView
                    case .uploading:
                        statusMessageView(icon: "arrow.up.circle.fill", message: "Uploading…")
                    case .processing:
                        statusMessageView(icon: "waveform", message: "Processing your \(commentType.displayName.lowercased())…\nThis usually takes a few seconds.")
                    case .error(let msg):
                        errorView(message: msg)
                    }

                    Spacer(minLength: 0)
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            engine.configure(for: commentType)
            // Auto-start after configure
            Task { await engine.requestPermissionAndStart() }
        }
        .onDisappear {
            engine.cancelRecording()
        }
        .sheet(isPresented: $showVisibilityPicker) {
            VoicePrayerVisibilityPickerView(selected: $visibility)
        }
        .alert("Sensitive Details Detected", isPresented: $showSensitiveWarning) {
            Button("Post Privately") {
                visibility = .private
                submitUpload()
            }
            Button("Post Anyway", role: .destructive) {
                submitUpload()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your recording may contain sensitive personal details. Consider a more private visibility setting.")
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                engine.cancelRecording()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(reduceTransparency
                                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                      : AnyShapeStyle(.thinMaterial))
                    )
            }
            .accessibilityLabel("Cancel recording")

            Spacer()

            // Type badge
            HStack(spacing: 6) {
                Image(systemName: commentType.systemIcon)
                    .font(.systemScaled(13, weight: .semibold))
                Text(commentType.displayName)
                    .font(.systemScaled(14, weight: .semibold))
            }
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(reduceTransparency
                               ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                               : AnyShapeStyle(.thinMaterial))
            )
            .overlay(
                Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
            )

            Spacer()

            // Visibility selector
            Button {
                showVisibilityPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: visibility.systemIcon)
                        .font(.systemScaled(13, weight: .medium))
                    Text(visibilityShortLabel)
                        .font(.systemScaled(13, weight: .medium))
                }
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(reduceTransparency
                                   ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                   : AnyShapeStyle(.thinMaterial))
                )
                .overlay(
                    Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                )
            }
            .accessibilityLabel("Visibility: \(visibility.displayName). Tap to change.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 28) {
            Text("Preparing microphone…")
                .font(.systemScaled(16))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            ProgressView()
                .tint(Color(uiColor: .label))
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 32) {
            // Timer + limit indicator
            VStack(spacing: 6) {
                Text(timerString)
                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                    .foregroundStyle(Color(uiColor: .label))
                    .accessibilityLabel("Elapsed time \(timerString)")
                    .monospacedDigit()

                if engine.isNearLimit {
                    Text("Almost at limit (\(Int(engine.maxDuration))s max)")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: engine.isNearLimit)

            // Waveform
            waveformView(samples: engine.waveformSamples, isActive: engine.isRecording)
                .frame(height: 64)
                .padding(.horizontal, 32)

            // Recording controls (Liquid Glass capsule)
            recordingControlsCapsule
        }
    }

    private var recordingControlsCapsule: some View {
        HStack(spacing: 20) {
            // Cancel
            controlButton(icon: "xmark", label: "Cancel") {
                engine.cancelRecording()
                dismiss()
            }
            .foregroundStyle(.red)

            // Pause / Resume
            controlButton(
                icon: engine.isPaused ? "play.fill" : "pause.fill",
                label: engine.isPaused ? "Resume" : "Pause"
            ) {
                if engine.isPaused { engine.resumeRecording() }
                else { engine.pauseRecording() }
            }

            // Stop / Finish
            controlButton(icon: "stop.fill", label: "Finish") {
                engine.stopRecording()
            }
            .foregroundStyle(.green)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Capsule(style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                      : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 28) {
            // Playback pill
            playbackPill

            // Transcript state (if available from quick local whisper — not yet; shows pending)
            if !uploadService.transcript.isEmpty {
                transcriptSection
            }

            // Sensitive detail warning
            if uploadService.containsSensitiveDetails {
                sensitiveWarningBanner
            }

            // Submit controls
            reviewControlsCapsule
        }
        .padding(.horizontal, 20)
    }

    private var playbackPill: some View {
        HStack(spacing: 14) {
            // Play/Stop button
            Button {
                if engine.isPlayingPreview { engine.stopPreview() }
                else { engine.playPreview() }
                AMENAnalyticsService.shared.track(.voiceCommentPreviewPlayed(postId: postId))
            } label: {
                Image(systemName: engine.isPlayingPreview ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
            }
            .accessibilityLabel(engine.isPlayingPreview ? "Stop preview" : "Play preview")

            VStack(alignment: .leading, spacing: 4) {
                // Mini waveform
                waveformView(samples: engine.waveformSamples, isActive: engine.isPlayingPreview)
                    .frame(height: 28)

                // Progress bar during playback
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color(uiColor: .label))
                            .frame(width: geo.size.width * max(0, min(1, engine.playbackProgress)), height: 3)
                    }
                }
                .frame(height: 3)
            }

            Text(timerString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                      : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    transcriptExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.systemScaled(12, weight: .medium))
                    Text("Transcript")
                        .font(.systemScaled(13, weight: .semibold))
                    Spacer()
                    Image(systemName: transcriptExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(11, weight: .semibold))
                }
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .buttonStyle(.plain)

            if transcriptExpanded {
                Text(uploadService.transcript)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color(uiColor: .label))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var sensitiveWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.orange)
            Text("Sensitive details detected. Consider a more private visibility.")
                .font(.systemScaled(13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var reviewControlsCapsule: some View {
        HStack(spacing: 20) {
            // Re-record
            controlButton(icon: "arrow.counterclockwise", label: "Re-record") {
                engine.reRecord()
                uploadService.reset()
                Task { await engine.requestPermissionAndStart() }
            }

            // Submit
            Button {
                submitUpload()
            } label: {
                HStack(spacing: 6) {
                    if uploadService.isUploading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.systemScaled(14, weight: .semibold))
                    }
                    Text(uploadService.isUploading ? "Sending…" : "Share \(commentType.displayName)")
                        .font(.systemScaled(15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .label))
                )
            }
            .disabled(!engine.hasRecording || uploadService.isUploading || engine.exceedsMaxFileSize)
            .accessibilityLabel("Share \(commentType.displayName)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Capsule(style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                      : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Status / Error

    private func statusMessageView(icon: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(message)
                .font(.systemScaled(15))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.red)
            Text(message)
                .font(.systemScaled(15))
                .foregroundStyle(Color(uiColor: .label))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                engine.reset()
                Task { await engine.requestPermissionAndStart() }
            }
            .font(.systemScaled(15, weight: .semibold))
            .padding(.horizontal, 28)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
            .foregroundStyle(Color(uiColor: .label))
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Waveform renderer

    @ViewBuilder
    private func waveformView(samples: [Float], isActive: Bool) -> some View {
        GeometryReader { geo in
            let barCount = min(samples.count, 40)
            let spacing: CGFloat = 2
            let barWidth = max(2, (geo.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let idx = samples.count - barCount + i
                    let s = idx >= 0 ? CGFloat(samples[idx]) : 0.05
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(isActive
                              ? Color(uiColor: .label)
                              : Color(uiColor: .secondaryLabel).opacity(0.6))
                        .frame(width: barWidth, height: max(3, s * geo.size.height))
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.08),
                            value: s
                        )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Control Button

    @ViewBuilder
    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(20, weight: .medium))
                Text(label)
                    .font(.systemScaled(11, weight: .medium))
            }
            .foregroundStyle(Color(uiColor: .label))
            .frame(width: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Helpers

    private var timerString: String {
        let s = Int(engine.elapsedSeconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var visibilityShortLabel: String {
        switch visibility {
        case .public:      return "Public"
        case .followers:   return "Followers"
        case .church:      return "Church"
        case .prayerCircle: return "Circle"
        case .private:     return "Private"
        }
    }

    // MARK: - Submit

    private func submitUpload() {
        guard let url = engine.recordedFileURL, engine.hasRecording else { return }
        guard !engine.exceedsMaxFileSize else {
            engine.markError("Recording exceeds the 25 MB size limit. Please record a shorter note.")
            return
        }
        AMENAnalyticsService.shared.track(.voiceCommentSubmitted(postId: postId, type: commentType.rawValue))
        engine.markUploading()
        Task {
            do {
                let comment = try await uploadService.upload(
                    fileURL: url,
                    postId: postId,
                    type: commentType,
                    durationMs: engine.durationMs,
                    waveform: engine.waveformSamples.map { Double($0) },
                    visibility: visibility
                )
                await MainActor.run {
                    engine.markProcessing()
                    onPublished(comment)
                    dismiss()
                }
            } catch let err as VoicePrayerError where err == .sensitiveContent {
                await MainActor.run {
                    engine.markFinishedRecording()
                    showSensitiveWarning = true
                }
            } catch {
                await MainActor.run {
                    engine.markError(error.localizedDescription)
                }
            }
        }
    }
}
