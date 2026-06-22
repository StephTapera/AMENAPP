// BereanConstitutionalIntelligence.swift
// AMENAPP
//
// Constitutional review gate for all Berean AI dispatch paths.
// Wired as a mandatory pre-flight in BereanContextActionEngine.perform()
// and delegated to from BereanStudyService.call().
//
// Key invariants:
//  - Gate is a Swift actor: serial access, no concurrent review races.
//  - HallucinationRisk is defined here (not in BereanOSModels) to keep
//    constitutional concerns isolated from the OS-level confidence tier.
//  - BereanConfidenceLevel (from BereanOSModels.swift) is reused as-is;
//    no duplication.
//  - High-impact actions (saveToChurchNotes, createStudy, factCheck,
//    turnIntoSermonOutline) require mode != .build.
//  - Crisis signals cause immediate .blocked; no AI call proceeds.

import Foundation

// MARK: - HallucinationRisk

enum HallucinationRisk: String, Codable, CaseIterable {
    /// Low hallucination risk: well-bounded retrieval task (e.g., translation comparison).
    case low
    /// Medium risk: generative explanation of an established passage.
    case medium
    /// High risk: open-ended generation, sermon outlines, study plans, fact-checking.
    case high
}

// MARK: - BereanConstitutionalMode

/// The epistemic mode Berean should operate in for a given action or session.
/// Modes gate which action types are permitted and how the system prompt is framed.
enum BereanConstitutionalMode: String, Codable, CaseIterable {
    /// Open dialogue: answer questions, surface multiple views, disclaim uncertainty.
    case ask
    /// Careful discernment: surface tensions, weigh evidence, defer to scripture.
    case discern
    /// Constructive output: sermon outlines, study plans, devotionals — high hallucination risk.
    case build
    /// Protective mode: crisis detected, medical topics, minor-adjacent content.
    case `guard`
    /// Contemplative mode: prayer, reflection, emotional insight — no factual claims.
    case reflect

    // MARK: Factory — BereanContextAction → defaultMode

    static func defaultMode(for action: BereanContextAction) -> BereanConstitutionalMode {
        switch action {
        // Protective/crisis-adjacent
        case .prayAboutThis, .turnIntoPrayer, .emotionalInsight:
            return .reflect

        // Reflection without generative claims
        case .reflect, .shareReflection, .turnIntoDevotional:
            return .reflect

        // Open question / ask
        case .askBerean, .askFollowUp, .askMentor, .askPastor, .voiceExplain,
             .discussWithGroup, .continueReading:
            return .ask

        // Retrieval / bounded tasks — low hallucination risk
        case .explain, .simplify, .summarize, .translate, .define,
             .historicalContext, .compareScripture, .crossReference,
             .searchRelatedVerses, .beginnerExplanation, .youthExplanation,
             .leadershipInsight:
            return .discern

        // High-impact generative tasks — build mode (requires extra gate below)
        case .saveToChurchNotes, .createStudy, .factCheck,
             .turnIntoSermonOutline, .createCarousel, .createPost:
            return .build

        // Utility actions — default to discern
        case .addReminder:
            return .discern
        }
    }

    // MARK: Factory — BereanRealtimeSessionType → defaultMode

    static func defaultMode(for sessionType: BereanRealtimeSessionType) -> BereanConstitutionalMode {
        switch sessionType {
        case .sermonTranslation:
            return .discern
        case .livePrayerRoom:
            return .reflect
        case .voiceAssistant:
            return .ask
        case .smartNotes:
            return .build
        case .multilingualConversation:
            return .ask
        }
    }
}

// MARK: - EpistemicDeclaration

/// Attached to every AI response so downstream consumers can surface uncertainty.
struct EpistemicDeclaration: Codable, Equatable {
    /// Facts that have strong scriptural or historical support.
    let verifiedFacts: [String]
    /// Interpretive conclusions that follow from context but are not explicitly stated.
    let assumptions: [String]
    /// Open questions or gaps the AI cannot resolve.
    let unknowns: [String]

    static let empty = EpistemicDeclaration(verifiedFacts: [], assumptions: [], unknowns: [])
}

// MARK: - BereanConstitutionalReviewResult

struct BereanConstitutionalReviewResult {
    let passed: Bool
    /// Populated when `passed == false`; empty when passed.
    let blockedReasons: [String]
    /// The mode that was (or should be) in effect.
    let requiredMode: BereanConstitutionalMode
    let hallucinationRisk: HallucinationRisk

    static func blocked(
        reasons: [String],
        mode: BereanConstitutionalMode = .guard,
        risk: HallucinationRisk = .high
    ) -> BereanConstitutionalReviewResult {
        BereanConstitutionalReviewResult(
            passed: false,
            blockedReasons: reasons,
            requiredMode: mode,
            hallucinationRisk: risk
        )
    }

