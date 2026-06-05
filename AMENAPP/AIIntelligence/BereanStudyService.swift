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

    // MARK: - Public API

    /// Explain a verse in plain language with historical context.
    func explainVerse(ref: String, passageText: String? = nil, context: String? = nil) async -> BereanStudyDraft? {
        var params: [String: Any] = ["verseRef": ref]
        if let t = passageText { params["passageText"] = t }
        if let c = context { params["context"] = c }
        return await call("bereanExplainVerse", type: .explainVerse, params: params)
    }

    /// Build a 7-day study plan from a verse or topic.
    func studyPlan(ref: String? = nil, topic: String? = nil, context: String? = nil) async -> BereanStudyDraft? {
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
    func discussionQuestions(ref: String, passageText: String? = nil, groupContext: String? = nil) async -> BereanStudyDraft? {
        var params: [String: Any] = ["verseRef": ref]
        if let t = passageText { params["passageText"] = t }
        if let g = groupContext { params["groupContext"] = g }
        return await call("bereanDiscussionQuestions", type: .discussionQuestions, params: params)
    }

    /// Draft a personalised prayer from a passage.
    func prayerFromPassage(ref: String, passageText: String? = nil, context: String? = nil) async -> BereanStudyDraft? {
        var params: [String: Any] = ["verseRef": ref]
        if let t = passageText { params["passageText"] = t }
        if let c = context { params["context"] = c }
        return await call("bereanPrayerFromPassage", type: .prayerFromPassage, params: params)
    }

    /// Structure a passage into a Church Notes entry draft.
    func convertToChurchNotes(ref: String, passageText: String? = nil, sermonTitle: String? = nil) async -> BereanStudyDraft? {
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

            let draft = BereanStudyDraft(id: draftId, type: type, payload: payload)
            lastDraft = draft
            return draft
        } catch {
            errorMessage = "Could not reach Berean. Check your connection."
            return nil
        }
    }
}
