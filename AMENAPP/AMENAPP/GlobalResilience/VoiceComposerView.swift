// VoiceComposerView.swift
// AMEN — Global Resilience System
//
// Sheet view for recording and editing voice-note posts.
// Feature-gated: only shown when GlobalResilienceFeatureFlags.shared.voiceTranscriptEnabled.
//
// Flow:
//   1. Idle      → hold-to-record button
//   2. Recording → animated waveform, release to stop
//   3. Done      → editable transcript, publish mode picker, action buttons
//
// onComplete(audioURL, transcriptText) is called when the user taps "Next →".
// saveAsChurchNote posts Notification.Name.saveAsChurchNote.

import AVFoundation
import Speech
import SwiftUI

// MARK: - VoicePublishMode

enum VoicePublishMode: String, CaseIterable, Identifiable {
    case audioAndTranscript = "Audio + Transcript"
    case transcriptOnly     = "Transcript Only"
    case audioOnly          = "Audio Only"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .audioAndTranscript: return "waveform.and.text.magnifyingglass"
        case .transcriptOnly:     return "text.alignleft"
        case .audioOnly:          return "waveform"
        }
    }
}

// MARK: - VoiceComposerView

struct VoiceComposerView: View {

    // MARK: Dependencies

    @StateObject private var engine = VoiceRecordingEngine()
    @ObservedObject private var flags = GlobalResilienceFeatureFlags.shared
    @ObservedObject private var lowData = LowDataModeManager.shared

    // MARK: Callbacks

    /// Called when the user taps "Next →". Both values may be nil depending on
    /// the selected publish mode.
    var onComplete: (URL?, String) -> Void
    /// Called when the user taps "Discard".
    var onDiscard: () -> Void

    // MARK: Local State

    @State private var publishMode: VoicePublishMode = .audioAndTranscript
    @State private var isHoldingRecord: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showDiscardConfirm: Bool = false

    // MARK: - Body

    var body: some View {
        // Feature gate.
        if flags.voiceTranscriptEnabled {
            content
        } else {
            unavailableView
        }
    }

    // MARK: - Main Content

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Low-data banner (inline, not overlay).
                    if lowData.isEffectiveLowData {
                        LowDataBanner()
                    }

                    // Transcription offline notice.
                    if !engine.isTranscriptAvailable && engine.recordingState == .done {
                        transcriptUnavailableNotice
                    }

                    // State-adaptive main card.
                    Group {
                        switch engine.recordingState {
                        case .idle:
                            idleCard
                        case .recording:
                            recordingCard
                        case .transcribing:
                            transcribingCard
                        case .done:
                            doneCard
                        case .error(let msg):
                            errorCard(msg)
                        }
                    }

