// GuardianPrePublishContracts.swift
// AMENAPP — Feature C · GUARDIAN PrePublish hook chain (Wave 0 contracts)
//
// Field-for-field Swift mirror of the TS source of truth:
//   Backend/functions/src/contracts/guardianPrePublish.ts
// Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.2 (Feature C) + §8.3 (hook chain).
//
// WHAT THIS IS: a deterministic, fail-closed orderer that EVERY write path
// (comment/post/note/dm/mediaCaption) routes through BEFORE the Firestore commit.
// It owns NO detection logic — every hook delegates to an existing real seam.
//
// INVARIANTS:
//   PP-I2  fixed order; short-circuit on first .blockCommit.
//   PP-I3  childSafetyHash is index 0, unconditional (never flag-gated), fail-closed.
//   PP-I4  throw/timeout => .holdForReview on guard surfaces / when the flag is ON.
//   PP-I5  deterministic mapping (signal => verdict is a fixed switch — never model vibes).
//   PP-I6  no person score is ever produced.
//   PP-I8  flag OFF => hooks 1–3 run in shadow/observe; only hook 0 blocks.

import Foundation

// MARK: - Surfaces, hook kinds, decisions, reason codes

enum PrePublishSurface: String, Codable, CaseIterable, Sendable {
    case comment      = "comment"
    case post         = "post"
    case note         = "note"
    case dm           = "dm"
    case mediaCaption = "mediaCaption"

    /// Guard surfaces MUST fail-secure (block/hold on provider error). Mirrors
    /// AmenModerationContext.isGuardSurface — DM is the canonical guard surface.
    var isGuardSurface: Bool {
        switch self {
        case .dm:                              return true
        case .comment, .post, .note, .mediaCaption: return false
        }
    }
}

enum PrePublishHookKind: String, Codable, CaseIterable, Sendable {
    case childSafetyHash      = "childSafetyHash"
    case toxicity             = "toxicity"
    case claimScriptureContext = "claimScriptureContext"
    case provenanceStamp      = "provenanceStamp"
}

/// Most-severe wins: blockCommit > holdForReview > stampOnly > proceed > shadowObserve.
enum HookDecision: String, Codable, CaseIterable, Sendable {
    case proceed       = "proceed"
    case stampOnly     = "stampOnly"
    case holdForReview = "holdForReview"
    case blockCommit   = "blockCommit"
    case shadowObserve = "shadowObserve"

    /// Severity rank for the most-severe reducer. Higher wins.
    var severity: Int {
        switch self {
        case .blockCommit:   return 4
        case .holdForReview: return 3
        case .stampOnly:     return 2
        case .proceed:       return 1
        case .shadowObserve: return 0
        }
    }
}

/// Coarse, audit-only reason codes. Never displayed; never a person score (PP-I6).
enum HookReasonCode: String, Codable, CaseIterable, Sendable {
    case clean                  = "clean"
    case noScreener             = "noScreener"
    case hashMatch              = "hashMatch"
    case providerError          = "providerError"
    case providerUncertain      = "providerUncertain"
    case toxic                  = "toxic"
    case fabricatedCitation     = "fabricatedCitation"
    case pendingCitation        = "pendingCitation"
    case provenancePending      = "provenancePending"
    case provenanceQuarantined  = "provenanceQuarantined"
    case stamped                = "stamped"
    case shadow                 = "shadow"
}

// MARK: - Per-hook verdict + whole-chain verdict

struct HookVerdict: Codable, Sendable {
    let hook: PrePublishHookKind
    let decision: HookDecision
    let reason: HookReasonCode
    let categories: [String]        // ModerationCategory raw values.
    let confidence: Double          // coarse, never displayed.
    let source: String              // the real seam that produced this verdict.
    let requiresHumanReview: Bool
    let evaluatedAt: TimeInterval   // epoch millis.
}

struct ChainVerdict: Codable, Sendable {
    let surface: PrePublishSurface
    let contentRef: String?
    let verdicts: [HookVerdict]
    let finalDecision: HookDecision
    let mayCommit: Bool             // true ONLY when finalDecision is .proceed | .stampOnly.
    let provenanceLabels: [String]  // AuthenticityKind raw values.
    let flagEnabled: Bool
    let evaluatedAt: TimeInterval
}

/// PP-I7: any non-proceed verdict is written to /moderationQueue as one of these.
struct PrePublishEscalationRecord: Codable, Sendable {
    let surface: PrePublishSurface
    let contentRef: String?
    let hook: PrePublishHookKind
    let decision: HookDecision
    let reason: HookReasonCode
    let categories: [String]
    let escalateImmediately: Bool   // true for childSafetyHash hashMatch (=> type 'csam').
    let queueType: QueueType
    let createdAt: TimeInterval

    enum QueueType: String, Codable, Sendable {
        case csam   = "csam"
        case review = "review"
    }
}

// MARK: - Hook protocol + chain input

/// A single deterministic, fail-closed pre-commit interceptor. Owns no detection
/// logic — delegates to an existing real seam and returns fail-closed on uncertainty.
protocol PrePublishHook: Sendable {
    var kind: PrePublishHookKind { get }
    var order: Int { get }
    var flagGated: Bool { get }
    func evaluate(_ input: PrePublishHookInput) async -> HookVerdict
}

struct PrePublishHookInput: Sendable {
    let surface: PrePublishSurface
    let contentRef: String?
    let text: String?
    let imageData: Data?
    let hasMedia: Bool
    let flagEnabled: Bool

    var isGuardSurface: Bool { surface.isGuardSurface }

