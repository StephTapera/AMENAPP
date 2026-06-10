// AILTransformService.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// Single client seam to the `ailTransform` Cloud Function. Every AIL SwiftUI
// surface routes through this service — none calls callModel/Functions directly.
//
// FAILURE MODEL (iron rule 3): AIL transforms FAIL OPEN. On any error, timeout,
// or unavailable backend, this returns A11yTransformResult.failedOpen(...) so the
// caller renders the ORIGINAL content with a quiet "unavailable" state. This is
// the exact OPPOSITE of ModerationGatewayService, which fails closed — the two
// must never be confused. The ONE exception is explainScripture: a refusal there
// is still surfaced as "explanation unavailable" (we never fabricate scripture
// explanation), which is also fail-open from the UI's perspective.
//
// No tier checks anywhere — accessibility is free at every tier.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@Observable
final class AILTransformService {

    static let shared = AILTransformService()

    private let functions = Functions.functions(region: "us-central1")
    private init() {}

    /// Run an AIL transform. Always resolves — never throws — so callers can wire
    /// it without defensive plumbing; failure is expressed via `result.failOpen`.
    ///
    /// - Parameters:
    ///   - task: the AIL capability to invoke.
    ///   - input: the source text/content to transform.
    ///   - originalRef: resolvable id/path of the original (always returned for "View original").
    ///   - targetLang: optional BCP-47 target (translate).
    ///   - readingLevel: optional level (simplify).
    ///   - isDirectMessage: true ⇒ server must NOT cache this transform.
    ///   - crisisContext: true ⇒ bypass all AIL caps/limits.
    func transform(
        task: A11yTask,
        input: String,
        originalRef: String,
        targetLang: String? = nil,
        readingLevel: ReadingLevel? = nil,
        isDirectMessage: Bool = false,
        crisisContext: Bool = false
    ) async -> A11yTransformResult {

        // Speech tasks are handled on-device/server by the SpeechProvider, not here.
        guard !task.isSpeechAdapterTask else {
            return .failedOpen(task: task, originalRef: originalRef)
        }
        guard Auth.auth().currentUser?.uid != nil else {
            return .failedOpen(task: task, originalRef: originalRef)
        }

        var params: [String: Any] = [
            "task": task.rawValue,
            "input": input,
            "originalRef": originalRef,
            "isDirectMessage": isDirectMessage,
            "crisisContext": crisisContext,
        ]
        if let targetLang { params["targetLang"] = targetLang }
        if let readingLevel { params["readingLevel"] = readingLevel.rawValue }

        do {
            let callable = functions.httpsCallable("ailTransform")
            callable.timeoutInterval = 15
            let response = try await callable.call(params)
            guard let data = response.data as? [String: Any] else {
                return .failedOpen(task: task, originalRef: originalRef)
            }
            return Self.parse(data, task: task, originalRef: originalRef)
        } catch {
            // Fail OPEN — show the original, never block on a transform.
            return .failedOpen(task: task, originalRef: originalRef)
        }
    }

    // MARK: - Parsing

    private static func parse(
        _ data: [String: Any],
        task: A11yTask,
        originalRef: String
    ) -> A11yTransformResult {

        // Backend signalled fail-open explicitly (degrade path).
        if (data["failOpen"] as? Bool) == true {
            var r = A11yTransformResult.failedOpen(task: task, originalRef: originalRef)
            r.crisisBypass = (data["crisisBypass"] as? Bool) ?? false
            return r
        }

        let provenance = A11yProvenance(rawValue: data["provenance"] as? String ?? "") ?? .aiGenerated
        let confidence = A11yConfidence(rawValue: data["confidence"] as? String ?? "") ?? .medium

        var notes: [CultureNote]? = nil
        if let raw = data["cultureNotes"] as? [[String: Any]] {
            notes = raw.compactMap { dict in
                guard let phrase = dict["phrase"] as? String,
                      let note = dict["note"] as? String else { return nil }
                let kind = CultureNote.Kind(rawValue: dict["kind"] as? String ?? "") ?? .cultural
                return CultureNote(phrase: phrase, note: note, kind: kind)
            }
        }

        return A11yTransformResult(
            task: task,
            text: data["output"] as? String ?? data["text"] as? String,
            provenance: provenance,
            sourceLang: data["sourceLang"] as? String,
            targetLang: data["targetLang"] as? String,
            cultureNotes: notes,
            confidence: confidence,
            originalRef: (data["originalRef"] as? String) ?? originalRef,
            failOpen: false,
            crisisBypass: (data["crisisBypass"] as? Bool) ?? false
        )
    }
}
