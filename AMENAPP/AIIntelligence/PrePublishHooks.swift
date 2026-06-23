// PrePublishHooks.swift
// AMENAPP — Feature C · GUARDIAN PrePublish hook conformers (Wave 0 skeleton)
//
// The four deterministic, fail-closed hooks that compose the chain defined in
// GuardianPrePublishContracts.swift. Each hook owns NO detection logic — it delegates
// to an existing real seam and maps that seam's signal to a HookVerdict via a fixed
// switch (PP-I5: never model vibes). On any uncertainty it returns a fail-closed verdict.
//
// Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.3 (hook chain table).
//
//   0  ChildSafetyHashHook      -> CameraChildSafetyService (CSAMScreeningProtocol). UNCONDITIONAL,
//                                  fail-closed: nil screener => block. NEVER reads a flag.
//   1  ToxicityHook             -> AmenSafetyModerationCoordinator.moderate. Guard-surface error
//                                  => .uncertain => block.
//   2  ClaimScriptureContextHook-> BereanCitationGate. fabricated/unverifiable => block;
//                                  pending/never-verified => fail-closed hold.
//   3  ProvenanceStampHook      -> PostTrustAnalysisService advisory label. .stampOnly only —
//                                  C2PA/deepfake is an advisory label, NEVER a person score,
//                                  and never blocks on its own (PP-I6).

import Foundation

// MARK: - Hook 0: ChildSafetyHashHook (unconditional, fail-closed)

/// Delegates to the existing `CameraChildSafetyService` CSAM screener. This hook is
/// NEVER flag-gated and NEVER consults `AMENFeatureFlags`. If no screener is injected,
/// or the screener throws, or it reports `.screeningUnavailable`, the result is a hard
/// block — the absence of an affirmative clean is itself a denial (PP-I3).
///
/// iOS NEVER auto-files to NCMEC. A hash match routes to /moderationQueue type='csam'
/// (see HookChain.escalation) and the human gate handles CyberTipline submission.
struct ChildSafetyHashHook: PrePublishHook {

    let kind: PrePublishHookKind = .childSafetyHash
    let order: Int = 0
    let flagGated: Bool = false

    /// Injected screener accessor. Defaults to the shared camera-layer service. nil =>
    /// fail-closed (no screener means no publish for any media-bearing write).
    private let screenForCSAM: @Sendable (Data) async -> CSAMScreeningResult

    init(
        screenForCSAM: @escaping @Sendable (Data) async -> CSAMScreeningResult = { data in
            await CameraChildSafetyService.shared.screenForCSAM(imageData: data)
        }
    ) {
        self.screenForCSAM = screenForCSAM
    }

