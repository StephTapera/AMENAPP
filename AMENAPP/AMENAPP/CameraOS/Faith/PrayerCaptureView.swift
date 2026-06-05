// PrayerCaptureView.swift
// AMENAPP — Camera OS
// Prayer capture: record → transcribe → written prayer + card.
// On-brand, low-risk, private-first. No camera required — voice-first flow.

import SwiftUI
import AVFoundation

// MARK: - Local phase enum

private enum PrayerCapturePhase: Equatable {
    case typeSelection
    case recording
    case transcribing
    case editing
    case done
}

// MARK: - Audio recorder coordinator

private class AudioRecorderCoordinator: NSObject, AVAudioRecorderDelegate {

    var onFinish: ((Bool) -> Void)?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        onFinish?(flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        onFinish?(false)
    }
}

// MARK: - PrayerCaptureView

struct PrayerCaptureView: View {

    // MARK: Props

    let onComplete: (PrayerCapture) -> Void
    let onDismiss: () -> Void

    // MARK: State

    @State private var selectedType: PrayerCaptureType = .personalPrayer
    @State private var isRecording = false
    @State private var recordingSeconds: Int = 0
    @State private var transcript: String = ""
    @State private var writtenPrayer: String = ""
    @State private var scriptureRef: String = ""
    @State private var phase: PrayerCapturePhase = .typeSelection
    @State private var recordingTimer: Timer? = nil

    // Audio
    @State private var audioRecorder: AVAudioRecorder? = nil
    @State private var pulseScale: CGFloat = 1.0
    @State private var doneCheckScale: CGFloat = 0.3
    @State private var doneCheckOpacity: Double = 0.0

    private let coordinator = AudioRecorderCoordinator()

    // MARK: Accent

    private let amber = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Dismiss handle
                dismissHandle

