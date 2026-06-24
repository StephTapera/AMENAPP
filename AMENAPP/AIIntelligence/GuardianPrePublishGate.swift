// GuardianPrePublishGate.swift
// AMENAPP — Feature C · GUARDIAN PrePublish gate (C-Wave-5 seam)
//
// The single seam every write path calls BEFORE its Firestore commit. It wraps
// HookChain.standard().run(...) and, on a non-committable verdict, persists the
// fail-closed escalation records to /moderationQueue (PP-I7). It owns NO detection
// logic — every signal comes from the hooks, which delegate to existing real seams.
//
// Why a dedicated seam: the five write paths (comment / DM / media / post / prayer
// caption) live in peer-hot files. Concentrating the run+escalate logic here keeps
// each call-site insertion to a few lines (see audit/CWAVE5_WIRING.md), so wiring the
// chain never reshapes a hot file.
//
// Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.2/§8.3 + audit/DEPLOY_RUNBOOK.md §3.
//
// INVARIANTS honored here:
//   PP-I1  every write path routes through gate() before commit.
//   PP-I7  any non-proceed verdict is written to /moderationQueue (csam => immediate).
//   PP-I8  when guardian_pre_publish_enabled is OFF, hooks 1–3 only shadow-observe;
//          hook 0 (child-safety hash) still enforces. The flag is read here, once.
//   Fail-closed: a /moderationQueue write failure NEVER turns a block into an allow —
//   the caller blocks on `!verdict.mayCommit`, independent of the queue write.

import Foundation
import FirebaseFirestore

@MainActor
final class GuardianPrePublishGate {

    static let shared = GuardianPrePublishGate()

    private init() {}

    private var moderationQueue: CollectionReference {
        Firestore.firestore().collection("moderationQueue")
    }

    /// Runs the frozen hook chain for `surface` and returns the whole-chain verdict.
    /// Callers MUST block their commit when `verdict.mayCommit == false`.
    ///
    /// - Parameters:
    ///   - surface: the write surface (drives guard-surface fail-secure + hook context).
    ///   - contentRef: stable id of the content (commentId / messageId / postId / sessionId).
    ///   - text: the user text to screen (toxicity + scripture-claim hooks).
    ///   - imageData: encoded bytes for media-bearing writes (child-safety hash hook).
    ///   - hasMedia: whether this write carries media (gates the hash + provenance hooks).
    func gate(
        surface: PrePublishSurface,
        contentRef: String?,
        text: String? = nil,
        imageData: Data? = nil,
        hasMedia: Bool = false
    ) async -> ChainVerdict {
        let input = PrePublishHookInput(
            surface: surface,
            contentRef: contentRef,
            text: text,
            imageData: imageData,
            hasMedia: hasMedia,
            flagEnabled: AMENFeatureFlags.shared.guardianPrePublishEnabled
        )

        let verdict = await HookChain.standard().run(input)

        // PP-I7: persist escalation records for every non-committable verdict before the
        // caller returns. Done regardless of flag state — the chain already downgraded
        // flag-gated hooks to .shadowObserve when OFF, so only real blocks escalate here.
        if !verdict.mayCommit {
            await persistEscalations(verdict, surface: surface, contentRef: contentRef)
        }

        return verdict
    }

    /// Convenience: returns true when the surface may commit. Use at call sites that only
    /// need the boolean and ignore the provenance labels.
    func mayCommit(
        surface: PrePublishSurface,
        contentRef: String?,
        text: String? = nil,
        imageData: Data? = nil,
        hasMedia: Bool = false
    ) async -> Bool {
        await gate(
            surface: surface,
            contentRef: contentRef,
            text: text,
            imageData: imageData,
            hasMedia: hasMedia
        ).mayCommit
    }

    // MARK: - Escalation (PP-I7)

    private func persistEscalations(
        _ verdict: ChainVerdict,
        surface: PrePublishSurface,
        contentRef: String?
    ) async {
        for hookVerdict in verdict.verdicts {
            guard let record = HookChain.escalation(
                for: hookVerdict,
                surface: surface,
                contentRef: contentRef
            ) else { continue }

            let data: [String: Any] = [
                "surface": record.surface.rawValue,
                "contentRef": record.contentRef as Any,
                "hook": record.hook.rawValue,
                "decision": record.decision.rawValue,
                "reason": record.reason.rawValue,
                "categories": record.categories,
                "escalateImmediately": record.escalateImmediately,
                // `type` is the /moderationQueue discriminator the human-review dashboard
                // reads ("csam" routes to the CSAM lane; "review" to standard triage).
                "type": record.queueType.rawValue,
                "createdAt": record.createdAt,
                "source": "guardian_prepublish"
            ]

            do {
                try await moderationQueue.addDocument(data: data)
            } catch {
                // Intentionally swallow: the caller has ALREADY blocked the commit on
                // !mayCommit. A queue-write failure must never relax that block (fail-closed).
                // The server-side onCreate moderation trigger is the backstop.
            }
        }
    }
}
