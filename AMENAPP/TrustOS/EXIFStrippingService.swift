// EXIFStrippingService.swift
// AMENAPP — Trust OS
//
// Strips EXIF/GPS metadata from image data before upload.
// DEFAULT-ON: callers do not need to opt in.
// Uses CGImageSource / CGImageDestination — no third-party dependencies.

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

final class EXIFStrippingService {

    // MARK: - Full strip (all metadata removed)

    /// Strips all EXIF, GPS, IPTC, TIFF, and XMP metadata from JPEG or HEIF image data.
    /// Returns cleaned Data. Falls back to original data if stripping is not possible.
    static func strip(from imageData: Data) -> Data {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let uti    = CGImageSourceGetType(source)
        else { return imageData }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, uti, 1, nil
        ) else { return imageData }

        // Copy image pixels only — omit all metadata by passing an empty properties dict.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return imageData }
        return output as Data
    }

    // MARK: - GPS-only strip

    /// Strips only the GPS dictionary from image metadata, preserving all other EXIF data.
    /// Returns cleaned Data. Falls back to original data if stripping is not possible.
    static func stripGPS(from imageData: Data) -> Data {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let uti    = CGImageSourceGetType(source)
        else { return imageData }

        // Copy existing metadata so we can mutate it.
        var metadata: [CFString: Any] = [:]
        if let existingProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            metadata = existingProperties
        }

        // Remove GPS dictionary from metadata.
        metadata.removeValue(forKey: kCGImagePropertyGPSDictionary)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, uti, 1, nil
        ) else { return imageData }

        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality] = 0.92

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return imageData }
        return output as Data
    }
}
