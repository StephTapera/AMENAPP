//
//  MediaCaptureCoordinator.swift
//  AMENAPP
//
//  Camera + photo library coordinator.
//  Uses PHPickerViewController (iOS 14+) with UIImagePickerController fallback.
//  Publishes captured items for use by MediaPostComposerView.
//

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - MediaCaptureCoordinator

@MainActor
final class MediaCaptureCoordinator: NSObject, ObservableObject {

    @Published var capturedItems: [ImmersiveCapturedItem] = []
    @Published var isShowingCamera = false
    @Published var isShowingPicker = false
    @Published var captureError: String?

    private var cameraMode: ImmersiveMediaType = .photo
    private var pickerMaxItems: Int = 10

    // MARK: - Public API

    func openCamera(for type: ImmersiveMediaType) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            captureError = "Camera is not available on this device."
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized, .notDetermined:
            cameraMode = type
            isShowingCamera = true
        case .denied, .restricted:
            captureError = "Camera access is required to take photos or videos. Please enable it in Settings."
        @unknown default:
            captureError = "Camera access is unavailable."
        }
    }

    func openPhotoPicker(maxItems: Int = 10) {
        pickerMaxItems = maxItems
        isShowingPicker = true
    }

    func clearAll() {
        capturedItems.removeAll()
    }

    func removeItem(id: UUID) {
        capturedItems.removeAll { $0.id == id }
    }
}

// MARK: - AmenImagePickerView (PHPickerViewController)

struct AmenImagePickerView: UIViewControllerRepresentable {

    @ObservedObject var coordinator: MediaCaptureCoordinator
    var maxItems: Int = 10

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = maxItems
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> PickerCoordinator {
        PickerCoordinator(owner: coordinator)
    }

    // MARK: PHPickerViewControllerDelegate Coordinator

    final class PickerCoordinator: NSObject, PHPickerViewControllerDelegate {

        private let owner: MediaCaptureCoordinator

        init(owner: MediaCaptureCoordinator) {
            self.owner = owner
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            for result in results {
                let provider = result.itemProvider

                if provider.hasItemConformingToTypeIdentifier("public.movie") {
                    // Video
                    provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
                        guard let self, let url else { return }
                        // Copy to temp dir so it remains accessible after picker dismisses
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        try? FileManager.default.copyItem(at: url, to: dest)

                        let item = ImmersiveCapturedItem(
                            type: .video,
                            videoURL: dest
                        )
                        Task { @MainActor in
                            self.owner.capturedItems.append(item)
                        }
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    // Photo
                    provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                        guard let self, let image = object as? UIImage else { return }
                        let item = ImmersiveCapturedItem(
                            type: .photo,
                            image: image
                        )
                        Task { @MainActor in
                            self.owner.capturedItems.append(item)
                        }
                    }
                }
            }

            Task { @MainActor in
                self.owner.isShowingPicker = false
            }
        }
    }
}

// MARK: - MediaCaptureCameraView (UIImagePickerController)

struct MediaCaptureCameraView: UIViewControllerRepresentable {

    @ObservedObject var coordinator: MediaCaptureCoordinator
    var mode: ImmersiveMediaType = .photo

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        switch mode {
        case .photo:
            picker.mediaTypes = ["public.image"]
        case .video:
            picker.mediaTypes = ["public.movie"]
            picker.videoQuality = .typeHigh
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(owner: coordinator)
    }

    // MARK: UIImagePickerControllerDelegate Coordinator

    final class CameraCoordinator: NSObject,
                                   UIImagePickerControllerDelegate,
                                   UINavigationControllerDelegate {

        private let owner: MediaCaptureCoordinator

        init(owner: MediaCaptureCoordinator) {
            self.owner = owner
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)

            if let image = info[.originalImage] as? UIImage {
                // Photo
                let item = ImmersiveCapturedItem(type: .photo, image: image)
                Task { @MainActor in
                    owner.capturedItems.append(item)
                    owner.isShowingCamera = false
                }
            } else if let videoURL = info[.mediaURL] as? URL {
                // Video — copy to temp storage
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                try? FileManager.default.copyItem(at: videoURL, to: dest)
                let item = ImmersiveCapturedItem(type: .video, videoURL: dest)
                Task { @MainActor in
                    owner.capturedItems.append(item)
                    owner.isShowingCamera = false
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            Task { @MainActor in
                owner.isShowingCamera = false
            }
        }
    }
}

// MARK: - PermissionBanner (internal helper used by MediaPostComposerView)

struct MediaPermissionBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AmenTheme.Colors.statusWarning)
                .font(.system(size: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AmenTheme.Colors.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AmenTheme.Colors.textSecondary)
            }

            Spacer()

            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AmenTheme.Colors.amenBlue)
            .accessibilityLabel("Open Settings to grant permission")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
    }
}
