import SwiftUI
import AVFoundation
import AVKit

struct RemixRecorderView: View {
    var originalMediaURL: URL
    var onRemixComplete: (URL) -> Void

    @State private var session: AVCaptureSession?
    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var outputURL: URL?
    @State private var recordingTimer: Timer?
    @State private var elapsedSeconds: Double = 0
    @Environment(\.dismiss) private var dismiss

    private let maxDuration: Double = 60

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Original media thumbnail (top half)
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Text("Original Media")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    )
                    .frame(maxHeight: .infinity)

                Divider().background(Color.white.opacity(0.3))

                // Live camera preview placeholder (bottom half)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.4))
                    )
                    .frame(maxHeight: .infinity)
            }
            .ignoresSafeArea()

            // Progress bar
            VStack {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * recordingProgress, height: 3)
                        .animation(.linear(duration: 0.1), value: recordingProgress)
                }
                .frame(height: 3)
                Spacer()
            }

            // Controls
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .accessibilityLabel("Cancel remix")
                    Spacer()
                }
                Spacer()
                recordButton
                    .padding(.bottom, 40)
            }
        }
    }

    private var recordButton: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Circle()
                .fill(isRecording ? Color.white : Color.red)
                .frame(width: 72, height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: isRecording ? 6 : 36)
                        .fill(isRecording ? Color.red : Color.clear)
                        .frame(width: isRecording ? 28 : 72, height: isRecording ? 28 : 72)
                        .animation(.spring(response: 0.28), value: isRecording)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording remix")
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        outputURL = url
        isRecording = true
        elapsedSeconds = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedSeconds += 0.1
            recordingProgress = min(elapsedSeconds / maxDuration, 1.0)
            if elapsedSeconds >= maxDuration { stopRecording() }
        }
    }

    private func stopRecording() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        if let url = outputURL {
            // In production: merge original + camera footage here via AVMutableComposition
            onRemixComplete(url)
        }
        dismiss()
    }
}
