// TestimonyIntegrityService.swift
// AMEN App — Testimony Integrity + Story Assist (Agent 3)
//
// Helps someone structure a testimony WITHOUT making it fake.
// Integrity rules (HARD):
//   - Never embellish or invent facts
//   - Preserve the speaker's tone and wording
//   - Refinement is grammar/clarity/structure ONLY — shown as suggestions the user accepts/rejects
//   - Never claim pastoral authority or fake certainty on disputed theology
//
// Note: Uses TestimonyAssistDraft (not TestimonyDraft) to avoid conflict with
// Feature09_SharedTestimonyDraft.swift which has a different co-author use case.
//
// Sensitive-detail detection: SCAFFOLDED — thresholds are a policy decision.
// POLICY STOP: what counts as a "sensitive detail" and the redaction UX.

import Foundation
import FirebaseFunctions

// MARK: - Testimony Assist Draft (distinct from shared TestimonyDraft)

struct TestimonyAssistDraft: Identifiable {
    let id: String
    var rawTranscript: String   // speaker's original words — never modified
    var editedText: String      // user-accepted edits (grammar/clarity only)
    var title: String
    var audience: TestimonyAudience
    var sensitiveFlags: [SensitiveDetailFlag]
    var suggestedScriptures: [String]   // labeled "suggestion", dismissible
    var captionOptions: [String]        // 3 respectful captions for sharing

    init(transcript: String) {
        id = UUID().uuidString
        rawTranscript = transcript
        editedText = transcript
        title = ""
        audience = .public
        sensitiveFlags = []
        suggestedScriptures = []
        captionOptions = []
    }
}

enum TestimonyAudience: String, CaseIterable {
    case `public`    = "public"
    case churchOnly  = "church_only"
    case groupOnly   = "group_only"
    case `private`   = "private"

    var displayName: String {
        switch self {
        case .public:    return "Public"
        case .churchOnly: return "Church Community"
        case .groupOnly: return "Group Only"
        case .private:   return "Private"
        }
    }

    var systemIcon: String {
        switch self {
        case .public:    return "globe"
        case .churchOnly: return "building.columns.fill"
        case .groupOnly: return "person.3.fill"
        case .private:   return "lock.fill"
        }
    }
}

// MARK: - Sensitive Detail (SCAFFOLDED)
//
// POLICY STOP: the categories and thresholds below are scaffolded.
// Before enabling auto-flagging, confirm:
//   - What patterns constitute a "sensitive detail" for this community
//   - How aggressive the flagging should be (false positives are harmful)
//   - The exact redaction UX (suggest blur/remove vs. hard block vs. advisory)

enum SensitiveDetailCategory: String {
    case fullName       = "full_name"
    case location       = "precise_location"
    case minorMentioned = "minor_mentioned"
    case medicalDetail  = "medical_detail"
    case legalClaim     = "legal_claim"
    case financialInfo  = "financial_info"
}

struct SensitiveDetailFlag: Identifiable {
    let id = UUID()
    let category: SensitiveDetailCategory
    let excerpt: String         // the specific text flagged
    let suggestion: String      // suggested redaction — NEVER forced
    let confidence: Double      // 0–1
    var isDismissed = false
    var isAccepted  = false
}

// MARK: - Refinement Suggestion

struct TestimonyRefinementSuggestion: Identifiable {
    let id = UUID()
    let original: String
    let suggested: String
    let reason: String          // "grammar", "clarity", "structure" — never "content"
    var accepted: Bool = false
    var rejected: Bool = false
}

// MARK: - Service

@MainActor
final class TestimonyIntegrityService: ObservableObject {

    static let shared = TestimonyIntegrityService()

    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?

    private let functions = Functions.functions()

    // MARK: - Grammar/Clarity Refinement (integrity rules enforced server-side)

    func requestRefinements(for draft: TestimonyAssistDraft) async throws -> [TestimonyRefinementSuggestion] {
        guard AMENFeatureFlags.shared.bereanTestimonyAssistEnabled else { return [] }

        isProcessing = true
        defer { isProcessing = false }

        let payload: [String: Any] = [
            "task":       "TESTIMONY_REFINE",
            "transcript": draft.rawTranscript,
            "edited":     draft.editedText,
            "integrityRules": [
                "noEmbellishment": true,
                "preserveTone":    true,
                "grammarOnly":     true
            ]
        ]

        let result = try await functions.httpsCallable("bereanPostAssist").call(payload)
        guard let dict = result.data as? [String: Any],
              let suggestions = dict["suggestions"] as? [[String: Any]] else {
            return []
        }

        return suggestions.compactMap { s -> TestimonyRefinementSuggestion? in
            guard let original  = s["original"]  as? String,
                  let suggested = s["suggested"] as? String,
                  let reason    = s["reason"]    as? String else { return nil }
            return TestimonyRefinementSuggestion(original: original, suggested: suggested, reason: reason)
        }
    }

    // MARK: - Sensitive Detail Detection (SCAFFOLDED — not auto-enabled)
    //
    // POLICY STOP: Enable only after confirming thresholds and redaction UX.

    func detectSensitiveDetails(in text: String) -> [SensitiveDetailFlag] {
        // SCAFFOLDED: returns empty until policy thresholds are confirmed.
        return []
    }

    // MARK: - Berean Theme + Scripture Suggestion

    func suggestThemeAndScripture(for draft: TestimonyAssistDraft) async throws -> (theme: String, scriptures: [String], captions: [String]) {
        guard AMENFeatureFlags.shared.bereanTestimonyAssistEnabled else {
            return (theme: "", scriptures: [], captions: [])
        }

        isProcessing = true
        defer { isProcessing = false }

        let payload: [String: Any] = [
            "task":   "TESTIMONY_THEME",
            "text":   draft.editedText,
            "labels": ["scripture_vs_interpretation": true]
        ]

        let result = try await functions.httpsCallable("bereanBibleQA").call(payload)
        guard let dict = result.data as? [String: Any] else {
            return (theme: "", scriptures: [], captions: [])
        }

        return (
            theme:      dict["theme"]      as? String   ?? "",
            scriptures: dict["scriptures"] as? [String] ?? [],
            captions:   dict["captions"]   as? [String] ?? []
        )
    }

    // MARK: - Private Reflection Note

    func generatePrivateReflection(for draft: TestimonyAssistDraft) async throws -> String {
        let payload: [String: Any] = [
            "task": "TESTIMONY_REFLECTION",
            "text": draft.editedText
        ]
        let result = try await functions.httpsCallable("bereanNoteSummary").call(payload)
        return (result.data as? [String: Any])?["reflection"] as? String ?? ""
    }
}
