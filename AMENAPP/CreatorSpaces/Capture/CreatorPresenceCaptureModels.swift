import Foundation
import UIKit

struct CreatorPresenceCapturedFrame: Sendable {
    var data: Data
    var width: Int
    var height: Int
    var cameraPosition: String
}

struct CreatorPresenceCaptureResult: Sendable {
    var back: CreatorPresenceCapturedFrame?
    var front: CreatorPresenceCapturedFrame?
    var capturedAt: Date
    var isDualCamera: Bool
}

struct CreatorPresenceCompositeResult: Sendable {
    var frame: CreatorPresenceCapturedFrame
    var layout: CreatorFrameLayout
}

struct CreatorPresenceUploadResult: Sendable {
    var assetId: String
    var labelId: String
}

enum CreatorPresenceCaptureMode: String, CaseIterable, Identifiable {
    case photo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "Photo"
        }
    }
}

enum CreatorPresenceCaptureError: LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case configurationFailed
    case captureFailed
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .permissionDenied:
            return "Camera permission is required for Presence Posts."
        case .configurationFailed:
            return "Presence capture could not be configured."
        case .captureFailed:
            return "Presence capture failed."
        case .uploadFailed:
            return "Presence media upload failed."
        }
    }
}

extension UIImage {
    var creatorPresencePixelSize: (width: Int, height: Int) {
        let scaledWidth = Int(size.width * scale)
        let scaledHeight = Int(size.height * scale)
        return (max(1, scaledWidth), max(1, scaledHeight))
    }
}

enum CreatorPresenceImageCompositor {
    static func composite(_ capture: CreatorPresenceCaptureResult, layout: CreatorFrameLayout) -> CreatorPresenceCompositeResult? {
        guard let back = capture.back, let backImage = UIImage(data: back.data) else {
            return capture.front.flatMap { front in
                guard let image = UIImage(data: front.data),
                      let data = image.jpegData(compressionQuality: 0.92) else { return nil }
                let size = image.creatorPresencePixelSize
                return CreatorPresenceCompositeResult(
                    frame: CreatorPresenceCapturedFrame(data: data, width: size.width, height: size.height, cameraPosition: "composite"),
                    layout: layout
                )
            }
        }

        guard let front = capture.front, let frontImage = UIImage(data: front.data) else {
            guard let data = backImage.jpegData(compressionQuality: 0.92) else { return nil }
            let size = backImage.creatorPresencePixelSize
            return CreatorPresenceCompositeResult(
                frame: CreatorPresenceCapturedFrame(data: data, width: size.width, height: size.height, cameraPosition: "composite"),
                layout: layout
            )
        }

        let composedImage: UIImage
        switch layout {
        case .pip:
            composedImage = pip(back: backImage, front: frontImage)
        case .split:
            composedImage = split(back: backImage, front: frontImage)
        case .stacked:
            composedImage = stacked(back: backImage, front: frontImage)
        }

        guard let data = composedImage.jpegData(compressionQuality: 0.9) else { return nil }
        let size = composedImage.creatorPresencePixelSize
        return CreatorPresenceCompositeResult(
            frame: CreatorPresenceCapturedFrame(data: data, width: size.width, height: size.height, cameraPosition: "composite"),
            layout: layout
        )
    }

    private static func pip(back: UIImage, front: UIImage) -> UIImage {
        render(size: back.size) { bounds in
            back.draw(in: bounds)
            let inset = max(16, min(bounds.width, bounds.height) * 0.045)
            let pipWidth = bounds.width * 0.34
            let pipHeight = pipWidth * (front.size.height / max(front.size.width, 1))
            let pipRect = CGRect(
                x: bounds.maxX - pipWidth - inset,
                y: bounds.maxY - pipHeight - inset,
                width: pipWidth,
                height: pipHeight
            )
            UIColor.black.withAlphaComponent(0.28).setFill()
            UIBezierPath(roundedRect: pipRect.insetBy(dx: -4, dy: -4), cornerRadius: 18).fill()
            front.draw(in: pipRect)
        }
    }

    private static func split(back: UIImage, front: UIImage) -> UIImage {
        let targetSize = CGSize(width: max(back.size.width, front.size.width), height: max(back.size.height, front.size.height))
        return render(size: targetSize) { bounds in
            back.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height))
            front.draw(in: CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height))
        }
    }

    private static func stacked(back: UIImage, front: UIImage) -> UIImage {
        let targetSize = CGSize(width: max(back.size.width, front.size.width), height: max(back.size.height, front.size.height))
        return render(size: targetSize) { bounds in
            back.draw(in: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height / 2))
            front.draw(in: CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height / 2))
        }
    }

    private static func render(size: CGSize, draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(CGRect(origin: .zero, size: size))
        }
    }
}
