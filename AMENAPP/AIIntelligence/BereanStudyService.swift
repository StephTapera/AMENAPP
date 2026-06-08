import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Draft Models

struct BereanStudyDraft: Identifiable {
    let id: String
    let type: BereanStudyActionType
    let payload: [String: Any]
    var approved: Bool = false
}

enum BereanStudyActionType: String {
    case explainVerse
    case studyPlan
    case compareTranslations
    case discussionQuestions
    case prayerFromPassage
    case convertToChurchNotes
}

/// Controls whether Berean surfaces multiple theological traditions for disputed passages.
/// Default is `.balanced` — present the mainstream Protestant consensus and note where
/// major traditions (Reformed, Arminian, Catholic, etc.) differ significantly.
enum BereanTheologicalPerspectiveMode: String {
    /// Mainstream Protestant consensus with brief notes on significant divergence.
    case balanced = "balanced"
    /// Present Reformed/Calvinist and Arminian perspectives side by side.
    case reformedAndArminian = "reformed_and_arminian"
    /// Present the full ecumenical range including Catholic and Orthodox traditions.
    case ecumenical = "ecumenical"
}

// MARK: - BereanStudyService Error

/// Thrown when free-text input to a Berean study function contains a local crisis signal.
/// Callers must surface the crisis resource card instead of continuing to the Cloud Function.
enum BereanStudyError: Error {
    /// The user's input matched one or more crisis keywords.
    /// Do not call the Cloud Function — show crisis resources immediately.
    case crisisInputDetected
}

// MARK: - BereanStudyService

/// Direct iOS bridge to the 6 Berean Study Assistant Firebase callables.
/// All outputs are DRAFTS — set `approved = true` only after user confirmation.
/// NVIDIA_API_KEY never touches the client; it lives in Secret Manager server-side.
@MainActor
final class BereanStudyService: ObservableObject {
    static let shared = BereanStudyService()

    @Published var isLoading = false
    @Published var lastDraft: BereanStudyDraft?
    @Published var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")
    private init() {}

    // MARK: - Crisis Pre-check

    /// Checks all user-supplied free-text tokens against the local crisis keyword list.
    /// Returns `true` (and sets `errorMessage`) if any token matches, so the caller can
    /// bail out before reaching the Cloud Function.
    private func hasCrisisSignal(in texts: String?...) -> Bool {
        let combined = texts.compactMap { $0 }.joined(separator: " ")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return CrisisDetectionService.shared.hasLocalCrisisSignal(in: combined)
    }

    // MARK: - Public API

    /// Explain a verse in plain language with historical context.
    /// Pass `perspectiveMode` to surface multiple theological traditions for disputed passages.
    /// Returns `nil` and sets `errorMessage` if the input contains a crisis signal — the
    /// caller should check `errorMessage` and surface crisis resources in that case.
    func explainVerse(
        ref: String,
        passageText: String? = nil,
        context: String? = nil,
        perspectiveMode: BereanTheologicalPerspectiveMode = .balanced
    ) async -> BereanStudyDraft? {
        if hasCrisisSignal(in: passageText, context) {
            errorMessage = "It sounds like you may be going through something difficult. Please reach out for support."
            return nil
        }
        var params: [String: Any] = ["verseRef": ref, "perspectiveMode": perspectiveMode.rawValue]
        if let t = passageText { params["passageText"] = t }
        if let c = context { params["context"] = c }
        return await call("bereanExplainVerse", type: .explainVerse, params: params)
    }

    /// Build a 7-day study plan from a verse or topic.
    /// Returns `nil` and sets `errorMessage` if the input contains a crisis signal.
    func studyPlan(ref: String? = nil, topic: String? = nil, context: String? = nil) async -> BereanStudyDraft? {
        if hasCrisisSignal(in: topic, context) {
            errorMessage = "It sounds like you may be going through something difficult. Please reach out for support."
            return nil
        }
        var params: [String: Any] = [:]
        if let r = ref { params["verseRef"] = r }
        if let t = topic { params["topic"] = t }
        if let c = context { params["context"] = c }
        return await call("bereanStudyPlan", type: .studyPlan, params: params)
    }

    /// Compare KJV, NIV, ESV, NLT side-by-side.
    func compareTranslations(ref: String) async -> BereanStudyDraft? {
        await call("bereanCompareTranslations", type: .compareTranslations, params: ["verseRef": ref])
    }

