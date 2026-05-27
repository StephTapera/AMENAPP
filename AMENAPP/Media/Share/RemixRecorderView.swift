import SwiftUI
import AVKit
import AVFoundation

// MARK: - RemixRecorderView
// Full-screen remix recorder: records front-camera reaction while showing
// a thumbnail of the original media in the top-right corner.
// Falls back to single-cam (AVCaptureSession) because AVCaptureMultiCamSession
// requires a device-level entitlement that is not universally available.
// On completion merges original audio with reaction video via AVMutableComposition.

struct RemixRecorderView: View {
    var originalMediaURL: URL
    var onRemixComplete: (URL) -> Void

    @StateObject private var recorder = RemixRecorder()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let maxDuration: Double = 60.0

    var body: some View {
        ZStack {
            cameraPreview
            thumbnailOverlay
            progressBar
            controls
        }
        .ignoresSafeArea()
        .onAppear { recorder.configure() }
        .onDisappear { recorder.teardown() }
        .onChange(of: recorder.recordingComplete) { _, complete in
            if complete, let url = recorder.outputURL {
                mergeAndDeliver(reactionURL: url)
            }
        }
    }

    // MARK: - Camera preview
    private var cameraPreview: some View {
        CameraPreviewRepresentable(session: recorder.session)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    // MARK: - Original media thumbnail (top-right)
    private var thumbnailOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VideoPlayer(player: AVPlayer(url: originalMediaURL))
                    .frame(width: 100, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    }
                    .shadow(
                        color: LiquidGlassTokens.shadowFloating.color,
                        radius: LiquidGlassTokens.shadowFloating.radius,
                        y: LiquidGlassTokens.shadowFloating.y
                    )
                    .padding(.top, 60)
                    .padding(.trailing, 16)
                    .accessibilityLabel("Original media preview")
            }
            Spacer()
        }
    }

    // MARK: - Progress bar
    private var progressBar: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 3)
                    Rectangle()
                        .fill(Color.amenGold)
                        .frame(width: geo.size.width * CGFloat(recorder.elapsed / maxDuration), height: 3)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: recorder.elapsed)
                }
            }
            .frame(height: 3)
            .padding(.top, 8)
            Spacer()
        }
        .accessibilityElement()
        .accessibilityLabel("Recording progress: \(Int(recorder.elapsed)) of \(Int(maxDuration)) seconds")
    }

    // MARK: - Controls
    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                // Dismiss
                Button {
                    recorder.cancelRecording()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(reduceTransparency
                                    ? AnyShapeStyle(Color.black.opacity(0.7))
                                    : AnyShapeStyle(LiquidGlassTokens.blurRegular))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel remix")

                Spacer()

                // Record button
                recordButton

                Spacer()
                // Duration label
                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Elapsed: \(durationText)")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private var recordButton: some View {
        let isRecording = recorder.isRecording
        return Button {
            if isRecording {
                recorder.stopRecording()
            } else {
                recorder.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                RoundedRectangle(
                    cornerRadius: isRecording ? 8 : 36,
                    style: .continuous
                )
                .fill(Color.red)
                .frame(
                    width: isRecording ? 28 : 58,
                    height: isRecording ? 28 : 58
                )
                .animation(
                    reduceMotion ? nil : .spring(response: LiquidGlassTokens.motionFast, dampingFraction: 0.7),
                    value: isRecording
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording remix" : "Start recording remix")
        .accessibilityAddTraits(.isButton)
    }

    private var durationText: String {
        let remaining = max(0, maxDuration - recorder.elapsed)
        let secs = Int(remaining)
        return String(format: "0:%02d", secs)
    }

    // MARK: - Merge + deliver
    private func mergeAndDeliver(reactionURL: URL) {
        Task {
            let merged = await RemixMerger.merge(originalURL: originalMediaURL, reactionURL: reactionURL)
            await MainActor.run {
                onRemixComplete(merged ?? reactionURL)
                dismiss()
            }
        }
    }
}

// MARK: - CameraPreviewRepresentable
struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var session: AVCaptureSession? {
        didSet { previewLayer.session = session }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
    }
}

// MARK: - RemixRecorder
@MainActor
final class RemixRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: Double = 0
    @Published var recordingComplete = false
    @Published var outputURL: URL?

    let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private let maxDuration: Double = 60.0

    func configure() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.setupSession()
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Front camera
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        guard let camera = discovery.devices.first,
              let videoInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // Microphone
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remix_\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed += 0.1
                if self.elapsed >= self.maxDuration {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        movieOutput.stopRecording()
        isRecording = false
    }

    func cancelRecording() {
        stopRecording()
    }

    func teardown() {
        cancelRecording()
        session.stopRunning()
    }
}

extension RemixRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error == nil {
                self.outputURL = outputFileURL
                self.recordingComplete = true
            }
        }
    }
}

// MARK: - RemixMerger
enum RemixMerger {
    /// Merges original audio track with the reaction video track.
    /// Returns merged URL on success, nil on failure (caller falls back to reactionURL).
    static func merge(originalURL: URL, reactionURL: URL) async -> URL? {
        let composition = AVMutableComposition()

        let originalAsset = AVURLAsset(url: originalURL)
        let reactionAsset = AVURLAsset(url: reactionURL)

        do {
            let origDuration = try await originalAsset.load(.duration)
            let reactDuration = try await reactionAsset.load(.duration)
            let mergeDuration = CMTimeMinimum(origDuration, reactDuration)

            // Video track from reaction
            guard let reactionVideoTracks = try? await reactionAsset.loadTracks(withMediaType: .video),
                  let reactionVideoTrack = reactionVideoTracks.first,
                  let compVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { return nil }

            try compVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: mergeDuration),
                of: reactionVideoTrack,
                at: .zero
            )

            // Audio from original
            let origAudioTracks = try await originalAsset.loadTracks(withMediaType: .audio)
            if let origAudioTrack = origAudioTracks.first,
               let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try compAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: mergeDuration),
                    of: origAudioTrack,
                    at: .zero
                )
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("merged_remix_\(UUID().uuidString).mov")

            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else { return nil }

            exporter.outputURL = outputURL
            exporter.outputFileType = .mov

            await exporter.export()
            return exporter.status == .completed ? outputURL : nil
        } catch {
            return nil
        }
    }
}
