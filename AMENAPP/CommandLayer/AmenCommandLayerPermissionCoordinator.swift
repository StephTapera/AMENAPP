import AVFoundation
import Foundation
import Photos
import UIKit

enum AmenCommandLayerPermissionType: String, Equatable {
    case camera
    case photos
    case microphone
    case files
}

enum AmenCommandLayerPermissionStatus: Equatable {
    case granted
    case limited
    case denied
    case unavailable(String)

    var canProceed: Bool {
        switch self {
        case .granted, .limited:
            return true
        case .denied, .unavailable:
            return false
        }
    }

    var recoveryMessage: String {
        switch self {
        case .granted:
            return "Permission granted."
        case .limited:
            return "Amen can access only selected photos. You can manage access in Settings."
        case .denied:
            return "Permission is denied. You can enable access in Settings."
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
enum AmenCommandLayerPermissionCoordinator {
    static func permissionType(for action: AmenCommandLayerActionID) -> AmenCommandLayerPermissionType? {
        switch action {
        case .camera:
            return .camera
        case .photos:
            return .photos
        case .addFiles:
            return .files
        case .aiMeetingNotes:
            return .microphone
        default:
            return nil
        }
    }

    static func currentStatus(for type: AmenCommandLayerPermissionType) -> AmenCommandLayerPermissionStatus {
        switch type {
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                return .unavailable("Camera is not available on this device.")
            }
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .photos:
            return mapPhotoStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .microphone:
            return mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .files:
            return .granted
        }
    }

    static func requestPermissionIfNeeded(for type: AmenCommandLayerPermissionType) async -> AmenCommandLayerPermissionStatus {
        let current = currentStatus(for: type)
        switch current {
        case .granted, .limited, .denied, .unavailable:
            if current != .denied && current.canProceed {
                return current
            }
        }

        switch type {
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                return .unavailable("Camera is not available on this device.")
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .granted : .denied
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return mapPhotoStatus(status)
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        case .files:
            return .granted
        }
    }

    private static func mapAVStatus(_ status: AVAuthorizationStatus) -> AmenCommandLayerPermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .unavailable("Permission has not been requested yet.")
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unavailable("Permission status is unavailable.")
        }
    }

    private static func mapPhotoStatus(_ status: PHAuthorizationStatus) -> AmenCommandLayerPermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .limited:
            return .limited
        case .notDetermined:
            return .unavailable("Photo access has not been requested yet.")
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unavailable("Photo access status is unavailable.")
        }
    }
}

extension AmenCommandLayerActionID {
    var commandLayerPermissionType: AmenCommandLayerPermissionType? {
        AmenCommandLayerPermissionCoordinator.permissionType(for: self)
    }
}
