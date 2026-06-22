import Foundation
import AVFoundation
import UIKit

enum SingleCamCaptureError: LocalizedError {
    case cameraUnavailable
    case sessionNotConfigured
    case captureFailed
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "AMEN couldn't access this camera."
        case .sessionNotConfigured:
            return "The camera session isn't ready yet."
        case .captureFailed:
            return "AMEN couldn't capture this photo."
        case .recordingFailed:
            return "AMEN couldn't finish this video."
        }
    }
}

final class SingleCamCaptureService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "amen.witness.singlecam.session", qos: .userInitiated)

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isConfigured = false
    private var photoCaptureContinuation: CheckedContinuation<UIImage, Error>?
    private var recordingContinuation: CheckedContinuation<URL, Error>?
    private var recordingURL: URL?

    func configure(position: AVCaptureDevice.Position, includeAudio: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureSession(position: position, includeAudio: includeAudio)
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

    func switchCamera() async throws -> AVCaptureDevice.Position {
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        try await configure(position: newPosition, includeAudio: audioInput != nil)
        return newPosition
    }

    func capturePhoto(flashMode: AVCaptureDevice.FlashMode) async throws -> UIImage {
        guard isConfigured else { throw SingleCamCaptureError.sessionNotConfigured }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(flashMode) {
                    settings.flashMode = flashMode
                }
                self.photoCaptureContinuation = continuation
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func startRecording() async throws {
        guard isConfigured else { throw SingleCamCaptureError.sessionNotConfigured }
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard !self.movieOutput.isRecording else {
                    continuation.resume()
                    return
                }

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                self.recordingURL = outputURL

                if let connection = self.movieOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }

                self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
                continuation.resume()
            }
        }
    }

    func stopRecording() async throws -> URL {
        guard isConfigured else { throw SingleCamCaptureError.sessionNotConfigured }
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.movieOutput.isRecording else {
                    continuation.resume(throwing: SingleCamCaptureError.recordingFailed)
                    return
                }
                self.recordingContinuation = continuation
                self.movieOutput.stopRecording()
            }
        }
    }

    func isFlashAvailable() -> Bool {
        guard let device = videoInput?.device else { return false }
        return device.hasFlash && currentPosition == .back
    }

    private func configureSession(position: AVCaptureDevice.Position, includeAudio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        if let videoInput {
            session.removeInput(videoInput)
        }
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
        if session.outputs.contains(photoOutput) {
            session.removeOutput(photoOutput)
        }
        if session.outputs.contains(movieOutput) {
            session.removeOutput(movieOutput)
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw SingleCamCaptureError.cameraUnavailable
        }

        let newVideoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newVideoInput) else {
            throw SingleCamCaptureError.cameraUnavailable
        }
        session.addInput(newVideoInput)
        self.videoInput = newVideoInput
        self.currentPosition = position

        if includeAudio,
           let mic = AVCaptureDevice.default(for: .audio) {
            let newAudioInput = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(newAudioInput) {
                session.addInput(newAudioInput)
                self.audioInput = newAudioInput
            }
        }

        guard session.canAddOutput(photoOutput) else {
            throw SingleCamCaptureError.cameraUnavailable
        }
        session.addOutput(photoOutput)
        if let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = maxDimensions
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        isConfigured = true
    }
}

extension SingleCamCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoCaptureContinuation?.resume(throwing: error)
            photoCaptureContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            photoCaptureContinuation?.resume(throwing: SingleCamCaptureError.captureFailed)
            photoCaptureContinuation = nil
            return
        }

        photoCaptureContinuation?.resume(returning: image)
        photoCaptureContinuation = nil
    }
}

extension SingleCamCaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error {
            recordingContinuation?.resume(throwing: error)
            recordingContinuation = nil
            return
        }

        recordingContinuation?.resume(returning: outputFileURL)
        recordingContinuation = nil
    }
}