    static func approved(
        mode: BereanConstitutionalMode,
        risk: HallucinationRisk
    ) -> BereanConstitutionalReviewResult {
        BereanConstitutionalReviewResult(
            passed: true,
            blockedReasons: [],
            requiredMode: mode,
            hallucinationRisk: risk
        )
    }
}

// MARK: - ScriptureVerificationPolicy

/// The policy that governs how scripture reference mismatches are handled
/// for a given BereanConstitutionalMode.
///
/// This is the SINGLE authoritative encoding of mode → policy.
/// No other file should hard-code mode-to-policy logic.
enum ScriptureVerificationPolicy {
    /// Mismatch refs MUST NOT be surfaced as AI text; substitute canonicalText
    /// or display a correction notice. Applied for `.guard` and `.discern`.
    case blockOnMismatch
    /// Mismatch refs are annotated visibly but do not block display.
    /// Applied for `.ask`, `.build`, and `.reflect`.
    case annotateOnMismatch
}

// MARK: - BereanConstitutionalReviewGate (actor)

/// Mandatory pre-flight gate for all Berean AI dispatch.
/// Swift actor ensures serial access and prevents concurrent constitutional review races.
actor BereanConstitutionalReviewGate {

    // MARK: Singleton

    static let shared = BereanConstitutionalReviewGate()
    private init() {}

    // MARK: - Scripture Verification Policy (G-1)

    /// Returns the ScriptureVerificationPolicy for a given constitutional mode.
    ///
    /// This is the SINGLE place that encodes mode → policy.
    /// ScriptureReferenceValidator.verifyWithAPIPipeline calls this; no other
    /// file should hard-code mode-to-policy logic.
    ///
    /// - `.guard`, `.discern` → `.blockOnMismatch`
    /// - `.ask`, `.build`, `.reflect` → `.annotateOnMismatch`
    static func scriptureVerificationPolicy(
        for mode: BereanConstitutionalMode
    ) -> ScriptureVerificationPolicy {
        switch mode {
        case .guard, .discern:
            return .blockOnMismatch
        case .ask, .build, .reflect:
            return .annotateOnMismatch
        }
    }

    // MARK: - Review

    /// Performs constitutional review before any Berean AI call.
    ///
    /// - Parameters:
    ///   - action: The BereanContextAction being dispatched.
    ///   - payload: The user-supplied payload for the action.
    ///   - mode: The constitutional mode to review against (pass `nil` to derive from action).
    /// - Returns: A `BereanConstitutionalReviewResult` that is either `.passed` or `.blocked`.
    func review(
        action: BereanContextAction,
        payload: BereanContextPayload,
        mode: BereanConstitutionalMode? = nil
    ) async -> BereanConstitutionalReviewResult {

        let resolvedMode = mode ?? BereanConstitutionalMode.defaultMode(for: action)
        let risk = hallucinationRisk(for: action)

        var reasons: [String] = []

        // Check 1: non-empty selectedText
        if payload.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("Payload selectedText is empty — no content to review.")
        }

        // Check 2: crisis signal present (client-side fast path)
        let combinedText = [payload.selectedText, payload.surroundingText ?? ""].joined(separator: " ")
        let hasCrisis = await MainActor.run { CrisisDetectionService.shared.hasLocalCrisisSignal(in: combinedText) }
        if hasCrisis {
            reasons.append("Crisis signal detected in payload — action blocked.")
        }

        // Check 3: medical guardrail declared when needed
        let medicalKeywords = [
            "diagnosis", "medicine", "medication", "dosage", "treatment",
            "prescription", "symptom", "disease", "cancer", "diabetes",
            "mental health", "depression", "anxiety", "therapy"
        ]
        // Hard-refuse subset: direct clinical-advice requests are REFUSED outright.
        // A medicalGuardrail/disclaimer flag cannot unlock these — Berean must never
        // diagnose, prescribe, or advise on medication/dosage.
        let medicalHardRefuseKeywords = [
            "diagnosis", "diagnose", "dosage", "prescription", "prescribe",
            "medication", "should i take", "how much should i take", "stop taking"
        ]
        let lower = combinedText.lowercased()
        if medicalHardRefuseKeywords.contains(where: { lower.contains($0) }) {
            reasons.append("Direct medical/clinical advice requested — Berean cannot diagnose, prescribe, or advise on medication or dosage. Please consult a licensed medical professional. (action refused)")
        } else {
            let hasMedical = medicalKeywords.contains { lower.contains($0) }
            if hasMedical && payload.metadata["medicalGuardrail"] == nil {
                reasons.append("Medical topic detected but medicalGuardrail not declared — use BereanContextCoordinator.addMedicalGuardrail(to:) before dispatching.")
            }
        }

        // Check 4: high-impact action types must not use .build mode
        // These actions carry the highest hallucination risk and require discern/ask/reflect.
        let highImpactActions: Set<BereanContextAction> = [
            .saveToChurchNotes, .createStudy, .factCheck, .turnIntoSermonOutline
        ]
        if highImpactActions.contains(action) && resolvedMode == .build {
            reasons.append("High-impact action '\(action.rawValue)' requires mode != .build to prevent unchecked generative output.")
        }

        if !reasons.isEmpty {
            return BereanConstitutionalReviewResult.blocked(reasons: reasons, mode: resolvedMode, risk: risk)
        }

        return BereanConstitutionalReviewResult.approved(mode: resolvedMode, risk: risk)
    }

    // MARK: - Constitutional review for BereanStudyService

    /// Lightweight review for BereanStudyService.call() paths.
    /// Checks crisis signal and medical guardrail on arbitrary free-text inputs.
    ///
    /// - Parameters:
    ///   - texts: Free-text strings from the study call (verseRef, topic, context, etc.).
    ///   - actionType: The study action type being called.
    ///   - metadata: Optional metadata dict (passed from the params dict if available).
    func reviewStudyCall(
        texts: [String],
        actionType: BereanStudyActionType,
        metadata: [String: String] = [:]
    ) async -> BereanConstitutionalReviewResult {

        let mode = studyMode(for: actionType)
        let risk = studyHallucinationRisk(for: actionType)
        let combined = texts.joined(separator: " ")
        var reasons: [String] = []

        // Crisis signal check
        let combinedNonEmpty = !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCrisisSignal = combinedNonEmpty
            ? await MainActor.run { CrisisDetectionService.shared.hasLocalCrisisSignal(in: combined) }
            : false
        let studyCrisis = hasCrisisSignal
        if studyCrisis {
            reasons.append("Crisis signal detected in study call inputs — action blocked.")
        }

        // Medical guardrail check
        let medicalKeywords = [
            "diagnosis", "medicine", "medication", "dosage", "treatment",
            "prescription", "symptom", "disease", "cancer", "diabetes",
            "mental health", "depression", "anxiety", "therapy"
        ]
        // Hard-refuse subset: direct clinical-advice requests are REFUSED outright,
        // regardless of any medicalGuardrail flag.
        let medicalHardRefuseKeywords = [
            "diagnosis", "diagnose", "dosage", "prescription", "prescribe",
            "medication", "should i take", "how much should i take", "stop taking"
        ]
        let lower = combined.lowercased()
        if medicalHardRefuseKeywords.contains(where: { lower.contains($0) }) {
            reasons.append("Direct medical/clinical advice requested — Berean cannot diagnose, prescribe, or advise on medication or dosage. Please consult a licensed medical professional. (action refused)")
        } else {
            let hasMedical = medicalKeywords.contains { lower.contains($0) }
            if hasMedical && metadata["medicalGuardrail"] == nil {
                reasons.append("Medical topic detected in study call — use a medical guardrail note before dispatching.")
            }
        }

        if !reasons.isEmpty {
            return BereanConstitutionalReviewResult.blocked(reasons: reasons, mode: mode, risk: risk)
        }

        return BereanConstitutionalReviewResult.approved(mode: mode, risk: risk)
    }

    // MARK: - Private helpers

    private func hallucinationRisk(for action: BereanContextAction) -> HallucinationRisk {
        switch action {
        case .factCheck, .turnIntoSermonOutline, .createStudy, .saveToChurchNotes,
             .createCarousel, .createPost:
            return .high
        case .explain, .summarize, .simplify, .historicalContext,
             .compareScripture, .crossReference, .searchRelatedVerses,
             .beginnerExplanation, .youthExplanation, .leadershipInsight:
            return .medium
        default:
            return .low
        }
    }

    private func studyMode(for type: BereanStudyActionType) -> BereanConstitutionalMode {
        switch type {
        case .prayerFromPassage:
            return .reflect
        case .explainVerse, .compareTranslations, .discussionQuestions:
            return .discern
        case .studyPlan, .convertToChurchNotes:
            return .build
        }
    }

    private func studyHallucinationRisk(for type: BereanStudyActionType) -> HallucinationRisk {
        switch type {
        case .compareTranslations:
            return .low
        case .explainVerse, .discussionQuestions, .prayerFromPassage:
            return .medium
        case .studyPlan, .convertToChurchNotes:
            return .high
        }
    }
}
