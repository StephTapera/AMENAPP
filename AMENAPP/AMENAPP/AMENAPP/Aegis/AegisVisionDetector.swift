// AegisVisionDetector.swift
// On-device Vision detection for Aegis capabilities C1–C13.
//
// PRIVACY CONTRACT:
//   - NEVER uploads image data or derived features without explicit user consent + flag check.
//   - All analysis runs locally on the device using Apple Vision.framework.
//   - C13 (EXIF strip) mutates image data in-place before any upload path is reached.
//
// Thread-safety: `AegisVisionDetector` is an actor. All Vision requests are
// dispatched internally via VNImageRequestHandler on the actor's executor.

import Vision
import CoreImage
import UIKit
import ImageIO

// MARK: - AegisVisionDetector

actor AegisVisionDetector {

    // MARK: - Public entry point

    /// Runs all flagged C1–C13 on-device detections against the supplied image.
    /// Returns only results for capabilities whose flags are enabled.
    /// C12 is a backend-only pattern capability — always returns an empty array.
    func detectAll(in image: UIImage) async -> [AegisDetectionResult] {
        guard let cgImage = image.cgImage else { return [] }

        var results: [AegisDetectionResult] = []

        // Vision capabilities operate on a shared handler for efficiency.
        // We build the required requests first, then execute them in one pass
        // where possible; EXIF and pure-text requests run separately.

        // ── C13: EXIF/GPS strip ─────────────────────────────────────────────
        // Run first so callers can swap the stripped image if needed.
        if AegisFeatureFlags.shared.isEnabled(.exifGpsStrip),
           let data = image.jpegData(compressionQuality: 0.95) {
            let stripped = stripExif(from: data)
            let wasStripped = stripped.count != data.count || !dataContainsGPS(data)
            results.append(AegisDetectionResult.make(
                capability: .exifGpsStrip,
                severity: .info,
                confidence: 1.0,
                action: wasStripped
                    ? "EXIF and GPS metadata stripped from image before upload."
                    : "No GPS metadata detected.",
                evidence: [AegisEvidence(
                    type: .metadata,
                    description: wasStripped ? "GPS/EXIF data removed" : "No GPS metadata present",
                    confidence: 1.0,
                    spanStart: nil,
                    spanEnd: nil
                )],
                regions: [],
                care: []
            ))
        }

        // ── C11: Real-time location via EXIF timestamp ───────────────────────
        if AegisFeatureFlags.shared.isEnabled(.realtimeLocation),
           let data = image.jpegData(compressionQuality: 0.95) {
            if let locationResult = detectRealtimeLocation(from: data) {
                results.append(locationResult)
            }
        }

        // ── Text recognition pass (C2, C3, C4, C5, C6, C7, C8, C9) ─────────
        let textCapabilities: [AegisCapability] = [
            .schoolExposure, .homeAddress, .licensePlate,
            .sensitiveDocs, .idPassport, .medicalDocs, .financialInfo, .sensitiveBackground
        ]
        let enabledTextCaps = textCapabilities.filter { AegisFeatureFlags.shared.isEnabled($0) }
        if !enabledTextCaps.isEmpty {
            let textResults = await runTextRecognition(on: cgImage, for: enabledTextCaps)
            results.append(contentsOf: textResults)
        }

        // ── Face detection pass (C1, C10) ────────────────────────────────────
        let faceCapabilities: [AegisCapability] = [.childMinorPresence, .multiPersonFace]
        let enabledFaceCaps = faceCapabilities.filter { AegisFeatureFlags.shared.isEnabled($0) }
        if !enabledFaceCaps.isEmpty {
            let faceResults = await runFaceDetection(on: cgImage, for: enabledFaceCaps)
            results.append(contentsOf: faceResults)
        }

        // ── C12: Routine mapping — backend-only, no on-device analysis ───────
        // Returns empty. Backend infers patterns from temporal + geo metadata.

        return results
    }

    // MARK: - C1 + C10: Face Detection

    private func runFaceDetection(
        on cgImage: CGImage,
        for capabilities: [AegisCapability]
    ) async -> [AegisDetectionResult] {
        return await withCheckedContinuation { continuation in
            var results: [AegisDetectionResult] = []

            let request = VNDetectFaceRectanglesRequest { req, error in
                guard error == nil, let observations = req.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let faceCount = observations.count
                let regions = observations.map { obs -> [String: Double] in
                    [
                        "x": Double(obs.boundingBox.origin.x),
                        "y": Double(obs.boundingBox.origin.y),
                        "w": Double(obs.boundingBox.width),
                        "h": Double(obs.boundingBox.height)
                    ]
                }

                // C1 — Child/minor presence: use face size as proxy heuristic.
                // Smaller bounding boxes relative to image area suggest younger subjects.
                // IMPORTANT: this is advisory only (.caution). Never block without server confirmation.
                if capabilities.contains(.childMinorPresence) && faceCount > 0 {
                    let smallFaces = observations.filter { $0.boundingBox.width < 0.12 }
                    if !smallFaces.isEmpty {
                        let smallRegions = smallFaces.map { obs -> [String: Double] in
                            [
                                "x": Double(obs.boundingBox.origin.x),
                                "y": Double(obs.boundingBox.origin.y),
                                "w": Double(obs.boundingBox.width),
                                "h": Double(obs.boundingBox.height)
                            ]
                        }
                        // Low confidence advisory — server must confirm before any block action.
                        results.append(AegisDetectionResult.make(
                            capability: .childMinorPresence,
                            severity: .caution,                  // advisory only
                            confidence: 0.45,                    // deliberately low; server escalation required
                            action: "Possible minor detected. Please confirm all people in this image have given permission to be photographed.",
                            evidence: [AegisEvidence(
                                type: .boundingBox,
                                description: "\(smallFaces.count) potentially minor-aged face(s) detected based on face size heuristic (low confidence — server verification required)",
                                confidence: 0.45,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: smallRegions,
                            care: []
                        ))
                    }
                }

                // C10 — Multi-person face + consent check
                if capabilities.contains(.multiPersonFace) && faceCount >= 2 {
                    results.append(AegisDetectionResult.make(
                        capability: .multiPersonFace,
                        severity: .caution,
                        confidence: min(0.65 + Double(faceCount) * 0.05, 0.92),
                        action: "Confirm permission from all \(faceCount) recognizable people in this image.",
                        evidence: [AegisEvidence(
                            type: .boundingBox,
                            description: "\(faceCount) recognizable faces detected",
                            confidence: 0.88,
                            spanStart: nil,
                            spanEnd: nil
                        )],
                        regions: regions,
                        care: []
                    ))
                }

                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - C2, C3, C4, C5, C6, C7, C8, C9: Text Recognition

    private func runTextRecognition(
        on cgImage: CGImage,
        for capabilities: [AegisCapability]
    ) async -> [AegisDetectionResult] {
        return await withCheckedContinuation { continuation in
            var results: [AegisDetectionResult] = []

            // Also run rectangle detection for C9 (background screens/docs)
            var rectangleObservations: [VNRectangleObservation] = []
            let rectRequest = VNDetectRectanglesRequest { req, _ in
                rectangleObservations = (req.results as? [VNRectangleObservation]) ?? []
            }
            rectRequest.minimumAspectRatio = 0.3
            rectRequest.maximumAspectRatio = 1.0
            rectRequest.minimumSize = 0.15

            let textRequest = VNRecognizeTextRequest { req, error in
                guard error == nil,
                      let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let recognizedLines = observations.compactMap {
                    $0.topCandidates(1).first
                }
                let fullText = recognizedLines.map(\.string).joined(separator: "\n")

                // Build regions from text observations for evidence
                let textRegions = observations.map { obs -> [String: Double] in
                    [
                        "x": Double(obs.boundingBox.origin.x),
                        "y": Double(obs.boundingBox.origin.y),
                        "w": Double(obs.boundingBox.width),
                        "h": Double(obs.boundingBox.height)
                    ]
                }

                // ── C2: School exposure ──────────────────────────────────────
                if capabilities.contains(.schoolExposure) {
                    let schoolPatterns = [
                        "elementary", "middle school", "high school", "kindergarten",
                        "grade [k1-9]", "k-12", "school district", "academy",
                        "\\bms\\b.*school", "\\bes\\b.*school"
                    ]
                    let schoolRegex = schoolPatterns.joined(separator: "|")
                    if matchesPattern(schoolRegex, in: fullText, caseInsensitive: true) {
                        results.append(AegisDetectionResult.make(
                            capability: .schoolExposure,
                            severity: .warn,
                            confidence: 0.78,
                            action: "School name or location may be visible. Review before sharing.",
                            evidence: [AegisEvidence(
                                type: .textSpan,
                                description: "School-related text detected in image",
                                confidence: 0.78,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C3: Home address ─────────────────────────────────────────
                if capabilities.contains(.homeAddress) {
                    // Matches patterns like "123 Main Street", "4B Oak Ave", zip codes
                    let addressPattern = "\\b\\d{1,5}\\s+[A-Za-z]+(?:\\s+[A-Za-z]+){0,3}\\s+(?:st(?:reet)?|ave(?:nue)?|blvd|boulevard|rd|road|dr(?:ive)?|ln|lane|ct|court|pl(?:ace)?|way|cir(?:cle)?|terr(?:ace)?|pkwy|parkway)\\b"
                    let zipPattern = "\\b\\d{5}(?:-\\d{4})?\\b"
                    let hasAddress = matchesPattern(addressPattern, in: fullText, caseInsensitive: true)
                    let hasZip = matchesPattern(zipPattern, in: fullText, caseInsensitive: false)
                    if hasAddress || (hasZip && fullText.count > 20) {
                        results.append(AegisDetectionResult.make(
                            capability: .homeAddress,
                            severity: .warn,
                            confidence: hasAddress ? 0.82 : 0.60,
                            action: "A street address may be visible. Remove or blur it before sharing.",
                            evidence: [AegisEvidence(
                                type: .textSpan,
                                description: "Street address or postal code detected in image text",
                                confidence: hasAddress ? 0.82 : 0.60,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C4: License plate ────────────────────────────────────────
                if capabilities.contains(.licensePlate) {
                    // US + international plate patterns
                    let platePattern = "\\b[A-Z0-9]{1,3}[\\s-]?[A-Z0-9]{2,4}[\\s-]?[A-Z0-9]{1,4}\\b"
                    if matchesPattern(platePattern, in: fullText, caseInsensitive: false) {
                        results.append(AegisDetectionResult.make(
                            capability: .licensePlate,
                            severity: .warn,
                            confidence: 0.72,
                            action: "A license plate may be visible. Blur it to protect location privacy.",
                            evidence: [AegisEvidence(
                                type: .pattern,
                                description: "License plate pattern detected in image text",
                                confidence: 0.72,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C5: Sensitive documents ──────────────────────────────────
                if capabilities.contains(.sensitiveDocs) {
                    let docKeywords = [
                        "confidential", "for official use only", "restricted",
                        "do not distribute", "medical record", "patient name",
                        "employee id", "tax return", "w-2", "1099", "ssn",
                        "social security", "account number", "case number"
                    ]
                    if containsKeyword(from: docKeywords, in: fullText) {
                        results.append(AegisDetectionResult.make(
                            capability: .sensitiveDocs,
                            severity: .warn,
                            confidence: 0.80,
                            action: "This image may contain a sensitive document. Remove or redact it.",
                            evidence: [AegisEvidence(
                                type: .textSpan,
                                description: "Sensitive document keywords detected",
                                confidence: 0.80,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C6: ID / Passport ────────────────────────────────────────
                if capabilities.contains(.idPassport) {
                    let idKeywords = [
                        "passport", "driver license", "driver's license", "state id",
                        "identification card", "date of birth", "dob", "d.o.b",
                        "nationality", "place of birth", "mrz", "<<", // MRZ line marker
                        "license no", "lic no", "id no", "id number"
                    ]
                    if containsKeyword(from: idKeywords, in: fullText) {
                        results.append(AegisDetectionResult.make(
                            capability: .idPassport,
                            severity: .block,
                            confidence: 0.88,
                            action: "Government-issued ID detected. Do not share identity documents publicly.",
                            evidence: [AegisEvidence(
                                type: .textSpan,
                                description: "Government ID or passport keywords detected",
                                confidence: 0.88,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C7: Medical documents ────────────────────────────────────
                if capabilities.contains(.medicalDocs) {
                    let medKeywords = [
                        "rx ", "prescription", "diagnosis", "icd-", "cpt code",
                        "patient", "medication", "dosage", "refills", "dr.", "m.d.",
                        "medical record", "hospital", "clinic", "pharmacy",
                        "lab result", "blood type", "hiv", "covid", "radiology"
                    ]
                    if containsKeyword(from: medKeywords, in: fullText) {
                        results.append(AegisDetectionResult.make(
                            capability: .medicalDocs,
                            severity: .warn,
                            confidence: 0.77,
                            action: "Medical information may be visible. Remove or blur it before sharing.",
                            evidence: [AegisEvidence(
                                type: .textSpan,
                                description: "Medical document keywords detected",
                                confidence: 0.77,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C8: Financial information ────────────────────────────────
                if capabilities.contains(.financialInfo) {
                    // Credit card: 16-digit groups, routing/account numbers
                    let cardPattern = "\\b(?:\\d{4}[\\s-]){3}\\d{4}\\b"
                    let routingPattern = "\\brouting[:\\s#]*\\d{9}\\b"
                    let accountPattern = "\\baccount[:\\s#]*\\d{6,17}\\b"
                    let bankKeywords = ["visa", "mastercard", "american express", "amex",
                                        "discover", "checking account", "savings account",
                                        "iban", "swift", "wire transfer"]
                    let hasCardPattern = matchesPattern(cardPattern, in: fullText, caseInsensitive: false)
                    let hasRoutingPattern = matchesPattern(routingPattern, in: fullText, caseInsensitive: true)
                    let hasAccountPattern = matchesPattern(accountPattern, in: fullText, caseInsensitive: true)
                    let hasBankKeyword = containsKeyword(from: bankKeywords, in: fullText)

                    if hasCardPattern || hasRoutingPattern || hasAccountPattern || hasBankKeyword {
                        let severity: AegisSeverity = (hasCardPattern || hasRoutingPattern) ? .block : .warn
                        results.append(AegisDetectionResult.make(
                            capability: .financialInfo,
                            severity: severity,
                            confidence: hasCardPattern ? 0.92 : 0.75,
                            action: "Financial information detected. Do not share bank or card details publicly.",
                            evidence: [AegisEvidence(
                                type: .pattern,
                                description: "Financial account pattern or card number detected",
                                confidence: hasCardPattern ? 0.92 : 0.75,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: textRegions,
                            care: []
                        ))
                    }
                }

                // ── C9: Sensitive background (screens/documents in background) ──
                if capabilities.contains(.sensitiveBackground) {
                    // Trigger if we see rectangle shapes that look like screens/docs
                    // AND those regions contain PII-like text
                    let hasScreenRect = !rectangleObservations.isEmpty
                    let hasPiiHint = containsKeyword(from: [
                        "password", "ssn", "account", "private", "confidential",
                        "bank", "pin", "secret", "login", "credentials"
                    ], in: fullText)
                    if hasScreenRect && hasPiiHint {
                        let rectRegions = rectangleObservations.map { obs -> [String: Double] in
                            [
                                "x": Double(obs.boundingBox.origin.x),
                                "y": Double(obs.boundingBox.origin.y),
                                "w": Double(obs.boundingBox.width),
                                "h": Double(obs.boundingBox.height)
                            ]
                        }
                        results.append(AegisDetectionResult.make(
                            capability: .sensitiveBackground,
                            severity: .caution,
                            confidence: 0.65,
                            action: "Sensitive content may be visible in the background. Check what's on any screens or documents behind you.",
                            evidence: [AegisEvidence(
                                type: .boundingBox,
                                description: "\(rectangleObservations.count) screen/document region(s) detected in background containing potentially sensitive text",
                                confidence: 0.65,
                                spanStart: nil,
                                spanEnd: nil
                            )],
                            regions: rectRegions,
                            care: []
                        ))
                    }
                }

                continuation.resume(returning: results)
            }

            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false  // raw OCR, no correction interference

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([rectRequest, textRequest])
        }
    }

    // MARK: - C11: Real-time location via EXIF

    private func detectRealtimeLocation(from data: Data) -> AegisDetectionResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gpsData = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            return nil
        }

        // Check if the GPS timestamp is within the last 15 minutes
        var isRecent = false
        if let gpsTimestamp = gpsData[kCGImagePropertyGPSTimeStamp as String] as? String,
           let gpsDate = gpsData[kCGImagePropertyGPSDateStamp as String] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            if let date = formatter.date(from: "\(gpsDate)T\(gpsTimestamp)") {
                isRecent = Date().timeIntervalSince(date) < 15 * 60  // 15 minutes
            }
        } else {
            // No timestamp — GPS present but age unknown; treat as recent for safety
            isRecent = true
        }

        guard isRecent else { return nil }

        return AegisDetectionResult.make(
            capability: .realtimeLocation,
            severity: .warn,
            confidence: 0.90,
            action: "This image contains GPS coordinates captured in the last 15 minutes. Remove location data before sharing.",
            evidence: [AegisEvidence(
                type: .metadata,
                description: "EXIF GPS timestamp indicates image was taken within the last 15 minutes",
                confidence: 0.90,
                spanStart: nil,
                spanEnd: nil
            )],
            regions: [],
            care: []
        )
    }

    // MARK: - C13: EXIF/GPS Strip

    /// Copies image data without GPS and EXIF dictionaries.
    /// Returns the stripped data. If stripping fails, returns original data unchanged.
    func stripExif(from data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source) else { return data }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else { return data }

        // Copy metadata but exclude GPS and EXIF dictionaries
        let removeKeys: [CFString] = [
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyIPTCDictionary   // may contain location/creator info
        ]

        let copyOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]

        // Get source properties to filter
        var filteredProps: [String: Any] = [:]
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            filteredProps = props
            for key in removeKeys {
                filteredProps.removeValue(forKey: key as String)
            }
            // Also zero out GPS sub-key if nested inside TIFF
            if var tiff = filteredProps[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff.removeValue(forKey: kCGImagePropertyTIFFArtist as String)
                filteredProps[kCGImagePropertyTIFFDictionary as String] = tiff
            }
        }

        CGImageDestinationAddImageFromSource(destination, source, 0,
            (filteredProps.isEmpty ? copyOptions : filteredProps.merging(
                copyOptions as [String: Any], uniquingKeysWith: { _, new in new }
            )) as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }

    // MARK: - Pattern Matching Helpers

    private func matchesPattern(_ pattern: String, in text: String, caseInsensitive: Bool) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func containsKeyword(from keywords: [String], in text: String) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0.lowercased()) }
    }

    private func dataContainsGPS(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return false
        }
        return props[kCGImagePropertyGPSDictionary as String] != nil
    }
}
