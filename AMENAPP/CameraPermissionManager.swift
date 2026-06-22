import Foundation
import AVFoundation
import UIKit

enum CameraPermissionError: LocalizedError, Equatable {
    case cameraDenied
    case microphoneDenied
    case restricted

    var errorDescription: String? {
        switch self {
        case .cameraDenied:
            return "Camera access is required to capture witness media."
        case .microphoneDenied:
            return "Microphone access is required to record witness video."
        case .restricted:
            return "Camera access is restricted on this device."
        }
    }
}

struct CameraPermissionState: Equatable {
    var camera: AVAuthorizationStatus
    var microphone: AVAuthorizationStatus

    var canCapturePhoto: Bool {
        camera == .authorized
    }

    var canCaptureVideo: Bool {
        camera == .authorized && microphone == .authorized
    }
}

@MainActor
final class CameraPermissionManager: ObservableObject {
    @Published private(set) var state = CameraPermissionState(
        camera: AVCaptureDevice.authorizationStatus(for: .video),
        microphone: AVCaptureDevice.authorizationStatus(for: .audio)
    )

    func refresh() {
        state = CameraPermissionState(
            camera: AVCaptureDevice.authorizationStatus(for: .video),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    func requestPhotoPermissions() async throws {
        let cameraStatus = try await requestAccess(for: .video)
        refresh()

        switch cameraStatus {
        case .authorized:
            return
        case .restricted:
            throw CameraPermissionError.restricted
        default:
            throw CameraPermissionError.cameraDenied
        }
    }

    func requestVideoPermissions() async throws {
        let cameraStatus = try await requestAccess(for: .video)
        guard cameraStatus == .authorized else {
            refresh()
            if cameraStatus == .restricted {
                throw CameraPermissionError.restricted
            }
            throw CameraPermissionError.cameraDenied
        }

        let micStatus = try await requestAccess(for: .audio)
        refresh()

        switch micStatus {
        case .authorized:
            return
        case .restricted:
            throw CameraPermissionError.restricted
        default:
            throw CameraPermissionError.microphoneDenied
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestAccess(for mediaType: AVMediaType) async throws -> AVAuthorizationStatus {
        let current = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch current {
        case .authorized, .denied, .restricted:
            return current
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: mediaType)
            return granted ? .authorized : .denied
        @unknown default:
            return .denied
        }
    }
}