    /// Generate 5 group-study discussion questions.
    /// Returns `nil` and sets `errorMessage` if the input contains a crisis signal.
    func discussionQuestions(
        ref: String,
        passageText: String? = nil,
        groupContext: String? = nil,
        perspectiveMode: BereanTheologicalPerspectiveMode = .balanced
    ) async -> BereanStudyDraft? {
        if hasCrisisSignal(in: passageText, groupContext) {
            errorMessage = "It sounds like you may be going through something difficult. Please reach out for support."
            return nil
        }
        var params: [String: Any] = ["verseRef": ref, "perspectiveMode": perspectiveMode.rawValue]
        if let t = passageText { params["passageText"] = t }
        if let g = groupContext { params["groupContext"] = g }
        return await call("bereanDiscussionQuestions", type: .discussionQuestions, params: params)
    }

    /// Draft a personalised prayer from a passage.
    /// Returns `nil` and sets `errorMessage` if the input contains a crisis signal.
    func prayerFromPassage(ref: String, passageText: String? = nil, context: String? = nil) async -> BereanStudyDraft? {
        if hasCrisisSignal(in: passageText, context) {
            errorMessage = "It sounds like you may be going through something difficult. Please reach out for support."
            return nil
        }
        var params: [String: Any] = ["verseRef": ref]
        if let t = passageText { params["passageText"] = t }
        if let c = context { params["context"] = c }
        return await call("bereanPrayerFromPassage", type: .prayerFromPassage, params: params)
    }

    /// Structure a passage into a Church Notes entry draft.
    /// Returns `nil` and sets `errorMessage` if the input contains a crisis signal.
    func convertToChurchNotes(ref: String, passageText: String? = nil, sermonTitle: String? = nil) async -> BereanStudyDraft? {
        if hasCrisisSignal(in: passageText, sermonTitle) {
            errorMessage = "It sounds like you may be going through something difficult. Please reach out for support."
            return nil
        }
        var params: [String: Any] = ["verseRef": ref]
        if let t = passageText { params["passageText"] = t }
        if let s = sermonTitle { params["sermonTitle"] = s }
        return await call("bereanConvertToChurchNotes", type: .convertToChurchNotes, params: params)
    }

    // MARK: - Private

    private func call(_ name: String, type: BereanStudyActionType, params: [String: Any]) async -> BereanStudyDraft? {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Sign in to use Berean study features."
            return nil
        }
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let result = try await functions.httpsCallable(name).call(params)
            guard let data = result.data as? [String: Any] else {
                errorMessage = "Unexpected response from Berean."
                return nil
            }

            if let errStr = data["error"] as? String, errStr == "study_unavailable" {
                errorMessage = data["fallback"] as? String ?? "Berean study is temporarily unavailable."
                return nil
            }

            let draftId = data["draftId"] as? String ?? UUID().uuidString
            guard let payload = data["draft"] as? [String: Any] else {
                errorMessage = "Could not read draft content."
                return nil
            }

            // Validate any scripture references present in the draft.
            // citedRefs is an array of "Book Chapter:Verse" strings the server included.
            if let citedRefs = payload["citedRefs"] as? [String] {
                for ref in citedRefs {
                    let result = ScriptureReferenceValidator.validate(ref)
                    switch result {
                    case .unknownBook(let book):
                        dlog("⚠️ [Berean] Draft contains unknown book '\(book)' — suppressing draft")
                        errorMessage = "Berean returned an unrecognised scripture reference. Please try again."
                        return nil
                    case .outOfRange(let book, let chapter, let verse):
                        dlog("⚠️ [Berean] Out-of-range reference \(book) \(chapter):\(verse) — suppressing draft")
                        errorMessage = "Berean returned an out-of-range scripture reference. Please try again."
                        return nil
                    case .malformed(let raw):
                        dlog("⚠️ [Berean] Malformed reference '\(raw)' — suppressing draft")
                        errorMessage = "Berean returned a malformed scripture reference. Please try again."
                        return nil
                    case .valid:
                        break
                    }
                }
            }

            let draft = BereanStudyDraft(id: draftId, type: type, payload: payload)
            lastDraft = draft
            return draft
        } catch {
            errorMessage = "Could not reach Berean. Check your connection."
            return nil
        }
    }
}