                switch phase {
                case .typeSelection:
                    typeSelectionPhase
                case .recording:
                    recordingPhase
                case .transcribing:
                    transcribingPhase
                case .editing:
                    editingPhase
                case .done:
                    donePhase
                }
            }
        }
        .onChange(of: phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
    }

    // MARK: - Dismiss handle

    private var dismissHandle: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            }
            .accessibilityLabel("Dismiss prayer capture")
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Phase 1: Type Selection

    private var typeSelectionPhase: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Begin in Prayer")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)

                    Text("What kind of prayer is this?")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 10) {
                    ForEach(PrayerCaptureType.allCases) { type in
                        PrayerTypeOptionRow(
                            type: type,
                            isSelected: selectedType == type,
                            amber: amber
                        ) {
                            selectedType = type
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Begin button
                Button(action: { withAnimation(.easeInOut(duration: 0.3)) { phase = .recording } }) {
                    Text("Begin")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(amber, in: Capsule())
                }
                .accessibilityLabel("Begin prayer recording")
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Phase 2: Recording

    private var recordingPhase: some View {
        VStack(spacing: 32) {
            Spacer()

            // Waveform / mic icon
            ZStack {
                Circle()
                    .fill(amber.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isRecording ? pulseScale : 1.0)
                    .animation(
                        isRecording
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseScale
                    )

                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(amber)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(isRecording ? "Recording in progress" : "Microphone, tap to record")

            // Status text
            Text(isRecording ? "Recording..." : "Tap to begin")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            // Timer
            if isRecording || recordingSeconds > 0 {
                Text(formattedTime(recordingSeconds))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityLabel("Elapsed time \(formattedTime(recordingSeconds))")
            }

            // Record button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(amber)
                        .frame(width: 72, height: 72)

                    if isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black)
                            .frame(width: 26, height: 26)
                    } else {
                        Circle()
                            .fill(.black)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Phase: Transcribing (brief)

    private var transcribingPhase: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(amber)
                .scaleEffect(1.4)
                .accessibilityLabel("Transcribing your prayer")

            Text("Transcribing...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Phase 3: Editing

    private var editingPhase: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                Text("Review Your Prayer")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                // Transcript editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 20)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                            )
                            .frame(height: 160)

                        TextEditor(text: $transcript)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(height: 160)
                    }
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Prayer transcript, editable")
                }

                // Written prayer editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Written Prayer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 20)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                            )
                            .frame(height: 160)

                        if writtenPrayer.isEmpty {
                            Text("Edit your written prayer...")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $writtenPrayer)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(height: 160)
                    }
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Written prayer, editable")
                }

                // Scripture reference
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scripture Reference")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 20)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                            )
                            .frame(height: 48)

                        if scriptureRef.isEmpty {
                            Text("e.g., Philippians 4:6")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.horizontal, 16)
                                .allowsHitTesting(false)
                        }

                        TextField("", text: $scriptureRef)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Scripture reference, optional")
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: completePrayer) {
                        Text("Complete Prayer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(amber, in: Capsule())
                    }
                    .accessibilityLabel("Save and complete prayer")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            recordingSeconds = 0
                            transcript = ""
                            writtenPrayer = ""
                            phase = .recording
                        }
                    }) {
                        Text("Record Again")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                    }
                    .accessibilityLabel("Discard and record a new prayer")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Phase 4: Done

    private var donePhase: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(amber.opacity(0.18))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(amber)
                    .accessibilityHidden(true)
            }
            .scaleEffect(doneCheckScale)
            .opacity(doneCheckOpacity)
            .accessibilityLabel("Prayer saved checkmark")

            Text("Prayer Captured")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Text("Your prayer has been saved.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                doneCheckScale = 1.0
                doneCheckOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onDismiss()
            }
        }
    }

    // MARK: - Helpers

    private func handlePhaseChange(_ newPhase: PrayerCapturePhase) {
        if newPhase != .recording {
            recordingTimer?.invalidate()
            recordingTimer = nil
            if isRecording {
                stopAudioRecorder()
                isRecording = false
            }
        }
        if newPhase == .recording {
            pulseScale = 1.18
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopAudioRecorder()
            isRecording = false
            recordingTimer?.invalidate()
            recordingTimer = nil
            withAnimation { phase = .transcribing }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Production: call transcription service here.
                transcript = "Your prayer has been captured."
                writtenPrayer = transcript
                withAnimation { phase = .editing }
            }
        } else {
            startAudioRecorder()
            isRecording = true
            pulseScale = 1.18
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                recordingSeconds += 1
            }
        }
    }

    private func startAudioRecorder() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            // If session activation fails, we proceed without recording.
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("prayer_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        guard let recorder = try? AVAudioRecorder(url: tempURL, settings: settings) else { return }
        coordinator.onFinish = { _ in }
        recorder.delegate = coordinator
        recorder.record()
        audioRecorder = recorder
    }

    private func stopAudioRecorder() {
        audioRecorder?.stop()
        audioRecorder = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func completePrayer() {
        let capture = PrayerCapture(
            id: UUID().uuidString,
            transcript: transcript,
            prayerType: selectedType,
            writtenPrayer: writtenPrayer.isEmpty ? transcript : writtenPrayer,
            scriptureRef: scriptureRef.isEmpty ? nil : scriptureRef,
            capturedAt: Date()
        )
        onComplete(capture)
        withAnimation(.easeInOut(duration: 0.3)) { phase = .done }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Prayer type option row

private struct PrayerTypeOptionRow: View {

    let type: PrayerCaptureType
    let isSelected: Bool
    let amber: Color
    let onTap: () -> Void

    private var description: String {
        switch type {
        case .personalPrayer:  return "A conversation with God"
        case .prayerRequest:   return "Share a need with your community"
        case .intercession:    return "Praying on behalf of others"
        case .thanksgiving:    return "Gratitude and praise"
        case .worship:         return "Honoring God in song or words"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: type.systemIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? .black : amber)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)

                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.black.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? amber : .ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? amber.opacity(0.6) : .white.opacity(0.22),
                                lineWidth: 0.8
                            )
                    )
            }
        }
        .accessibilityLabel("\(type.displayName), \(description)\(isSelected ? ", selected" : "")")
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PrayerCaptureView(
        onComplete: { capture in
            print("Captured: \(capture.prayerType.displayName)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
    .preferredColorScheme(.dark)
}
