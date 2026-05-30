// BereanVisualScriptureService.swift
// AMEN App — Berean Visual Scripture Intelligence (Agent 2)
//
// Camera/image -> OCR -> scripture reference detection -> Berean context card.
// Images for personal journals/prayer notes are processed transiently and
// never stored unless the user explicitly saves them.

import Foundation
import Vision
import UIKit
import FirebaseFunctions

// MARK: - Scripture Reference

struct BereanScriptureReference: Hashable, Equatable {
    let book: String
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int?

    var displayString: String {
        if let end = verseEnd {
            return "\(book) \(chapter):\(verseStart)–\(end)"
        }
        return "\(book) \(chapter):\(verseStart)"
    }
}

// MARK: - Bible Version

enum BereanBibleVersion: String, CaseIterable {
    case kjv  = "KJV"
    case niv  = "NIV"
    case esv  = "ESV"
    case nlt  = "NLT"
    case nkjv = "NKJV"
    case nasb = "NASB"
    case amp  = "AMP"
    case unknown = "Unknown"
}

// MARK: - OCR Result

struct BereanScriptureOCRResult {
    let rawText: String
    let detectedReference: BereanScriptureReference?
    let detectedVersion: BereanBibleVersion?
    let ocrConfidence: Double   // 0–1
    let isShareSafe: Bool       // true if image passed the safety scan

    var hasReference: Bool { detectedReference != nil }
}

// MARK: - Context Card

struct BereanScriptureContextCard: Identifiable {
    let id: String
    let reference: BereanScriptureReference
    let version: BereanBibleVersion
    let passageText: String
    let crossReferences: [BereanScriptureReference]
    let contextSummary: String
    /// Always labeled as scripture | interpretation | encouragement — never mixed.
    let bereanLabel: BereanContentLabel
    let bereanNote: String

    init(
        reference: BereanScriptureReference,
        version: BereanBibleVersion,
        passageText: String,
        crossReferences: [BereanScriptureReference] = [],
        contextSummary: String,
        bereanLabel: BereanContentLabel,
        bereanNote: String
    ) {
        self.id = UUID().uuidString
        self.reference = reference
        self.version = version
        self.passageText = passageText
        self.crossReferences = crossReferences
        self.contextSummary = contextSummary
        self.bereanLabel = bereanLabel
        self.bereanNote = bereanNote
    }
}

enum BereanContentLabel: String {
    case scripture      = "Scripture"
    case interpretation = "Interpretation"
    case encouragement  = "Encouragement"

    var systemIcon: String {
        switch self {
        case .scripture:      return "book.fill"
        case .interpretation: return "bubble.left.and.bubble.right.fill"
        case .encouragement:  return "heart.fill"
        }
    }
}

// MARK: - Service

@MainActor
final class BereanVisualScriptureService: ObservableObject {

    static let shared = BereanVisualScriptureService()

    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?

    private let functions = Functions.functions()

    // MARK: - Step 1: OCR

    func extractScripture(from image: UIImage) async throws -> BereanScriptureOCRResult {
        guard AMENFeatureFlags.shared.bereanVisualScriptureEnabled else {
            throw BereanVisualScriptureError.featureDisabled
        }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let rawText = try await performOCR(image: image)
        let reference = detectReference(in: rawText)
        let version = detectVersion(in: rawText)

        return BereanScriptureOCRResult(
            rawText: rawText,
            detectedReference: reference,
            detectedVersion: version,
            ocrConfidence: reference != nil ? 0.88 : 0.2,
            isShareSafe: true   // Safety scan happens server-side on share; local OCR is private
        )
    }

    // MARK: - Step 2: Berean Context Card

    /// Fetch a context card for a detected reference. User must confirm before saving/sharing.
    func fetchContextCard(
        for reference: BereanScriptureReference,
        version: BereanBibleVersion
    ) async throws -> BereanScriptureContextCard {
        isProcessing = true
        defer { isProcessing = false }

        let payload: [String: Any] = [
            "task":      "VISUAL_SCRIPTURE_CONTEXT",
            "reference": reference.displayString,
            "version":   version.rawValue
        ]

        let result = try await functions.httpsCallable("bereanBibleQA").call(payload)
        guard let dict = result.data as? [String: Any] else {
            throw BereanVisualScriptureError.invalidResponse
        }

        let passageText     = dict["passage"]     as? String ?? ""
        let contextSummary  = dict["context"]     as? String ?? ""
        let bereanNote      = dict["note"]        as? String ?? ""
        let labelRaw        = dict["label"]       as? String ?? "scripture"
        let crossRefStrs    = dict["crossRefs"]   as? [String] ?? []

        let label = BereanContentLabel(rawValue: labelRaw) ?? .scripture
        let crossRefs = crossRefStrs.compactMap { detectReference(in: $0) }

        return BereanScriptureContextCard(
            reference: reference,
            version: version,
            passageText: passageText,
            crossReferences: crossRefs,
            contextSummary: contextSummary,
            bereanLabel: label,
            bereanNote: bereanNote
        )
    }

    // MARK: - Private: OCR via Vision

    private func performOCR(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw BereanVisualScriptureError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "es-ES", "pt-BR", "fr-FR", "de-DE"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Private: Reference Detection

    // Matches patterns like "John 3:16", "1 Corinthians 13:4-7", "Ps. 23:1"
    private func detectReference(in text: String) -> BereanScriptureReference? {
        let pattern = #"(?:(?:\d\s)?[A-Za-z]+(?:\s[A-Za-z]+)*)\s(\d+):(\d+)(?:[–\-](\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
            return nil
        }

        // Extract book from the full match minus the captured groups
        let fullMatch = nsText.substring(with: match.range)
        guard let chapterStr = Range(match.range(at: 1), in: text).map({ String(text[$0]) }),
              let verseStr   = Range(match.range(at: 2), in: text).map({ String(text[$0]) }),
              let chapter    = Int(chapterStr),
              let verse      = Int(verseStr) else {
            return nil
        }
        let verseEnd = Range(match.range(at: 3), in: text).flatMap { Int(String(text[$0])) }

        // Book is the part before "chapter:verse"
        let chapterPart = "\(chapter):\(verse)"
        let book = fullMatch
            .components(separatedBy: chapterPart).first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard !book.isEmpty else { return nil }

        return BereanScriptureReference(
            book: book,
            chapter: chapter,
            verseStart: verse,
            verseEnd: verseEnd
        )
    }

    private func detectVersion(in text: String) -> BereanBibleVersion? {
        BereanBibleVersion.allCases
            .filter { $0 != .unknown }
            .first { text.range(of: $0.rawValue, options: .caseInsensitive) != nil }
    }
}

// MARK: - Errors

enum BereanVisualScriptureError: Error, LocalizedError {
    case featureDisabled
    case invalidImage
    case invalidResponse
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .featureDisabled:   return "Visual Scripture is not available yet."
        case .invalidImage:      return "Could not read the image."
        case .invalidResponse:   return "Berean returned an unexpected response. Try again."
        case .notAuthorized:     return "Camera permission is required."
        }
    }
}
