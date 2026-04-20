import Foundation
import UIKit
import AVFoundation

enum WitnessMediaComposerError: LocalizedError {
    case invalidImageData
    case unableToWriteAsset
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "The captured media could not be processed."
        case .unableToWriteAsset:
            return "AMEN couldn't save the witness media."
        case .thumbnailGenerationFailed:
            return "AMEN couldn't generate a preview for the witness media."
        }
    }
}

enum WitnessMediaComposer {
    static func composeDualPhoto(
        primary: UIImage,
        pip: UIImage,
        layout: WitnessPiPLayout
    ) throws -> (finalURL: URL, thumbnailURL: URL, size: CGSize) {
        let baseSize = normalizedCanvasSize(for: primary.size)
        let pipRect = CGRect(
            x: layout.normalizedOriginX * baseSize.width,
            y: layout.normalizedOriginY * baseSize.height,
            width: layout.normalizedWidth * baseSize.width,
            height: layout.normalizedHeight * baseSize.height
        )

        let renderer = UIGraphicsImageRenderer(size: baseSize)
        let composite = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: baseSize))

            primary.draw(in: CGRect(origin: .zero, size: baseSize))

            let pipPath = UIBezierPath(roundedRect: pipRect, cornerRadius: 26)
            context.cgContext.saveGState()
            pipPath.addClip()
            pip.draw(in: pipRect)
            context.cgContext.restoreGState()

            UIColor(white: 1.0, alpha: 0.42).setStroke()
            pipPath.lineWidth = 2
            pipPath.stroke()
        }

        let finalURL = tempURL(extension: "jpg")
        let thumbnailURL = tempURL(extension: "jpg")
        guard let finalData = composite.jpegData(compressionQuality: 0.92),
              let thumbnailData = composite.preparingThumbnail(of: CGSize(width: 640, height: 640))?.jpegData(compressionQuality: 0.82) else {
            throw WitnessMediaComposerError.invalidImageData
        }

        try finalData.write(to: finalURL, options: .atomic)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
        return (finalURL, thumbnailURL, baseSize)
    }

    static func prepareSinglePhoto(_ image: UIImage) throws -> (finalURL: URL, thumbnailURL: URL, size: CGSize) {
        let finalURL = tempURL(extension: "jpg")
        let thumbnailURL = tempURL(extension: "jpg")
        guard let finalData = image.jpegData(compressionQuality: 0.92),
              let thumbnailData = image.preparingThumbnail(of: CGSize(width: 640, height: 640))?.jpegData(compressionQuality: 0.82) else {
            throw WitnessMediaComposerError.invalidImageData
        }

        try finalData.write(to: finalURL, options: .atomic)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
        return (finalURL, thumbnailURL, image.size)
    }

    static func prepareSingleVideo(_ sourceURL: URL) async throws -> (videoURL: URL, thumbnailURL: URL, duration: Double, size: CGSize) {
        let compressedURL = await VideoAttachmentService.compress(sourceURL)
        let asset = AVAsset(url: compressedURL)
        let duration: Double
        let naturalSize: CGSize

        if #available(iOS 16, *) {
            duration = try await asset.load(.duration).seconds
            let track = try await asset.loadTracks(withMediaType: .video).first
            naturalSize = try await track?.load(.naturalSize) ?? CGSize(width: 1080, height: 1920)
        } else {
            duration = asset.duration.seconds
            naturalSize = asset.tracks(withMediaType: .video).first?.naturalSize ?? CGSize(width: 1080, height: 1920)
        }

        guard let thumbnail = VideoAttachmentService.thumbnail(for: compressedURL),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.82) else {
            throw WitnessMediaComposerError.thumbnailGenerationFailed
        }

        let thumbnailURL = tempURL(extension: "jpg")
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
        return (compressedURL, thumbnailURL, duration, naturalSize)
    }

    static func removeLocalAssets(for attachment: WitnessDraftAttachment) {
        let urls = [
            attachment.finalAsset.localPath,
            attachment.thumbnailAsset?.localPath,
            attachment.frontAsset?.localPath,
            attachment.backAsset?.localPath
        ]
            .compactMap { $0 }
            .map(URL.init(fileURLWithPath:))

        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func normalizedCanvasSize(for original: CGSize) -> CGSize {
        let maxDimension: CGFloat = 1600
        guard max(original.width, original.height) > maxDimension else { return original }
        let scale = maxDimension / max(original.width, original.height)
        return CGSize(width: floor(original.width * scale), height: floor(original.height * scale))
    }

    private static func tempURL(`extension`: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(`extension`)
    }
}
