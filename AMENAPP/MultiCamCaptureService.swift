import Foundation
import AVFoundation
import UIKit

enum MultiCamCaptureError: LocalizedError {
    case unsupported
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Dual camera capture isn't supported on this device."
        case .configurationFailed:
            return "AMEN couldn't start simultaneous front and back capture."
        case .captureFailed:
            return "AMEN couldn't capture both cameras at once."
        }
    }
}

final class MultiCamCaptureService: NSObject {
    let session = AVCaptureMultiCamSession()
    let sessionQueue = DispatchQueue(label: "amen.witness.multicam.session", qos: .userInitiated)

    let backPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()
    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var isConfigured = false

    private var frontContinuation: CheckedContinuation<UIImage, Error>?
    private var backContinuation: CheckedContinuation<UIImage, Error>?

    override init() {
        backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    var isSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    func configure() async throws {
        guard isSupported else { throw MultiCamCaptureError.unsupported }
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startRunning() {
        sessionQueue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopRunning() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func captureDualPhoto(backFlashMode: AVCaptureDevice.FlashMode) async throws -> (front: UIImage, back: UIImage) {
        guard isConfigured else { throw MultiCamCaptureError.configurationFailed }

        async let frontImage = capturePhoto(output: frontPhotoOutput, role: .front, flashMode: .off)
        async let backImage = capturePhoto(output: backPhotoOutput, role: .back, flashMode: backFlashMode)
        return try await (frontImage, backImage)
    }

    private func capturePhoto(
        output: AVCapturePhotoOutput,
        role: AVCaptureDevice.Position,
        flashMode: AVCaptureDevice.FlashMode
    ) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                if output.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }

                switch role {
                case .front:
                    self.frontContinuation = continuation
                default:
                    self.backContinuation = continuation
                }

                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let backInput {
            session.removeInput(backInput)
        }
        if let frontInput {
            session.removeInput(frontInput)
        }
        if session.outputs.contains(backPhotoOutput) {
            session.removeOutput(backPhotoOutput)
        }
        if session.outputs.contains(frontPhotoOutput) {
            session.removeOutput(frontPhotoOutput)
        }

        guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw MultiCamCaptureError.configurationFailed
        }

        let backInput = try AVCaptureDeviceInput(device: backDevice)
        let frontInput = try AVCaptureDeviceInput(device: frontDevice)
        guard session.canAddInput(backInput), session.canAddInput(frontInput) else {
            throw MultiCamCaptureError.configurationFailed
        }

        session.addInputWithNoConnections(backInput)
        session.addInputWithNoConnections(frontInput)
        self.backInput = backInput
        self.frontInput = frontInput

        guard session.canAddOutput(backPhotoOutput), session.canAddOutput(frontPhotoOutput) else {
            throw MultiCamCaptureError.configurationFailed
        }

        session.addOutputWithNoConnections(backPhotoOutput)
        session.addOutputWithNoConnections(frontPhotoOutput)

        try connectPreviewAndPhoto(for: backInput, output: backPhotoOutput, previewLayer: backPreviewLayer)
        try connectPreviewAndPhoto(for: frontInput, output: frontPhotoOutput, previewLayer: frontPreviewLayer)

        backPhotoOutput.isHighResolutionCaptureEnabled = true
        frontPhotoOutput.isHighResolutionCaptureEnabled = true
        isConfigured = true
    }

    private func connectPreviewAndPhoto(
        for input: AVCaptureDeviceInput,
        output: AVCapturePhotoOutput,
        previewLayer: AVCaptureVideoPreviewLayer
    ) throws {
        guard let videoPort = input.ports.first(where: { $0.mediaType == .video }) else {
            throw MultiCamCaptureError.configurationFailed
        }

        let previewConnection = AVCaptureConnection(inputPort: videoPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else {
            throw MultiCamCaptureError.configurationFailed
        }
        session.addConnection(previewConnection)
        previewConnection.videoOrientation = .portrait

        let photoConnection = AVCaptureConnection(inputPorts: [videoPort], output: output)
        guard session.canAddConnection(photoConnection) else {
            throw MultiCamCaptureError.configurationFailed
        }
        session.addConnection(photoConnection)
        photoConnection.videoOrientation = .portrait
    }
}

extension MultiCamCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            if output == frontPhotoOutput {
                frontContinuation?.resume(throwing: error)
                frontContinuation = nil
            } else {
                backContinuation?.resume(throwing: error)
                backContinuation = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            if output == frontPhotoOutput {
                frontContinuation?.resume(throwing: MultiCamCaptureError.captureFailed)
                frontContinuation = nil
            } else {
                backContinuation?.resume(throwing: MultiCamCaptureError.captureFailed)
                backContinuation = nil
            }
            return
        }

        if output == frontPhotoOutput {
            frontContinuation?.resume(returning: image)
            frontContinuation = nil
        } else {
            backContinuation?.resume(returning: image)
            backContinuation = nil
        }
    }
}
