// ContextLensService.swift
// AMENAPP — Camera OS
// Converts camera captures into structured understanding.
// Pipeline: on-device Vision OCR → scene classification → Firebase AI structured output.

import Foundation
import Vision
import UIKit
import FirebaseFunctions

// MARK: - ContextLensService

actor ContextLensService {

    // MARK: Shared instance

    static let shared = ContextLensService()

    // MARK: Private dependencies

    private lazy var functions = Functions.functions()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Main entry point. Runs the full pipeline:
    /// OCR → scene classification → structured output → optional Berean Vision analysis.
    func scan(imageData: Data) async -> ContextLensResult {
        // Step 1: On-device OCR
        let rawText = await extractText(from: imageData)

        // Step 2: Heuristic scene classification
        let scene = classifyScene(text: rawText)

        // Step 3: Firebase AI structured output
        let structuredOutput = await structureOutput(text: rawText, scene: scene)

        // Step 4: Berean Vision — only for faith content
        var bereanResult: BereanVisionScanResult?
        let looksLikeFaithContent = scene == .church || isFaithKeyword(rawText)
        if looksLikeFaithContent {
            bereanResult = await bereanVisionAnalyze(text: rawText)
        }

        // Heuristic confidence: longer OCR text = more confident
        let confidence: Double = rawText.isEmpty ? 0.0 : min(1.0, Double(rawText.count) / 500.0)

        return ContextLensResult(
            sceneType: scene,
            structuredOutput: structuredOutput,
            bereanVisionResult: bereanResult,
            rawOCRText: rawText,
            confidence: confidence
        )
    }

    // MARK: - OCR

    /// Runs Vision's accurate text-recognition pipeline on the provided image data.
    private func extractText(from imageData: Data) async -> String {
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            return ""
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let lines = observations.compactMap { obs -> String? in
                    obs.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Scene Classification

    /// Heuristic keyword-based scene classifier.
    private func classifyScene(text: String) -> CameraSceneType {
        let lower = text.lowercased()

        if lower.contains("sermon") || lower.contains("scripture") ||
           lower.contains("praise") || lower.contains("worship") ||
           lower.contains("church") || lower.contains("amen") ||
           lower.contains("hallelujah") {
            return .church
        }

        if lower.contains("agenda") || lower.contains("action item") ||
           lower.contains("meeting") || lower.contains("standup") {
            return .office
        }

        if lower.contains("class") || lower.contains("homework") ||
           lower.contains("assignment") || lower.contains("teacher") {
            return .classroom
        }

        if lower.contains("patient") || lower.contains("diagnosis") ||
           lower.contains("prescription") {
            return .hospital
        }

        // Note: recipe text ("ingredients", "tablespoon", "cup of") falls through to
        // .unknown because CameraSceneType has no dedicated recipe case; the
        // structuredOutput step will still produce .recipeShoppingList via the CF.
        return .unknown
    }

    // MARK: - Structured Output

    /// Calls the `interpretContextLens` Cloud Function and parses the typed response.
    /// Falls back to `.generic` on any network or parsing failure.
    private func structureOutput(
        text: String,
        scene: CameraSceneType
    ) async -> ContextLensStructuredOutput {
        do {
            let callable = functions.httpsCallable("interpretContextLens")
            let result = try await callable.call([
                "rawText": text,
                "sceneHint": scene.rawValue
            ] as [String: Any])

            guard let data = result.data as? [String: Any],
                  let type = data["type"] as? String,
                  let payload = data["payload"] as? [String: Any] else {
                return .generic(text: text, summary: String(text.prefix(200)))
            }

            return parseStructuredOutput(type: type, payload: payload, fallbackText: text)
        } catch {
            dlog("⚠️ ContextLensService.structureOutput: \(error)")
            return .generic(text: text, summary: String(text.prefix(200)))
        }
    }

    /// Maps the CF response type string + payload dictionary to a `ContextLensStructuredOutput`.
    private func parseStructuredOutput(
        type: String,
        payload: [String: Any],
        fallbackText: String
    ) -> ContextLensStructuredOutput {
        switch type {
        case "meeting_summary":
            let title = payload["title"] as? String ?? "Meeting Summary"
            let keyPoints = payload["keyPoints"] as? [String] ?? []
            let actionItems = payload["actionItems"] as? [String] ?? []
            return .meetingSummary(title: title, keyPoints: keyPoints, actionItems: actionItems)

        case "recipe":
            let ingredients = payload["ingredients"] as? [String] ?? []
            return .recipeShoppingList(ingredients: ingredients)

        case "book_notes":
            let title = payload["title"] as? String ?? "Book Notes"
            let author = payload["author"] as? String
            let keyThemes = payload["keyThemes"] as? [String] ?? []
            return .bookNotes(title: title, author: author, keyThemes: keyThemes)

        case "bulletin_events":
            let rawEvents = payload["events"] as? [[String: Any]] ?? []
            let events: [BulletinEventItem] = rawEvents.map { eventDict in
                BulletinEventItem(
                    id: eventDict["id"] as? String ?? UUID().uuidString,
                    title: eventDict["title"] as? String ?? "Event",
                    date: eventDict["date"] as? String,
                    location: eventDict["location"] as? String,
                    notes: eventDict["notes"] as? String ?? ""
                )
            }
            return .bulletinEvents(events: events)

        case "sermon_notes":
            let title = payload["title"] as? String ?? "Sermon Notes"
            let scripture = payload["scripture"] as? [String] ?? []
            let summary = payload["summary"] as? String ?? ""
            let discussionQuestions = payload["discussionQuestions"] as? [String] ?? []
            return .sermonNotes(
                title: title,
                scripture: scripture,
                summary: summary,
                discussionQuestions: discussionQuestions
            )

        default:
            let summary = payload["summary"] as? String ?? String(fallbackText.prefix(200))
            return .generic(text: fallbackText, summary: summary)
        }
    }

    // MARK: - Berean Vision

    /// Calls the `bereanVisionScan` Cloud Function and returns a parsed result, or nil on failure.
    private func bereanVisionAnalyze(text: String) async -> BereanVisionScanResult? {
        do {
            let callable = functions.httpsCallable("bereanVisionScan")
            let result = try await callable.call(["text": text] as [String: Any])

            guard let data = result.data as? [String: Any] else { return nil }

            let scriptureRefs = data["scriptureRefs"] as? [String] ?? []
            let summary = data["summary"] as? String ?? ""
            let studyNotes = data["studyNotes"] as? [String] ?? []
            let discussionQuestions = data["discussionQuestions"] as? [String] ?? []
            let confidence = data["confidence"] as? Double ?? 0.0

            return BereanVisionScanResult(
                scriptureRefs: scriptureRefs,
                summary: summary,
                studyNotes: studyNotes,
                discussionQuestions: discussionQuestions,
                confidence: confidence
            )
        } catch {
            dlog("⚠️ ContextLensService.bereanVisionAnalyze: \(error)")
            return nil
        }
    }

    // MARK: - Private helpers

    /// Lightweight faith-keyword check used as secondary signal alongside scene type.
    private func isFaithKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        let faithWords = [
            "scripture", "verse", "john", "matthew", "luke", "acts",
            "psalms", "genesis", "romans", "corinthians", "revelation",
            "sermon", "gospel", "jesus", "christ", "holy spirit", "amen"
        ]
        return faithWords.contains { lower.contains($0) }
    }
}
