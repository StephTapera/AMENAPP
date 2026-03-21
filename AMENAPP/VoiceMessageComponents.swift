//
//  VoiceMessageComponents.swift
//  AMENAPP
//
//  Voice message recording, waveform UI, playback, and Firebase Storage upload.
//  Wire into UnifiedChatView via VoiceMessageRecorderButton.
//

import SwiftUI
import AVFoundation
import FirebaseStorage
import FirebaseAuth
import Combine

// MARK: - Recorder ViewModel

@MainActor
final class VoiceMessageViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var amplitudes: [CGFloat] = Array(repeating: 0.15, count: 30)
    @Published var error: String? = nil

    private var recorder: AVAudioRecorder?
    private var durationTimer: Timer?
    private var amplitudeTimer: Timer?
    private var recordingURL: URL?

    // Callback fired with the Firebase Storage URL on successful upload
    var onComplete: ((URL, TimeInterval) -> Void)?

    // MARK: - Start

    func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.error = "Microphone permission is required to send voice messages."
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent("voice_\(UUID().uuidString).m4a")
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()

            isRecording = true
            recordingDuration = 0
            amplitudes = Array(repeating: 0.15, count: 30)

            // Duration counter (1Hz)
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.recordingDuration += 1 }
            }

            // Amplitude sampler (10Hz for smooth waveform)
            amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleAmplitude() }
            }
            RunLoop.main.add(durationTimer!, forMode: .common)
            RunLoop.main.add(amplitudeTimer!, forMode: .common)

        } catch {
            self.error = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func sampleAmplitude() {
        guard let rec = recorder, rec.isRecording else { return }
        rec.updateMeters()
        let db = rec.averagePower(forChannel: 0)  // -160…0 dB
        let normalized = CGFloat(max(0.05, min(1.0, (db + 60) / 60)))
        amplitudes = Array(amplitudes.dropFirst()) + [normalized]
    }

    // MARK: - Stop & Upload

    func stopAndSend() {
        guard isRecording, let url = recordingURL else { return }
        stopTimers()
        let finalDuration = recordingDuration
        recorder?.stop()
        recorder = nil
        isRecording = false
        isUploading = true

        Task {
            await uploadToStorage(localURL: url, duration: finalDuration)
        }
    }

    func cancelRecording() {
        stopTimers()
        recorder?.stop()
        recorder = nil
        isRecording = false
        isUploading = false
        recordingDuration = 0
        amplitudes = Array(repeating: 0.15, count: 30)
    }

    private func stopTimers() {
        durationTimer?.invalidate(); durationTimer = nil
        amplitudeTimer?.invalidate(); amplitudeTimer = nil
    }

    private func uploadToStorage(localURL: URL, duration: TimeInterval) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isUploading = false
            return
        }
        let storagePath = "voice_messages/\(uid)/\(UUID().uuidString).m4a"
        let ref = Storage.storage().reference().child(storagePath)

        do {
            let data = try Data(contentsOf: localURL)
            let meta = StorageMetadata()
            meta.contentType = "audio/m4a"
            _ = try await ref.putDataAsync(data, metadata: meta)
            let downloadURL = try await ref.downloadURL()

            isUploading = false
            onComplete?(downloadURL, duration)
        } catch {
            isUploading = false
            self.error = "Upload failed: \(error.localizedDescription)"
        }
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in self.error = "Recording failed." }
        }
    }
}

// MARK: - Animated Waveform

struct VoiceWaveformView: View {
    let amplitudes: [CGFloat]
    var barColor: Color = .purple
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { _, amp in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: max(4, amp * 28))
                    .animation(.easeOut(duration: 0.08), value: amp)
            }
        }
    }
}

// MARK: - Static Playback Waveform

/// Renders a fixed waveform bar chart for a sent voice message.
/// Bar heights are derived deterministically from the message ID so they look
/// consistent between sender and receiver.
struct VoicePlaybackWaveform: View {
    let messageId: String
    let progress: Double          // 0…1
    var totalBars: Int = 30

