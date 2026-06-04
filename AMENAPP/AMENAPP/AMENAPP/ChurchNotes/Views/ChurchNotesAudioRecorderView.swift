import SwiftUI
import AVFoundation

/// Records sermon audio for Church Notes intelligence processing.
/// Feature flag `churchNotesAudioCaptureEnabled` must be true before this view is shown.
/// The view never calls backend callables directly — it delegates to ChurchNotesMediaProcessingService.
struct ChurchNotesAudioRecorderView: View {

    let noteId: String
    @ObservedObject var processingService: ChurchNotesMediaProcessingService
    var onDismiss: () -> Void

    @StateObject private var recorder = ChurchNotesAudioRecorder()

    @State private var hasPermission = false
    @State private var showPermissionAlert = false
    @State private var isSubmitting = false
    @State private var submitError: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    statusBanner
                    Spacer()
                    waveformArea
                    Spacer()
                    controlDock
                        .padding(.bottom, 36)
                }
            }
            .navigationTitle("Record Sermon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stop()
                        onDismiss()
                    }
                    .accessibilityLabel("Cancel recording")
                }
            }
            .task { await checkMicPermission() }
            .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") { openSettings() }
                Button("Cancel", role: .cancel) { onDismiss() }
            } message: {
                Text("Allow microphone access in Settings to record sermons.")
            }
        }
    }

    // MARK: - Status banner

    private var statusBanner: some View {
        HStack(spacing: 8) {
            if recorder.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(recorderStatusLabel)
                .font(.subheadline)
                .foregroundStyle(recorder.isRecording ? Color.red : Color.secondary)
        }
        .padding(.top, 20)
        .animation(reduceMotion ? nil : .amenEaseMedium, value: recorder.isRecording)
        .accessibilityLabel(recorderStatusLabel)
    }

    private var recorderStatusLabel: String {
        if recorder.isRecording  { return "Recording — \(formatDuration(recorder.elapsedSeconds))" }
        if recorder.isPaused     { return "Paused — \(formatDuration(recorder.elapsedSeconds))" }
        if recorder.hasRecording { return "Recording ready — \(formatDuration(recorder.elapsedSeconds))" }
        return hasPermission ? "Ready to record" : "Microphone access needed"
    }

    // MARK: - Waveform placeholder

    private var waveformArea: some View {
        VStack(spacing: 16) {
            Image(systemName: recorder.isRecording ? "waveform" : "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(recorder.isRecording ? Color.red : Color.secondary)
                .symbolEffect(.variableColor, isActive: recorder.isRecording)
                .accessibilityHidden(true)

            if recorder.hasRecording && !recorder.isRecording {
                Text("Tap 'Send for Transcription' to process this recording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else if !hasPermission {
                Text("Tap 'Allow Microphone' to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Control dock

    @ViewBuilder
    private var controlDock: some View {
        if !hasPermission {
            // Solid CTA — permission prompts are not chrome, they stay opaque.
            Button("Allow Microphone Access") {
                Task { await requestMicPermission() }
            }
            .buttonStyle(ChurchNotesActionButtonStyle(color: .accentColor))
            .accessibilityHint("Opens microphone permission prompt")
        } else if isSubmitting {
            HStack(spacing: 12) {
                ProgressView()
                Text("Uploading…")
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else if let err = submitError {
            VStack(spacing: 12) {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") { Task { await submitRecording() } }
                    .buttonStyle(ChurchNotesActionButtonStyle(color: .accentColor))
                    .accessibilityLabel("Retry upload")
            }
        } else if recorder.hasRecording && !recorder.isRecording {
            // Post-recording actions: floating glass capsule bar above content.
            VStack(spacing: 14) {
                postRecordingDock
            }
        } else {
            // Live recording controls.
            recordingControlDock
        }
    }

    /// Glass capsule bar shown after a recording is complete.
    @ViewBuilder
    private var postRecordingDock: some View {
        if reduceTransparency {
            VStack(spacing: 14) {
                solidPostRecordingButtons
            }
        } else {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        Task { await submitRecording() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 17, weight: .medium))
                            Text("Send for Transcription")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                    }
                    .accessibilityLabel("Send recording for AI transcription")
                    .accessibilityHint("Uploads recording and generates a transcript draft for your review")
                    .glassEffect()

                    Button {
                        recorder.discard()
                        submitError = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Discard recording and start again")
                    .glassEffect()
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// Solid fallback for post-recording buttons (reduceTransparency).
    @ViewBuilder
    private var solidPostRecordingButtons: some View {
        Button("Send for Transcription") {
            Task { await submitRecording() }
        }
        .buttonStyle(ChurchNotesActionButtonStyle(color: .accentColor))
        .accessibilityLabel("Send recording for AI transcription")
        .accessibilityHint("Uploads recording and generates a transcript draft for your review")

        Button("Discard & Re-record") {
            recorder.discard()
            submitError = nil
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Discard recording and start again")
    }

    /// Glass recording control buttons (mic, pause/resume, stop).
    @ViewBuilder
    private var recordingControlDock: some View {
        if reduceTransparency {
            solidRecordingControls
        } else {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    if recorder.isRecording || recorder.isPaused {
                        Button(action: { recorder.isPaused ? recorder.resume() : recorder.pause() }) {
                            Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                                .font(.title2)
                                .frame(width: 56, height: 56)
                        }
                        .accessibilityLabel(recorder.isPaused ? "Resume recording" : "Pause recording")
                        .glassEffect(in: Circle())
                        .animation(.snappy, value: recorder.isPaused)

                        Button(action: { recorder.stop() }) {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                                .frame(width: 56, height: 56)
                        }
                        .accessibilityLabel("Stop recording")
                        .glassEffect(in: Circle())
                    } else {
                        Button(action: { Task { await recorder.start() } }) {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.red, in: Circle())
                        }
                        .accessibilityLabel("Start recording")
                        .accessibilityHint("Records sermon audio for AI transcription")
                        // Red-filled mic button stays opaque — no glass on content,
                        // only on chrome. The outer circle is the semantic action surface.
                    }
                }
            }
        }
    }

    /// Solid fallback recording controls (reduceTransparency).
    @ViewBuilder
    private var solidRecordingControls: some View {
        HStack(spacing: 32) {
            if recorder.isRecording || recorder.isPaused {
                Button(action: { recorder.isPaused ? recorder.resume() : recorder.pause() }) {
                    Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .accessibilityLabel(recorder.isPaused ? "Resume recording" : "Pause recording")

                Button(action: { recorder.stop() }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(Color.red.opacity(0.15), in: Circle())
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Stop recording")
            } else {
                Button(action: { Task { await recorder.start() } }) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .frame(width: 72, height: 72)
                        .background(Color.red, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Start recording")
                .accessibilityHint("Records sermon audio for AI transcription")
            }
        }
    }

    // MARK: - Actions

    private func checkMicPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:           hasPermission = true
        case .notDetermined:        hasPermission = false
        case .denied, .restricted:  hasPermission = false; showPermissionAlert = true
        @unknown default:           hasPermission = false
        }
    }

    private func requestMicPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        hasPermission = granted
        if !granted { showPermissionAlert = true }
    }

    private func submitRecording() async {
        guard let url = recorder.recordingURL else { return }
        isSubmitting = true
        submitError  = nil

        await processingService.uploadAudioAndCreateJob(
            fileURL: url,
            noteId: noteId,
            durationSeconds: recorder.elapsedSeconds
        )

        isSubmitting = false

        if case .failed(let msg) = processingService.uploadState.phase {
            submitError = msg
        } else {
            onDismiss()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Audio Recorder

@MainActor
final class ChurchNotesAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {

    @Published private(set) var isRecording  = false
    @Published private(set) var isPaused     = false
    @Published private(set) var hasRecording = false
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var recordingURL: URL?

    private var avRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startDate: Date?
    private var accumulatedSeconds: Double = 0

    private let maxDurationSeconds: Double = 7200 // 2h

    func start() async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("church_note_\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey:              Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey:            22050,
                AVNumberOfChannelsKey:      1,
                AVEncoderAudioQualityKey:   AVAudioQuality.medium.rawValue,
                AVEncoderBitRateKey:        64000,
            ]

            avRecorder = try AVAudioRecorder(url: url, settings: settings)
            avRecorder?.delegate = self
            avRecorder?.record()

            recordingURL  = url
            isRecording   = true
            isPaused      = false
            hasRecording  = false
            startDate     = Date()
            accumulatedSeconds = 0
            startTimer()
        } catch {
            // Failure is shown via the parent view's error state.
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        avRecorder?.pause()
        isPaused = true
        accumulatedSeconds = elapsedSeconds
        timer?.invalidate()
    }

    func resume() {
        guard isPaused else { return }
        avRecorder?.record()
        isPaused  = false
        startDate = Date()
        startTimer()
    }

    func stop() {
        avRecorder?.stop()
        isRecording  = false
        isPaused     = false
        hasRecording = recordingURL != nil
        accumulatedSeconds = elapsedSeconds
        timer?.invalidate()
    }

    func discard() {
        avRecorder?.stop()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        avRecorder         = nil
        recordingURL       = nil
        isRecording        = false
        isPaused           = false
        hasRecording       = false
        elapsedSeconds     = 0
        accumulatedSeconds = 0
        timer?.invalidate()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let additional = Date().timeIntervalSince(self.startDate ?? Date())
                let total      = self.accumulatedSeconds + additional
                self.elapsedSeconds = total
                if total >= self.maxDurationSeconds { self.stop() }
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor [weak self] in self?.discard() }
        }
    }
}

// MARK: - Shared button style

struct ChurchNotesActionButtonStyle: ButtonStyle {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 32)
            .animation(reduceMotion ? nil : .amenEaseQuick, value: configuration.isPressed)
    }
}
