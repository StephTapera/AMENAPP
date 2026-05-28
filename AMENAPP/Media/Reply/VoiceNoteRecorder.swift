import SwiftUI
import AVFoundation

struct VoiceNoteRecorder: View {
    @Binding var isRecording: Bool
    var onRecordingComplete: (URL) -> Void

    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var permissionGranted = false
    @State private var barHeights: [CGFloat] = [20, 30, 25, 35, 22]
    @State private var animationTimer: Timer?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 16) {
            if isRecording {
                waveformView
            }
            recordButton
        }
        .onAppear { requestPermission() }
        .onDisappear { stopAnimation() }
    }

    private var waveformView: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.purple)
                    .frame(width: 6, height: reduceMotion ? 30 : barHeights[i])
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.15),
                        value: barHeights[i]
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(.systemBackground))
            } else {
                Capsule().fill(LiquidGlassTokens.blurThin)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
            }
        }
        .frame(height: 52)
    }

    private var recordButton: some View {
        Button {
            // tap-to-toggle fallback; primary use is long-press from caller
        } label: {
            Circle()
                .fill(isRecording ? Color.red : Color.white.opacity(0.9))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isRecording ? .white : .black)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in startRecording() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in if isRecording { stopRecording() } }
        )
        .accessibilityLabel(isRecording ? "Stop recording" : "Hold to record voice note")
        .accessibilityAddTraits(.isButton)
    }

    private func requestPermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { permissionGranted = granted }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { permissionGranted = granted }
            }
        }
    }

    private func startRecording() {
        guard permissionGranted else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        recordingURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        try? AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        isRecording = true
        startAnimation()
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        stopAnimation()
        if let url = recordingURL {
            onRecordingComplete(url)
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            barHeights = (0..<5).map { _ in CGFloat.random(in: 12...50) }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