    private var bars: [CGFloat] {
        let seed = messageId.utf8.reduce(0) { $0 &+ Int($1) }
        return (0..<totalBars).map { i in
            let x = Double((seed &+ i * 137) % 256) / 255
            return CGFloat(0.2 + x * 0.8)
        }
    }

    var body: some View {
        let filled = Int(Double(totalBars) * progress)
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, amp in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < filled ? Color.purple : Color.secondary.opacity(0.4))
                    .frame(width: 2.5, height: max(4, amp * 24))
            }
        }
    }
}

// MARK: - Recording Button (hold-to-record)

struct VoiceMessageRecorderButton: View {
    @StateObject private var vm = VoiceMessageViewModel()
    var onComplete: ((URL, TimeInterval) -> Void)?

    @State private var isHolding = false
    @State private var holdScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if vm.isRecording {
                recordingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if vm.isUploading {
                ProgressView()
                    .frame(width: 36, height: 36)
                    .transition(.opacity)
            } else {
                micButton
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isUploading)
        .onAppear {
            vm.onComplete = { url, dur in
                onComplete?(url, dur)
            }
        }
        .alert("Voice Message", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    // ── Mic button (long-press to start) ──────────────────────────────────
    private var micButton: some View {
        Circle()
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            )
            .scaleEffect(holdScale)
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onChanged { _ in
                        withAnimation(.spring(response: 0.2)) { holdScale = 1.15 }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2)) { holdScale = 1.0 }
                        HapticManager.impact(style: .medium)
                        vm.startRecording()
                    }
            )
    }

    // ── Live recording pill ────────────────────────────────────────────────
    private var recordingOverlay: some View {
        HStack(spacing: 10) {
            // Animated waveform
            VoiceWaveformView(amplitudes: vm.amplitudes, barColor: .purple)
                .frame(height: 28)
                .frame(maxWidth: 100)

            // Duration
            Text(formattedDuration(vm.recordingDuration))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 38, alignment: .leading)

            Spacer(minLength: 0)

            // Cancel
            Button {
                HapticManager.impact(style: .light)
                vm.cancelRecording()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }

            // Send
            Button {
                HapticManager.impact(style: .medium)
                vm.stopAndSend()
            } label: {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: .purple.opacity(0.4), radius: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.purple.opacity(0.25), lineWidth: 1))
        )
        .frame(maxWidth: .infinity)
    }

    private func formattedDuration(_ secs: TimeInterval) -> String {
        let s = Int(secs) % 60
        let m = Int(secs) / 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Playback Bubble Component

struct VoiceMessageBubble: View {
    let attachment: MessageAttachment
    let messageId: String
    let isFromCurrentUser: Bool

    @StateObject private var player = VoicePlayer()

    var body: some View {
        HStack(spacing: 10) {
            // Play / Pause button
            Button {
                HapticManager.impact(style: .light)
                player.toggle(url: attachment.url)
            } label: {
                Circle()
                    .fill(isFromCurrentUser ? Color.purple : Color.secondary.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                // Playback waveform
                VoicePlaybackWaveform(messageId: messageId, progress: player.progress)
                    .frame(height: 24)

                // Duration
                Text(player.displayDuration)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 160)
    }
}

// MARK: - Audio Player

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var displayDuration = "0:00"

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var currentURL: URL?

    func toggle(url: URL?) {
        guard let url else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
            stopTimer()
        } else {
            play(url: url)
        }
    }

    private func play(url: URL) {
        do {
            if currentURL != url {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                currentURL = url
            }
            player?.play()
            isPlaying = true
            updateDisplay()
            startTimer()
        } catch {
            dlog("VoicePlayer error: \(error)")
        }
    }

    private func startTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateDisplay() }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateDisplay() {
        guard let p = player else { return }
        let elapsed = p.currentTime
        let total   = p.duration
        progress = total > 0 ? elapsed / total : 0
        let s = Int(elapsed) % 60
        let m = Int(elapsed) / 60
        displayDuration = String(format: "%d:%02d", m, s)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
        Task { @MainActor in
            isPlaying = false
            progress = 0
            displayDuration = "0:00"
            stopTimer()
        }
    }
}
