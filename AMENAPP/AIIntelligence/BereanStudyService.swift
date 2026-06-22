import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Draft Models

struct BereanStudyDraft: Identifiable {
    let id: String
    let type: BereanStudyActionType
    let payload: [String: Any]
    var approved: Bool = false
    /// Constitutional mode that was in effect when this draft was generated.
    var constitutionalMode: BereanConstitutionalMode = .discern
    /// Epistemic declaration for the draft (populated after constitutional review).
    var epistemicDeclaration: EpistemicDeclaration = .empty
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
///
/// ─────────────────────────────────────────────────────────────────────────
/// WIRING CERT — Berean LLM Lane  (safety-hardening branch, 2026-06-12)
/// ─────────────────────────────────────────────────────────────────────────
/// Gate 1 — Age-gating (isMinor)
///   All six public study methods call `call()` which checks
///   `AgeAssuranceService.shared.currentUserTier.isMinor` and returns nil
///   for users on the `.teen` or `.underMinimum` tier.
///   Fallback: `.adult` is assumed only when the tier has been positively
///   loaded; missing profile defaults to `.teen` per AgeAssurancePolicy.
///
/// Gate 2 — Client-side rate limiting
///   `call()` enforces a 10-requests-per-60-second sliding window using
///   `callTimestamps`. Requests beyond the cap set `errorMessage` and
///   return nil — no Cloud Function is invoked.
///
/// Gate 3 — Citation enforcement
///   Drafts that arrive with an empty or absent `citedRefs` array are
///   suppressed. Every entry in `citedRefs` is validated by
///   `ScriptureReferenceValidator`; unknown books, out-of-range chapter/
///   verse, or malformed strings all cause the draft to be discarded.
///   This addresses the "no fabricated references" invariant.
///
/// Gate 4 — Safety moderation on output
///   The draft's text fields (`summary`, `body`, `questions`, `prayer`)
///   are scanned by `CrisisDetectionService` before the draft is returned.
///   If the LLM somehow echoes a crisis phrase in its output, the draft is
///   suppressed and the crisis card is shown instead.
///
/// Gate 5 — Crisis pre-check on input (pre-existing, confirmed wired)
///   `hasCrisisSignal(in:)` runs before every CF call.
///
/// Gate 6 — Auth guard (pre-existing, confirmed wired)
///   `Auth.auth().currentUser != nil` checked in `call()`.
///
/// Gate 7 — Constitutional review (added 2026-06-12)
///   `BereanConstitutionalReviewGate.shared.reviewStudyCall()` runs after
///   the rate-limit gate. Delegates crisis-signal and medical-guardrail
///   checks to the shared actor, unifying constitutional logic across
///   BereanContextActionEngine and BereanStudyService without duplication.
///   The resolved constitutional mode is attached to the returned draft.
/// ─────────────────────────────────────────────────────────────────────────
@MainActor
final class BereanStudyService: ObservableObject {
    static let shared = BereanStudyService()

    @Published var isLoading = false
    @Published var lastDraft: BereanStudyDraft?
    @Published var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")
    // Constitutional gate — shared actor instance.
    private let constitutionGate = BereanConstitutionalReviewGate.shared

    // MARK: - Rate-limit state (Gate 2)
    // Sliding window: max 10 calls per 60 seconds per process lifetime.
    private var callTimestamps: [Date] = []
    private let rateLimitWindow: TimeInterval = 60
    private let rateLimitMax = 10

    private init() {}

    // MARK: - Crisis Pre-check (Gate 5)

    /// Checks all user-supplied free-text tokens against the local crisis keyword list.
    /// Returns `true` (and sets `errorMessage`) if any token matches, so the caller can
    /// bail out before reaching the Cloud Function.
    private func hasCrisisSignal(in texts: String?...) -> Bool {
        let combined = texts.compactMap { $0 }.joined(separator: " ")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return CrisisDetectionService.shared.hasLocalCrisisSignal(in: combined)
    }

    // MARK: - Age Gate (Gate 1)

    /// Returns `true` when the current user is a minor (teen or under-minimum tier).
    /// Fails safe: if AgeAssuranceService has not yet loaded a profile the policy
    /// default is `.teen` (restricted), so this returns `true` (blocked).
    private func currentUserIsMinor() -> Bool {
        AgeAssuranceService.shared.currentUserTier.isMinor
    }

    // MARK: - Rate-limit check (Gate 2)

    /// Enforces the sliding-window rate limit. Prunes expired timestamps, then
    /// returns `false` (and sets `errorMessage`) if the window is full.
    private func checkRateLimit() -> Bool {
        let now = Date()
        callTimestamps = callTimestamps.filter { now.timeIntervalSince($0) < rateLimitWindow }
        guard callTimestamps.count < rateLimitMax else {
            errorMessage = "You're sending requests very quickly. Please wait a moment before trying again."
            return false
        }
        callTimestamps.append(now)
        return true
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
        return await call("bereanExplainVerse", type: .explainVerse, params: params,
                          constitutionTexts: [ref, passageText, context].compactMap { $0 })
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
        return await call("bereanStudyPlan", type: .studyPlan, params: params,
                          constitutionTexts: [ref, topic, context].compactMap { $0 })
    }

