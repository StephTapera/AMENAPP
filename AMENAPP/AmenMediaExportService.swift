// AmenMediaExportService.swift
// AMENAPP
// Media export utilities (trim, thumbnail, voiceover).

import Foundation
import AVFoundation
import UIKit

enum AmenMediaExportError: Error {
    case cannotCreateExportSession
    case exportFailed
}

struct AmenMediaExportService {
    static func trimVideo(sourceURL: URL, startTime: Double, endTime: Double) async throws -> URL {
        let asset = AVAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw AmenMediaExportError.cannotCreateExportSession
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amen_trim_\(UUID().uuidString).mp4")

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        let start = CMTime(seconds: max(0, startTime), preferredTimescale: 600)
        let end = CMTime(seconds: max(startTime, endTime), preferredTimescale: 600)
        exporter.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                default:
                    continuation.resume(throwing: AmenMediaExportError.exportFailed)
                }
            }
        }
    }

    static func generateThumbnail(from url: URL, at time: Double) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