                    // Action bar — only shown when done or on error.
                    if case .done = engine.recordingState {
                        actionBar
                    } else if case .error = engine.recordingState {
                        actionBar
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        if engine.recordingState == .done || engine.recordingState == .recording {
                            showDiscardConfirm = true
                        } else {
                            discardAndDismiss()
                        }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Discard voice note")
                }
            }
            .confirmationDialog(
                "Discard this voice note?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    discardAndDismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Idle Card

    private var idleCard: some View {
        VStack(spacing: 24) {
            Text("Hold to Record")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Record a voice note up to 5 minutes.\nTranscription happens on your device.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // Language picker.
            languagePicker

            // Hold-to-record button.
            recordButton
        }
        .padding(24)
        .glassEffect()
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Recording Card

    private var recordingCard: some View {
        VStack(spacing: 20) {
            Text("Recording…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            durationLabel

            // Animated waveform.
            WaveformBarsView(isAnimating: true)
                .frame(height: 60)
                .accessibilityLabel("Recording in progress waveform")
                .accessibilityHidden(true)

            recordButton
        }
        .padding(24)
        .glassEffect()
        .padding(.horizontal, 16)
    }

    // MARK: - Transcribing Card

    private var transcribingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.3)
                .accessibilityLabel("Transcribing your voice note")

            Text("Transcribing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            durationLabel
        }
        .padding(36)
        .glassEffect()
        .padding(.horizontal, 16)
    }

    // MARK: - Done Card

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Duration + waveform preview.
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Note")
                        .font(.headline)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Transcript editor (shown unless audioOnly).
            if publishMode != .audioOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $engine.transcriptText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Edit transcript")
                        .disabled(!engine.isTranscriptAvailable && engine.transcriptText.isEmpty)
                }
            }

            // Publish mode picker.
            publishModePicker

            // Language picker (for re-transcription UX awareness).
            languagePicker
        }
        .padding(20)
        .glassEffect()
        .padding(.horizontal, 16)
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Recording Error")
                .font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                engine.reset()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Try recording again")
        }
        .padding(28)
        .glassEffect()
        .padding(.horizontal, 16)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 12) {
            // Save as Smart Church Note.
            Button {
                saveAsChurchNote()
            } label: {
                Label("Save as Smart Church Note", systemImage: "building.columns")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityLabel("Save this voice note as a Smart Church Note")

            HStack(spacing: 12) {
                // Discard.
                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Text("Discard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Discard this voice note")

                // Next.
                Button {
                    handleNext()
                } label: {
                    Label("Next", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Continue to post composer")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Supporting Sub-Views

    private var recordButton: some View {
        RecordHoldButton(isHolding: $isHoldingRecord) {
            Task { await handleRecordStart() }
        } onRelease: {
            Task { await handleRecordStop() }
        }
    }

    private var durationLabel: some View {
        Text(formattedDuration)
            .font(.system(.title2, design: .monospaced).weight(.medium))
            .foregroundStyle(.primary)
            .accessibilityLabel("Recording duration \(formattedDuration)")
    }

    private var transcriptUnavailableNotice: some View {
        Label {
            Text("Transcription not available offline")
                .font(.footnote)
        } icon: {
            Image(systemName: "mic.slash")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .glassEffect()
        .padding(.horizontal, 16)
        .accessibilityLabel("Transcription is not available in offline mode")
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.xmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Voice notes are not available right now.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Language Picker

    private var languagePicker: some View {
        Picker("Language", selection: Binding(
            get: { engine.selectedLocale },
            set: { engine.selectedLocale = $0 }
        )) {
            ForEach(VoiceRecordingEngine.supportedLocales, id: \.identifier) { locale in
                Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                    .tag(locale)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Recording language")
    }

    // MARK: - Publish Mode Picker

    private var publishModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Post As")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Post As", selection: $publishMode) {
                ForEach(VoicePublishMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Choose how to publish this voice note")
        }
    }

    // MARK: - Actions

    private func handleRecordStart() async {
        do {
            try await engine.startRecording()
        } catch {
            engine.recordingState = .error(error.localizedDescription)
        }
    }

    private func handleRecordStop() async {
        await engine.stopRecording()
    }

    private func handleNext() {
        let url: URL? = (publishMode == .transcriptOnly) ? nil : engine.audioURL
        let transcript: String = (publishMode == .audioOnly) ? "" : engine.transcriptText
        onComplete(url, transcript)
    }

    private func saveAsChurchNote() {
        var info: [String: Any] = [
            "transcriptText": engine.transcriptText,
            "publishMode": publishMode.rawValue,
            "duration": engine.duration
        ]
        if let url = engine.audioURL {
            info["audioURL"] = url
        }
        NotificationCenter.default.post(
            name: .saveAsChurchNote,
            object: nil,
            userInfo: info
        )
    }

    private func discardAndDismiss() {
        engine.reset()
        onDiscard()
    }

    // MARK: - Formatting

    private var formattedDuration: String {
        let total = Int(engine.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - WaveformBarsView

/// Simple animated waveform using a TimelineView so bars update on each frame.
private struct WaveformBarsView: View {

    let isAnimating: Bool
    private let barCount = 12
    private let baseHeights: [CGFloat] = [18, 30, 24, 40, 28, 48, 36, 44, 22, 38, 26, 32]

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    bar(for: index, date: timeline.date)
                }
            }
        }
    }

    private func bar(for index: Int, date: Date) -> some View {
        let phase = date.timeIntervalSinceReferenceDate * 3.5 + Double(index) * 0.45
        let pulse = (sin(phase) + 1) / 2    // 0…1
        let base = baseHeights[index % baseHeights.count]
        let height = isAnimating ? base * (0.4 + 0.6 * pulse) : base * 0.4

        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(0.85))
            .frame(width: 4, height: max(4, height))
            .animation(.easeInOut(duration: 0.15), value: height)
    }
}

// MARK: - RecordHoldButton

/// A large circular button that triggers onPress when touched and onRelease when lifted.
private struct RecordHoldButton: View {

    @Binding var isHolding: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer pulsing ring while holding.
            Circle()
                .stroke(Color.accentColor.opacity(isHolding ? 0.3 : 0), lineWidth: 12)
                .frame(width: 90, height: 90)
                .scaleEffect(isHolding ? 1.25 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isHolding)

            // Main button.
            Circle()
                .fill(isHolding ? Color.red : Color.accentColor)
                .frame(width: 72, height: 72)
                .scaleEffect(scale)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .overlay {
                    Image(systemName: isHolding ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding else { return }
                    isHolding = true
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        scale = 0.9
                    }
                    onPress()
                }
                .onEnded { _ in
                    isHolding = false
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        scale = 1.0
                    }
                    onRelease()
                }
        )
        .accessibilityLabel(isHolding ? "Release to stop recording" : "Hold to record")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isHolding ? "Lift your finger to stop" : "Touch and hold to start recording")
    }
}

// MARK: - glassEffect helper

private extension View {
    /// Applies a glass-style background matching the existing GlobalResilience surface style.
    @ViewBuilder
    func glassEffect() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Preview

#Preview("Voice Composer — idle") {
    VoiceComposerView(
        onComplete: { url, transcript in
            print("Complete: \(String(describing: url)), transcript: \(transcript)")
        },
        onDiscard: {
            print("Discarded")
        }
    )
}
