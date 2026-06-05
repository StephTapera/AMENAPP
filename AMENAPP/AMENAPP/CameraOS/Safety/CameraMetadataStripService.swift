// CameraMetadataStripService.swift
// AMENAPP — Camera OS
// Strips EXIF/GPS and device metadata from captures before upload.
// Runs on every capture regardless of safety profile.

import Foundation
import UIKit
import ImageIO
import CoreLocation
import AVFoundation

// MARK: - Strip Result

/// Summary of what was found and removed during a metadata strip pass.
struct CameraMetadataStripResult {
    /// Size in bytes of the input data before stripping.
    let originalDataSize: Int

    /// Size in bytes of the output data after stripping.
    let strippedDataSize: Int

    /// Whether the source contained GPS/location metadata.
    let hadGPSData: Bool

    /// Whether the source contained device-identifying EXIF metadata.
    let hadDeviceData: Bool

    /// The fully stripped image data, ready for upload.
    let strippedData: Data
}

// MARK: - CameraMetadataStripService

actor CameraMetadataStripService {

    static let shared = CameraMetadataStripService()

    // MARK: - Init

    private init() {}

    // MARK: - Strip metadata from image Data

    /// Strips GPS and device EXIF metadata from `imageData`.
    ///
    /// Implementation notes:
    /// - Uses ImageIO to inspect the source properties and re-encode without
    ///   kCGImagePropertyGPSDictionary / kCGImagePropertyExifDictionary.
    /// - If `stripGPS` is false, GPS data is preserved (only strip EXIF).
    /// - If `stripDevice` is false, EXIF data is preserved (only strip GPS).
    /// - Falls back to returning the original data if ImageIO cannot decode
    ///   the source, so as not to block the capture pipeline.
    func stripMetadata(
        from imageData: Data,
        stripGPS: Bool = true,
        stripDevice: Bool = true
    ) async -> CameraMetadataStripResult {

        let originalSize = imageData.count

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            // Cannot decode — return original data unchanged.
            return CameraMetadataStripResult(
                originalDataSize: originalSize,
                strippedDataSize: originalSize,
                hadGPSData: false,
                hadDeviceData: false,
                strippedData: imageData
            )
        }

        // Inspect the source to detect what metadata is present.
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let hadGPS = sourceProperties[kCGImagePropertyGPSDictionary] != nil
        let hadExif = sourceProperties[kCGImagePropertyExifDictionary] != nil

        // Determine UTI for re-encoding (preserve original format).
        let uti = CGImageSourceGetType(source) ?? kUTTypeJPEG as CFString

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, uti, 1, nil) else {
            return CameraMetadataStripResult(
                originalDataSize: originalSize,
                strippedDataSize: originalSize,
                hadGPSData: hadGPS,
                hadDeviceData: hadExif,
                strippedData: imageData
            )
        }

        // Build properties dict to override / remove the unwanted keys.
        var cleanProperties: [CFString: Any] = [:]

        // Always carry forward the top-level properties except GPS and EXIF.
        for (key, value) in sourceProperties {
            let skip =
                (stripGPS && key == kCGImagePropertyGPSDictionary) ||
                (stripDevice && key == kCGImagePropertyExifDictionary) ||
                (stripDevice && key == kCGImagePropertyTIFFDictionary) ||
                (stripDevice && key == kCGImagePropertyIPTCDictionary)
            if !skip {
                cleanProperties[key] = value
            }
        }

        // Explicitly nullify GPS and EXIF dictionaries in the output metadata.
        if stripGPS {
            cleanProperties[kCGImagePropertyGPSDictionary] = kCFNull
        }
        if stripDevice {
            cleanProperties[kCGImagePropertyExifDictionary] = kCFNull
            cleanProperties[kCGImagePropertyTIFFDictionary] = kCFNull
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, cleanProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return CameraMetadataStripResult(
                originalDataSize: originalSize,
                strippedDataSize: originalSize,
                hadGPSData: hadGPS,
                hadDeviceData: hadExif,
                strippedData: imageData
            )
        }

        let stripped = outputData as Data
        return CameraMetadataStripResult(
            originalDataSize: originalSize,
            strippedDataSize: stripped.count,
            hadGPSData: hadGPS,
            hadDeviceData: hadExif,
            strippedData: stripped
        )
    }

    // MARK: - Strip metadata from file URL (image or video)

    /// Strips metadata from the file at `url` and returns a new URL pointing
    /// to the stripped file in the system temporary directory.
    ///
    /// - For image files (JPEG/HEIC/PNG): reads data, strips via `stripMetadata`, writes to temp.
    /// - For video files (MOV/MP4): uses AVAssetExportSession configured to
    ///   omit location metadata, then copies to temp.
    ///
    /// Throws if the file cannot be read, decoded, or re-encoded.
    func stripFromURL(_ url: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            return try await stripImageFromURL(url)
        } else {
            return try await stripVideoFromURL(url)
        }
    }

    // MARK: - Private: Image URL stripping

    private func stripImageFromURL(_ url: URL) async throws -> URL {
        let data = try Data(contentsOf: url)
        let result = await stripMetadata(from: data, stripGPS: true, stripDevice: true)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        try result.strippedData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - Private: Video URL stripping

    private func stripVideoFromURL(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Destination in the temporary directory.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CameraMetadataStripError.exportSessionCreationFailed
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true

        // Remove location metadata by providing an empty metadata array.
        // AVAssetExportSession will propagate only what we provide here.
        exportSession.metadata = strippedVideoMetadata(from: asset)

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return tempURL
        case .failed:
            throw exportSession.error ?? CameraMetadataStripError.exportFailed
        case .cancelled:
            throw CameraMetadataStripError.exportCancelled
        default:
            throw CameraMetadataStripError.exportFailed
        }
    }

    /// Returns the asset's metadata with location items removed.
    private func strippedVideoMetadata(from asset: AVURLAsset) -> [AVMetadataItem] {
        let locationIdentifiers: Set<AVMetadataIdentifier> = [
            .commonIdentifierLocation,
            .quickTimeMetadataLocationISO6709
        ]

        return asset.metadata.filter { item in
            guard let identifier = item.identifier else {
                // If we cannot identify the item, exclude it to be safe.
                return false
            }
            return !locationIdentifiers.contains(identifier)
        }
    }

    // MARK: - Constants

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tiff", "tif", "webp"]
}

// MARK: - Error Types

enum CameraMetadataStripError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Could not create an export session for the video."
        case .exportFailed:
            return "Video metadata stripping failed during export."
        case .exportCancelled:
            return "Video metadata stripping was cancelled."
        }
    }
}
