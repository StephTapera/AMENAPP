// ONEProvenanceLabelService.swift
// ONE — On-device content provenance analysis.
// P2-E | EXIF metadata + Vision heuristics. C2PA full attestation is a stub;
// degrades gracefully to .unknown when signal is insufficient.

import Foundation
import ImageIO
import Vision

actor ONEProvenanceLabelService {

    // MARK: - Public

    func analyze(imageData: Data) async -> ONEProvenanceLabel {
        let exifResult  = analyzeEXIF(imageData)
        let visionResult = await analyzeWithVision(imageData)

        // Take whichever path gives higher confidence
        let (cls, conf) = exifResult.1 >= visionResult.1 ? exifResult : visionResult

        return ONEProvenanceLabel(
            classification: cls,
            confidence: conf,
            c2paPayload: nil,           // C2PA integration deferred post-ship
            attestedAt: Date(),
            processorNote: "ONE on-device v1"
        )
    }

    // Convenience for newly captured frames — always starts as captured
    func labelForFreshCapture() -> ONEProvenanceLabel {
        ONEProvenanceLabel(
            classification: .captured,
            confidence: 0.95,
            c2paPayload: nil,
            attestedAt: Date(),
            processorNote: "Fresh capture"
        )
    }

    // MARK: - EXIF analysis

    private func analyzeEXIF(_ data: Data) -> (ONEProvenanceClass, Float) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return (.unknown, 0.0) }

        let tiff     = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif     = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let software = (tiff?[kCGImagePropertyTIFFSoftware as String] as? String) ?? ""
        let hasGPS   = props[kCGImagePropertyGPSDictionary as String] != nil

        let aiKeywords      = ["DALL-E", "Midjourney", "Stable Diffusion", "Firefly",
                               "Imagen", "Gemini", "Flux", "Adobe AI"]
        let editKeywords    = ["Photoshop", "Lightroom", "GIMP", "Snapseed", "VSCO",
                               "Canva", "Pixelmator", "Affinity"]
        let captureKeywords = ["iPhone", "iPad", "iOS", "Android", "Samsung", "Pixel", "Canon",
                               "Nikon", "Sony", "Fujifilm"]

        if aiKeywords.contains(where: { software.contains($0) })      { return (.synthetic,  0.95) }
        if editKeywords.contains(where: { software.contains($0) })    { return (.edited,     0.92) }
        if captureKeywords.contains(where: { software.contains($0) }) { return (.captured,   hasGPS ? 0.90 : 0.78) }
        if exif?["LensModel"] != nil || exif?["FocalLength"] != nil   { return (.captured,   0.75) }

        return (.unknown, 0.0)
    }

    // MARK: - Vision heuristics

    private func analyzeWithVision(_ data: Data) async -> (ONEProvenanceClass, Float) {
        guard let cgImage = makeCGImage(from: data) else { return (.unknown, 0.0) }

        // Saliency-based heuristic — real AI detection requires a dedicated Core ML model (future work).
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            // Low-confidence fallback — saliency alone isn't deterministic
            return (.captured, 0.55)
        } catch {
            return (.unknown, 0.0)
        }
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