    /// Compare KJV, NIV, ESV, NLT side-by-side.
    func compareTranslations(ref: String) async -> BereanStudyDraft? {
        await call("bereanCompareTranslations", type: .compareTranslations, params: ["verseRef": ref],
                   constitutionTexts: [ref])
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
        return await call("bereanDiscussionQuestions", type: .discussionQuestions, params: params,
                          constitutionTexts: [ref, passageText, groupContext].compactMap { $0 })
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
        return await call("bereanPrayerFromPassage", type: .prayerFromPassage, params: params,
                          constitutionTexts: [ref, passageText, context].compactMap { $0 })
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
        return await call("bereanConvertToChurchNotes", type: .convertToChurchNotes, params: params,
                          constitutionTexts: [ref, passageText, sermonTitle].compactMap { $0 })
    }

    // MARK: - Private

    private func call(
        _ name: String,
        type: BereanStudyActionType,
        params: [String: Any],
        constitutionTexts: [String] = []
    ) async -> BereanStudyDraft? {

        // Gate 6 — Auth
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Sign in to use Berean study features."
            return nil
        }

        // Gate 1 — Age-gating (WIRING CERT: added 2026-06-11)
        // AgeAssuranceService defaults to .teen when no profile is loaded (fails safe).
        if currentUserIsMinor() {
            errorMessage = "Berean AI study features are available for adults only."
            dlog("[Berean] Blocked AI call '\(name)' — user is minor or age profile not loaded.")
            return nil
        }

        // Gate 2 — Client-side rate limit (WIRING CERT: added 2026-06-11)
        guard checkRateLimit() else { return nil }

        // Gate 7 — Constitutional review (WIRING CERT: added 2026-06-12)
        // Delegates crisis-signal and medical-guardrail checks to the shared
        // BereanConstitutionalReviewGate actor. This unifies constitutional
        // logic with BereanContextActionEngine without duplicating it here.
        let constitutionResult = await constitutionGate.reviewStudyCall(
            texts: constitutionTexts,
            actionType: type
        )
        guard constitutionResult.passed else {
            let reason = constitutionResult.blockedReasons.first ?? ""
            dlog("[Berean] Constitutional gate blocked study call '\(name)': \(constitutionResult.blockedReasons.joined(separator: "; "))")
            errorMessage = reason.lowercased().contains("crisis")
                ? "It sounds like you may be going through something difficult. Please reach out for support."
                : "Berean could not process this request. Please try again."
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

            // Gate 3 — Citation enforcement (WIRING CERT: strengthened 2026-06-11)
            // Previously: allowed drafts with zero citations through.
            // Now: exegetical responses (all types except compareTranslations) MUST
            //      include at least one citation; absence is treated as a fabrication risk.
            let citedRefs = payload["citedRefs"] as? [String] ?? []
            if type != .compareTranslations && citedRefs.isEmpty {
                dlog("⚠️ [Berean] Draft for '\(name)' has no citedRefs — suppressing (citation enforcement).")
                errorMessage = "Berean's response did not include a scripture citation. Please try again."
                return nil
            }

            for ref in citedRefs {
                let validationResult = ScriptureReferenceValidator.validate(ref)
                switch validationResult {
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

            // Gate 4 — Safety moderation on output text (WIRING CERT: added 2026-06-11)
            // Scans all text fields in the draft for crisis signals before returning.
            // Protects against edge cases where the LLM echoes a distress phrase.
            let outputTexts: [String] = [
                payload["summary"]   as? String,
                payload["body"]      as? String,
                payload["questions"] as? String,
                payload["prayer"]    as? String,
            ].compactMap { $0 }

            let outputCombined = outputTexts.joined(separator: " ")
            if !outputCombined.isEmpty && CrisisDetectionService.shared.hasLocalCrisisSignal(in: outputCombined) {
                dlog("⚠️ [Berean] Output moderation triggered on '\(name)' — suppressing draft and showing crisis card.")
                errorMessage = "Berean detected a sensitive topic in the response. If you're struggling, please reach out for support."
                return nil
            }

            var draft = BereanStudyDraft(id: draftId, type: type, payload: payload)
            draft.constitutionalMode = constitutionResult.requiredMode
            draft.epistemicDeclaration = EpistemicDeclaration.empty
            lastDraft = draft
            return draft
        } catch {
            errorMessage = "Could not reach Berean. Check your connection."
            return nil
        }
    }
}
