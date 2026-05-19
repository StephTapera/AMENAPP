// AmenCameraView.swift
// AMENAPP
// Camera capture wrapper for Universal Create.

import SwiftUI
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

enum AmenCameraCapture {
    case image(UIImage)
    case video(URL)
}

struct AmenCameraView: UIViewControllerRepresentable {
    let onComplete: (AmenCameraCapture?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (AmenCameraCapture?) -> Void

        init(onComplete: @escaping (AmenCameraCapture?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let mediaType = info[.mediaType] as? String, mediaType == UTType.movie.identifier,
               let url = info[.mediaURL] as? URL {
                onComplete(.video(url))
                return
            }

            if let image = info[.originalImage] as? UIImage {
                onComplete(.image(image))
                return
            }

            onComplete(nil)
        }
    }
}
