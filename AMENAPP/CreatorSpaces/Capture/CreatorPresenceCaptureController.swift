import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class CreatorPresenceCaptureController: NSObject, ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isDualCameraActive = false
    @Published private(set) var isThermalConstrained = false
    @Published var errorMessage: String?

    let session: AVCaptureSession

    private var backPhotoOutput = AVCapturePhotoOutput()
    private var frontPhotoOutput = AVCapturePhotoOutput()
    private var captureContinuation: CheckedContinuation<CreatorPresenceCaptureResult, Error>?
    private var pendingFrames: [String: CreatorPresenceCapturedFrame] = [:]
    private var expectedFrameCount = 0
    private var thermalObserverToken: NSObjectProtocol?

    override init() {
        if AVCaptureMultiCamSession.isMultiCamSupported {
            session = AVCaptureMultiCamSession()
        } else {
            session = AVCaptureSession()
        }
        super.init()
        observeThermalState()
    }

    deinit {
        if let token = thermalObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func requestAndConfigure() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            granted ? configureSession() : setError(CreatorPresenceCaptureError.permissionDenied)
        default:
            setError(CreatorPresenceCaptureError.permissionDenied)
        }
    }

    func start() {
        guard session.isRunning == false else { return }
        session.startRunning()
        isRunning = true
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    func capturePhoto() async throws -> CreatorPresenceCaptureResult {
        guard isConfigured else { throw CreatorPresenceCaptureError.configurationFailed }
        guard !isThermalConstrained else { throw CreatorPresenceCaptureError.cameraUnavailable }

        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            pendingFrames = [:]
            expectedFrameCount = isDualCameraActive ? 2 : 1

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            backPhotoOutput.capturePhoto(with: settings, delegate: self)
            if isDualCameraActive {
                frontPhotoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        let dualConfigured = configureBackCamera() && configureFrontCameraIfSupported()
        if !dualConfigured && session.inputs.isEmpty {
            _ = configureBackCamera()
        }

        session.commitConfiguration()

        isConfigured = !session.inputs.isEmpty
        isDualCameraActive = dualConfigured
        if !isConfigured {
            setError(CreatorPresenceCaptureError.configurationFailed)
        }
    }

    private func configureBackCamera() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        if session.canAddOutput(backPhotoOutput) {
            session.addOutput(backPhotoOutput)
            return true
        }
        return false
    }

    private func configureFrontCameraIfSupported() -> Bool {
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        if session.canAddOutput(frontPhotoOutput) {
            session.addOutput(frontPhotoOutput)
            return true
        }
        return false
    }

    private func observeThermalState() {
        thermalObserverToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateThermalState()
            }
        }
        updateThermalState()
    }

    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        isThermalConstrained = state == .serious || state == .critical
        if isThermalConstrained {
            stop()
        }
    }

    private func setError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func finishIfReady() {
        guard let captureContinuation, pendingFrames.count >= expectedFrameCount else { return }
        let result = CreatorPresenceCaptureResult(
            back: pendingFrames["back"],
            front: pendingFrames["front"],
            capturedAt: Date(),
            isDualCamera: pendingFrames["front"] != nil
        )
        self.captureContinuation = nil
        captureContinuation.resume(returning: result)
    }
}

extension CreatorPresenceCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error {
                captureContinuation?.resume(throwing: error)
                captureContinuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                captureContinuation?.resume(throwing: CreatorPresenceCaptureError.captureFailed)
                captureContinuation = nil
                return
            }
            let size = image.creatorPresencePixelSize
            let key = output === frontPhotoOutput ? "front" : "back"
            pendingFrames[key] = CreatorPresenceCapturedFrame(
                data: data,
                width: size.width,
                height: size.height,
                cameraPosition: key
            )
            finishIfReady()
        }
    }
}

struct CreatorPresencePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
                dlog("Expected AVCaptureVideoPreviewLayer from layerClass")
                return AVCaptureVideoPreviewLayer()
            }
            return previewLayer
        }
    }
}