    init(
        surface: PrePublishSurface,
        contentRef: String?,
        text: String? = nil,
        imageData: Data? = nil,
        hasMedia: Bool = false,
        flagEnabled: Bool
    ) {
        self.surface = surface
        self.contentRef = contentRef
        self.text = text
        self.imageData = imageData
        self.hasMedia = hasMedia
        self.flagEnabled = flagEnabled
    }
}

// MARK: - Frozen ordering (PP-I2/PP-I3)

/// childSafetyHash is index 0 and is NEVER flag-gated. Order is fixed.
enum PrePublishHookOrder {
    struct Entry: Sendable {
        let kind: PrePublishHookKind
        let order: Int
        let flagGated: Bool
    }

    /// Mirrors TS `PREPUBLISH_HOOK_ORDER`.
    static let frozen: [Entry] = [
        Entry(kind: .childSafetyHash,       order: 0, flagGated: false),
        Entry(kind: .toxicity,              order: 1, flagGated: true),
        Entry(kind: .claimScriptureContext, order: 2, flagGated: true),
        Entry(kind: .provenanceStamp,       order: 3, flagGated: true),
    ]
}

/// Remote Config key for the master enforcement flag (gates hooks 1–3 only).
let guardianPrePublishFlagKey = "guardian_pre_publish_enabled"

// MARK: - Fail-closed helpers (PP-I3/PP-I4)

enum PrePublishFailClosed {
    /// The single source of "deny when unevaluable". There is NO path where the absence
    /// of an affirmative allow maps to .proceed — the absence IS a denial.
    static func verdict(
        hook: PrePublishHookKind,
        reason: HookReasonCode,
        source: String
    ) -> HookVerdict {
        // childSafetyHash fails to a hard block; the other hooks fail to a review hold.
        let decision: HookDecision = (hook == .childSafetyHash) ? .blockCommit : .holdForReview
        return HookVerdict(
            hook: hook,
            decision: decision,
            reason: reason,
            categories: (hook == .childSafetyHash) ? ["child_safety"] : [],
            confidence: 0,
            source: source,
            requiresHumanReview: true,
            evaluatedAt: Date().timeIntervalSince1970 * 1000
        )
    }
}

// MARK: - HookChain (the orderer, with the most-severe reducer)

/// Runs hooks in frozen order, short-circuits on the first .blockCommit, and reduces
/// the surviving decisions to a chain verdict via the most-severe reducer.
final class HookChain: @unchecked Sendable {

    private let hooks: [PrePublishHook]

    /// Hooks must be supplied in their frozen order (childSafetyHash first).
    init(hooks: [PrePublishHook]) {
        self.hooks = hooks.sorted { $0.order < $1.order }
    }

    /// PP-I1/PP-I2/PP-I8 entry point. Every write path calls this before commit.
    func run(_ input: PrePublishHookInput) async -> ChainVerdict {
        var verdicts: [HookVerdict] = []
        var provenanceLabels: [String] = []

        for hook in hooks {
            // PP-I8: when the flag is OFF, a flag-gated hook only observes. The
            // unconditional child-safety hook (flagGated == false) always enforces.
            let enforcing = hook.flagGated == false || input.flagEnabled

            let verdict = await hook.evaluate(input)

            if hook.kind == .provenanceStamp, verdict.decision == .stampOnly {
                // Provenance attaches advisory labels; categories carry AuthenticityKind raws.
                provenanceLabels.append(contentsOf: verdict.categories)
            }

            if enforcing {
                verdicts.append(verdict)
                // PP-I2: short-circuit on the first hard block.
                if verdict.decision == .blockCommit {
                    break
                }
            } else {
                // Shadow/observe: record what WOULD have happened without enforcing it.
                verdicts.append(
                    HookVerdict(
                        hook: verdict.hook,
                        decision: .shadowObserve,
                        reason: .shadow,
                        categories: verdict.categories,
                        confidence: verdict.confidence,
                        source: verdict.source,
                        requiresHumanReview: false,
                        evaluatedAt: verdict.evaluatedAt
                    )
                )
            }
        }

        let finalDecision = Self.reduce(verdicts.map { $0.decision })
        return ChainVerdict(
            surface: input.surface,
            contentRef: input.contentRef,
            verdicts: verdicts,
            finalDecision: finalDecision,
            mayCommit: Self.mayCommit(finalDecision),
            provenanceLabels: provenanceLabels,
            flagEnabled: input.flagEnabled,
            evaluatedAt: Date().timeIntervalSince1970 * 1000
        )
    }

    /// Most-severe reducer. Empty chain (no media, flag OFF) reduces to .proceed.
    static func reduce(_ decisions: [HookDecision]) -> HookDecision {
        var worst: HookDecision = .proceed
        for d in decisions where d.severity > worst.severity {
            worst = d
        }
        return worst
    }

    /// A chain may commit only when nothing more severe than a provenance stamp survived.
    static func mayCommit(_ finalDecision: HookDecision) -> Bool {
        finalDecision == .proceed || finalDecision == .stampOnly
    }

    /// Builds the escalation record for a non-proceed verdict (PP-I7). Returns nil when
    /// the verdict is committable (no escalation needed).
    static func escalation(
        for verdict: HookVerdict,
        surface: PrePublishSurface,
        contentRef: String?
    ) -> PrePublishEscalationRecord? {
        guard verdict.decision != .proceed,
              verdict.decision != .stampOnly,
              verdict.decision != .shadowObserve else {
            return nil
        }
        let isCSAMHash = verdict.hook == .childSafetyHash && verdict.reason == .hashMatch
        return PrePublishEscalationRecord(
            surface: surface,
            contentRef: contentRef,
            hook: verdict.hook,
            decision: verdict.decision,
            reason: verdict.reason,
            categories: verdict.categories,
            escalateImmediately: isCSAMHash,
            queueType: isCSAMHash ? .csam : .review,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
    }
}
