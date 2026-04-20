import SwiftUI
import AVFoundation
import AVKit

struct WitnessCameraView: View {
    @ObservedObject var coordinator: CreatePostCameraCoordinator
    @StateObject private var viewModel = WitnessCameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pipLayout = WitnessPiPLayout.default

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let reviewState = viewModel.reviewState {
                WitnessReviewView(
                    reviewState: reviewState,
                    onDiscard: {
                        viewModel.discardReview()
                    },
                    onRetake: {
                        viewModel.discardReview()
                    },
                    onAccept: {
                        viewModel.acceptReview(with: coordinator)
                    }
                )
                .transition(.opacity)
            } else {
                cameraSurface
                    .transition(.opacity)
            }
        }
        .task {
            await viewModel.prepare()
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.handleDismiss()
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                viewModel.startSession()
            default:
                viewModel.handleDismiss()
            }
        }
        .alert("Camera", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            if let message = viewModel.alertMessage, message.contains("access") {
                Button("Settings") {
                    viewModel.permissionManager.openSettings()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var cameraSurface: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.multiCamActive && viewModel.surfaceMode == .photo {
                    WitnessPreviewLayerView(layer: primaryPreviewLayer)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            pipPreview(in: geometry.size)
                                .padding(18)
                        }
                } else {
                    WitnessSinglePreviewView(session: viewModel.singlePreviewSession)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }

                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var topBar: some View {
        HStack {
            liquidButton(icon: "xmark") {
                WitnessCameraAnalytics.track("witness_capture_cancelled", parameters: nil)
                coordinator.dismissCamera()
            }

            Spacer()

            if viewModel.isFlashAvailable && viewModel.surfaceMode == .photo {
                liquidButton(icon: viewModel.flashMode == .off ? "bolt.slash.fill" : "bolt.fill") {
                    viewModel.toggleFlash()
                }
            }

            Text(viewModel.surfaceMode == .photo ? "Photo" : "Video")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(liquidBackground(cornerRadius: 18))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if let reason = viewModel.lastFallbackReason, viewModel.surfaceMode == .video {
                Text(reason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(liquidBackground(cornerRadius: 18))
            }

            HStack(spacing: 12) {
                liquidButton(icon: viewModel.primaryCamera == .back ? "arrow.triangle.2.circlepath.camera" : "person.crop.rectangle") {
                    viewModel.swapPrimaryCamera()
                }

                captureButton

                HStack(spacing: 8) {
                    modePill(title: "Photo", selected: viewModel.surfaceMode == .photo) {
                        viewModel.switchSurfaceMode(.photo)
                    }
                    modePill(title: "Video", selected: viewModel.surfaceMode == .video) {
                        viewModel.switchSurfaceMode(.video)
                    }
                }
            }
        }
    }

    private var captureButton: some View {
        Button {
            Task {
                await viewModel.capture(using: pipLayout)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: 82, height: 82)
                if viewModel.surfaceMode == .video {
                    RoundedRectangle(cornerRadius: viewModel.isRecording ? 10 : 30, style: .continuous)
                        .fill(viewModel.isRecording ? Color.red : Color.black)
                        .frame(width: viewModel.isRecording ? 28 : 56, height: viewModel.isRecording ? 28 : 56)
                } else {
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if viewModel.isRecording {
                ProgressView(value: viewModel.recordingProgress)
                    .progressViewStyle(.linear)
                    .tint(.red)
                    .frame(width: 94)
                    .offset(y: -18)
            }
        }
        .accessibilityLabel(viewModel.surfaceMode == .video ? (viewModel.isRecording ? "Stop recording" : "Start recording") : "Capture photo")
    }

    private func pipPreview(in containerSize: CGSize) -> some View {
        let pipWidth = max(140, containerSize.width * pipLayout.normalizedWidth)
        let pipHeight = max(110, containerSize.height * pipLayout.normalizedHeight)
        let maxX = max(0, containerSize.width * 0.88 - pipWidth)
        let maxY = max(0, containerSize.height * 0.78 - pipHeight)

        return WitnessPreviewLayerView(layer: pipPreviewLayer)
            .frame(width: pipWidth, height: pipHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .offset(
                x: (containerSize.width * pipLayout.normalizedOriginX) - containerSize.width * 0.5,
                y: (containerSize.height * pipLayout.normalizedOriginY) - containerSize.height * 0.5
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let absoluteX = min(max(0, value.location.x - pipWidth * 0.5), maxX)
                        let absoluteY = min(max(0, value.location.y - pipHeight * 0.5), maxY)
                        pipLayout.normalizedOriginX = absoluteX / max(containerSize.width, 1)
                        pipLayout.normalizedOriginY = absoluteY / max(containerSize.height, 1)
                    }
            )
            .onTapGesture {
                if !reduceMotion {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.18)) {
                        viewModel.swapPrimaryCamera()
                    }
                } else {
                    viewModel.swapPrimaryCamera()
                }
            }
    }

    private var primaryPreviewLayer: AVCaptureVideoPreviewLayer {
        viewModel.primaryCamera == .back ? viewModel.backPreviewLayer : viewModel.frontPreviewLayer
    }

    private var pipPreviewLayer: AVCaptureVideoPreviewLayer {
        viewModel.primaryCamera == .back ? viewModel.frontPreviewLayer : viewModel.backPreviewLayer
    }

    private func liquidButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(liquidBackground(cornerRadius: 21))
        }
        .buttonStyle(.plain)
    }

    private func modePill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Group {
                        if selected {
                            Capsule().fill(.white.opacity(0.92))
                        } else {
                            liquidBackground(cornerRadius: 18)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    private func liquidBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            )
    }
}

private struct WitnessPreviewLayerView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> WitnessPreviewHostView {
        let view = WitnessPreviewHostView()
        view.attach(layer: layer)
        return view
    }

    func updateUIView(_ uiView: WitnessPreviewHostView, context: Context) {
        uiView.attach(layer: layer)
    }
}

private struct WitnessSinglePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> WitnessSinglePreviewHostView {
        let view = WitnessSinglePreviewHostView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: WitnessSinglePreviewHostView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class WitnessPreviewHostView: UIView {
    private weak var attachedLayer: AVCaptureVideoPreviewLayer?

    func attach(layer: AVCaptureVideoPreviewLayer) {
        guard attachedLayer !== layer else { return }
        attachedLayer?.removeFromSuperlayer()
        self.layer.masksToBounds = true
        self.layer.addSublayer(layer)
        attachedLayer = layer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}

private final class WitnessSinglePreviewHostView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct WitnessReviewView: View {
    let reviewState: WitnessCaptureReviewState
    let onDiscard: () -> Void
    let onRetake: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if reviewState.attachment.isVideo, let url = reviewState.attachment.finalFileURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else if let url = reviewState.attachment.finalFileURL,
                          let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.black
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            HStack(spacing: 12) {
                reviewButton(title: "Discard", filled: false, action: onDiscard)
                if reviewState.canRetake {
                    reviewButton(title: "Retake", filled: false, action: onRetake)
                }
                reviewButton(title: "Use Capture", filled: true, action: onAccept)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func reviewButton(title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(filled ? .white.opacity(0.94) : .white.opacity(0.12))
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
