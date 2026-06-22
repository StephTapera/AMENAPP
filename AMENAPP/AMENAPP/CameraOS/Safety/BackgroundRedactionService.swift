// BackgroundRedactionService.swift
// AMENAPP — Camera OS
// Applies blur/redaction to sensitive regions of images before upload.
// On-device only. No data leaves the device during redaction.

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - BackgroundRedactionService

actor BackgroundRedactionService {

    // MARK: Shared instance

    static let shared = BackgroundRedactionService()

    // MARK: Private dependencies

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: Init

    private init() {}

    // MARK: - Public API

    /// Applies redaction to all suggestions marked `isRedacted == true`.
    /// Returns JPEG data at quality 0.9, or nil if the image cannot be decoded/rendered.
    /// On-device only — no network calls are made.
    func redact(imageData: Data, suggestions: [CameraRedactionSuggestion]) async -> Data? {
        guard let source = UIImage(data: imageData) else { return nil }

        let rects = redactedRects(from: suggestions, imageSize: source.size)
        guard !rects.isEmpty else {
            // Nothing to redact — return original JPEG
            return source.jpegData(compressionQuality: 0.9)
        }

        guard let result = applyFrostingBlur(to: source, rects: rects) else { return nil }
        return result.jpegData(compressionQuality: 0.9)
    }

    /// Returns a preview UIImage with redactions applied. Useful for in-app display before upload.
    func previewRedaction(
        imageData: Data,
        suggestions: [CameraRedactionSuggestion]
    ) async -> UIImage? {
        guard let source = UIImage(data: imageData) else { return nil }

        let rects = redactedRects(from: suggestions, imageSize: source.size)
        guard !rects.isEmpty else { return source }

        return applyFrostingBlur(to: source, rects: rects)
    }

    // MARK: - Frosting Blur (primary compositor)

    /// Draws the original image then composites a heavy blurred overlay over each rect.
    /// Uses CIGaussianBlur per region for authentic pixel-level blur; falls back to
    /// semi-transparent white frost if CIFilter cannot produce output.
    func applyFrostingBlur(to image: UIImage, rects: [CGRect]) -> UIImage? {
        guard !rects.isEmpty else { return image }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let renderer = UIGraphicsImageRenderer(size: size)

        let rendered = renderer.image { ctx in
            // 1. Draw the original image as the base layer
            image.draw(in: CGRect(origin: .zero, size: size))

            // 2. For each rect, composite a blurred tile
            for rect in rects {
                let clampedRect = rect.intersection(CGRect(origin: .zero, size: size))
                guard !clampedRect.isNull,
                      clampedRect.width > 0,
                      clampedRect.height > 0 else { continue }

                if let blurredTile = blurRegion(of: image, rect: clampedRect) {
                    // Draw blurred tile exactly over the sensitive region
                    blurredTile.draw(in: clampedRect)
                } else {
                    // Fallback: semi-opaque white frost rectangle
                    UIColor.white.withAlphaComponent(0.75).setFill()
                    ctx.fill(clampedRect)
                }
            }
        }

        return rendered
    }

    // MARK: - CIFilter region blur

    /// Extracts a region from `image`, applies CIGaussianBlur with radius 20,
    /// and returns the blurred tile as a UIImage sized to `rect`.
    private func blurRegion(of image: UIImage, rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Convert UIKit rect (origin top-left) to CoreImage rect (origin bottom-left)
        let imageHeight = image.size.height
        let ciRect = CGRect(
            x: rect.origin.x,
            y: imageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        let fullCIImage = CIImage(cgImage: cgImage)

        // Crop to the region of interest
        let cropped = fullCIImage.cropped(to: ciRect)

        // Apply Gaussian blur
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = cropped
        filter.radius = 20

        guard let blurredCI = filter.outputImage else { return nil }

        // Crop output to the original region (blur expands bounds slightly)
        let clampedOutput = blurredCI.cropped(to: ciRect)

        guard let cgBlurred = ciContext.createCGImage(clampedOutput, from: ciRect) else {
            return nil
        }

        return UIImage(cgImage: cgBlurred, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Rect conversion

    /// Converts normalizedRect coordinates (0–1, origin bottom-left in CoreGraphics)
    /// into pixel-space UIKit rects (origin top-left) for the given image size.
    private func redactedRects(
        from suggestions: [CameraRedactionSuggestion],
        imageSize: CGSize
    ) -> [CGRect] {
        let width = imageSize.width
        let height = imageSize.height

        return suggestions
            .filter { $0.isRedacted }
            .compactMap { suggestion -> CGRect? in
                let normalized = suggestion.normalizedRect
                guard normalized.width > 0, normalized.height > 0 else { return nil }

                // Flip Y for UIKit coordinates (normalizedRect uses CG-style bottom-left origin)
                return CGRect(
                    x: normalized.minX * width,
                    y: (1.0 - normalized.maxY) * height,
                    width: normalized.width * width,
                    height: normalized.height * height
                )
            }
    }
}