    func evaluate(_ input: PrePublishHookInput) async -> HookVerdict {
        let source = "CameraChildSafetyService.CSAMScreeningProtocol"

        // No media on this write => the child-safety HASH hook has nothing to hash and
        // clears (text-only paths still get toxicity/citation coverage downstream).
        guard input.hasMedia else {
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        // Media-bearing write but no bytes provided => cannot screen => fail-closed.
        guard let imageData = input.imageData else {
            return PrePublishFailClosed.verdict(hook: kind, reason: .noScreener, source: source)
        }

        let result = await screenForCSAM(imageData)
        switch result {
        case .clean:
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        case .flagged(let confidence):
            return HookVerdict(
                hook: kind,
                decision: .blockCommit,
                reason: .hashMatch,
                categories: ["child_safety"],
                confidence: confidence,
                source: source,
                requiresHumanReview: true,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        case .screeningUnavailable:
            // nil screener OR screener threw => fail-closed hard block (PP-I3).
            return PrePublishFailClosed.verdict(hook: kind, reason: .noScreener, source: source)
        }
    }
}

// MARK: - Hook 1: ToxicityHook (delegates AmenSafetyModerationCoordinator)

/// Delegates to the existing `AmenSafetyModerationCoordinator.moderate`. The coordinator
/// already enforces fail-secure on guard surfaces (returns `.uncertain` => not allowed),
/// so this hook only maps the coordinator's result to a verdict (PP-I5 fixed switch).
struct ToxicityHook: PrePublishHook {

    let kind: PrePublishHookKind = .toxicity
    let order: Int = 1
    let flagGated: Bool = true

    // Isolation matches the sibling hooks + the protocol requirement (implicit MainActor under
    // the repo's DEFAULT_ACTOR_ISOLATION=MainActor). The coordinator call still runs on MainActor.
    func evaluate(_ input: PrePublishHookInput) async -> HookVerdict {
        let source = "AmenSafetyModerationCoordinator.moderate"

        guard let text = input.text, !text.isEmpty else {
            // No text to screen on this surface => nothing for toxicity to do.
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        let result = await AmenSafetyModerationCoordinator.shared.moderate(
            text: text,
            context: input.surface.moderationContext
        )

        if result.allowed {
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: result.categories,
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        // Not allowed. .uncertain (provider error on guard surface) => fail-closed.
        if result.severity == .uncertain {
            return PrePublishFailClosed.verdict(hook: kind, reason: .providerUncertain, source: source)
        }

        // Deterministic block from the coordinator. .review => hold, .block => block.
        let decision: HookDecision = (result.severity == .review) ? .holdForReview : .blockCommit
        return HookVerdict(
            hook: kind,
            decision: decision,
            reason: .toxic,
            categories: result.categories,
            confidence: 1.0,
            source: source,
            requiresHumanReview: result.severity != .block,
            evaluatedAt: Date().timeIntervalSince1970 * 1000
        )
    }
}

private extension PrePublishSurface {
    /// Maps a write surface to the moderation coordinator's context. DM stays the guard surface.
    var moderationContext: AmenModerationContext {
        switch self {
        case .dm:           return .dm
        case .comment:      return .comment
        case .post, .note:  return .post
        case .mediaCaption: return .post
        }
    }
}

// MARK: - Hook 2: ClaimScriptureContextHook (delegates BereanCitationGate)

/// Delegates to the existing `BereanCitationGate`. The gate is itself fail-closed: when
/// its flag is OFF, or the source is down, it returns `.unverifiable`, and only `.verified`
/// / `.paraphrase` clear (`CitationVerdict.shouldBlock`). This hook detects scripture
/// claims in the text and, when present, requires the gate to clear them before commit.
struct ClaimScriptureContextHook: PrePublishHook {

    let kind: PrePublishHookKind = .claimScriptureContext
    let order: Int = 2
    let flagGated: Bool = true

    /// Pure structural detection of "does this text claim a scripture reference?".
    /// No network, no model. When false the hook clears (nothing to verify).
    private let claimsScripture: @Sendable (String) -> Bool
    /// The verse reference + claimed quotation to hand the gate, when a claim is present.
    private let extractClaim: @Sendable (String) -> (reference: String, quotation: String)?

    init(
        claimsScripture: @escaping @Sendable (String) -> Bool = { text in
            // Conservative reference shape: "Book chapter:verse". Real extraction is wired
            // at the call sites in later waves; this keeps the hook self-contained + fail-safe.
            text.range(of: #"[A-Z1-3][a-z]+\.?\s+\d+:\d+"#, options: .regularExpression) != nil
        },
        extractClaim: @escaping @Sendable (String) -> (reference: String, quotation: String)? = { text in
            guard let r = text.range(of: #"[A-Z1-3][a-z]+\.?\s+\d+:\d+"#, options: .regularExpression) else {
                return nil
            }
            return (String(text[r]), text)
        }
    ) {
        self.claimsScripture = claimsScripture
        self.extractClaim = extractClaim
    }

    func evaluate(_ input: PrePublishHookInput) async -> HookVerdict {
        let source = "BereanCitationGate"

        guard let text = input.text, !text.isEmpty, claimsScripture(text),
              let claim = extractClaim(text) else {
            // No scripture claim => nothing for the citation hook to gate.
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        // Delegate to the existing gate. shouldBlock is true for fabricated/unverifiable/flagged.
        let (verdict, shouldBlock) = await BereanCitationGate.guardedEmit(
            reference: claim.reference,
            quotation: claim.quotation,
            depth: .study
        )

        if !shouldBlock {
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: verdict.confidence,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        // Map the citation result to a fail-closed verdict (PP-I5 fixed switch).
        switch verdict.result {
        case .fabricated, .flagged:
            return HookVerdict(
                hook: kind,
                decision: .blockCommit,
                reason: .fabricatedCitation,
                categories: ["misinformation"],
                confidence: verdict.confidence,
                source: source,
                requiresHumanReview: true,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        case .unverifiable:
            // Source down / status never reached verified => fail-closed hold.
            return PrePublishFailClosed.verdict(hook: kind, reason: .pendingCitation, source: source)
        case .verified, .paraphrase:
            // Unreachable (shouldBlock would be false) — defensive clear.
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: verdict.confidence,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }
    }
}

// MARK: - Hook 3: ProvenanceStampHook (delegates PostTrustAnalysisService, stampOnly)

/// Delegates to the existing `PostTrustAnalysisService` to attach an advisory provenance
/// label. C2PA / deepfake provenance is an ADVISORY LABEL ONLY — it is never a person
/// score (PP-I6) and never blocks on its own. This hook therefore returns `.stampOnly`
/// when a label is attached and `.proceed` when there is nothing to stamp; it never
/// returns `.blockCommit`.
struct ProvenanceStampHook: PrePublishHook {

    let kind: PrePublishHookKind = .provenanceStamp
    let order: Int = 3
    let flagGated: Bool = true

    /// Produces AuthenticityKind raw values for the content. The real delivery decision
    /// (pending => hold, quarantined => block) is owned by MediaAuthenticityService and is
    /// wired in a later wave; absent that service in this worktree, the hook is stamp-only.
    private let provenanceLabels: @Sendable (PrePublishHookInput) -> [String]

    init(
        provenanceLabels: @escaping @Sendable (PrePublishHookInput) -> [String] = { input in
            // No media => no provenance label to attach.
            input.hasMedia ? ["pending_review"] : []
        }
    ) {
        self.provenanceLabels = provenanceLabels
    }

    func evaluate(_ input: PrePublishHookInput) async -> HookVerdict {
        let source = "PostTrustAnalysisService"
        let labels = provenanceLabels(input)

        guard !labels.isEmpty else {
            return HookVerdict(
                hook: kind,
                decision: .proceed,
                reason: .clean,
                categories: [],
                confidence: 1.0,
                source: source,
                requiresHumanReview: false,
                evaluatedAt: Date().timeIntervalSince1970 * 1000
            )
        }

        return HookVerdict(
            hook: kind,
            decision: .stampOnly,
            reason: .stamped,
            categories: labels,       // AuthenticityKind raw values surfaced as provenanceLabels.
            confidence: 1.0,
            source: source,
            requiresHumanReview: false,
            evaluatedAt: Date().timeIntervalSince1970 * 1000
        )
    }
}

// MARK: - Default chain assembly

extension HookChain {
    /// Builds the frozen-order chain with the four production hooks. Child-safety first.
    static func standard() -> HookChain {
        HookChain(hooks: [
            ChildSafetyHashHook(),
            ToxicityHook(),
            ClaimScriptureContextHook(),
            ProvenanceStampHook(),
        ])
    }
}
