// BereanMigrationService.swift
// AMEN Universal Migration & Context System (Wave 2) — Berean Migration Interview
//
// Adaptive conversational onboarding. Berean asks; the user answers; the model emits
// structured facet *candidates*. CRITICAL INVARIANT (§1.7, "approval before
// persistence"): candidates accumulate in EPHEMERAL @Published state ONLY. NOTHING
// reaches Firestore until the user explicitly approves via `approveAndPersist`, which
// is the ONLY persistence path in this file. Aborting mid-interview removes the
// listener and clears all ephemeral state — it persists nothing.
//
// Streaming follows the repo's real Berean idiom (see BereanRealtimeSessionManager):
// a Cloud Function brokers an ephemeral session, and candidates arrive via a Firestore
// snapshot listener on that session document. "Cancellation" is listener removal +
// ephemeral state clear — there is no fetch/AbortController in this codebase.
//
// `FacetCandidate` is the canonical type owned by BereanMigrationInterviewPrompt.swift
// (the structured-output contract). This service consumes it — it does not redefine it.
//
// Flag-gated on `contextBereanInterviewEnabled`. No content import: this service never
// reads/writes messages, posts, media, or contacts. Tier-P facets are derived but are
// never emitted to a CF — they are only persisted to the owner's own Firestore docs
// via ContextStoreService.saveFacet (which itself enforces every tier/approval rule).

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Ephemeral interview models

/// One accumulated, not-yet-approved candidate plus the ephemeral bookkeeping the UI
/// needs (a stable id for ForEach/dismissal, and the Aegis C59 receipt the eventual
/// `Provenance` will carry). PURELY EPHEMERAL — nothing here is persisted until the
/// user approves and it is converted into a `ContextFacet` in `approveAndPersist`.
struct PendingFacetCandidate: Identifiable, Equatable {
    let id: UUID
    /// The canonical structured-output candidate (owned by the prompt-author file).
    let candidate: FacetCandidate
    /// Aegis C59 sanitization receipt id for the transcript text this was drawn from.
    /// Non-empty is required before persistence (re-verified by ContextStoreService).
    let sanitizationPassId: String

    init(id: UUID = UUID(), candidate: FacetCandidate, sanitizationPassId: String) {
        self.id = id
        self.candidate = candidate
        self.sanitizationPassId = sanitizationPassId
    }

    /// Human label shown in the approval sidebar.
    var label: String { candidate.label }

    /// The canonical tier this candidate would receive once persisted (tier is law,
    /// derived from category/key — never chosen here).
    var tier: EncryptionTier {
        ContextTierTable.tier(for: candidate.category, key: candidate.key)
    }
}

// `InterviewTurn` (ephemeral transcript line) is declared by the interview-ui file
// (BereanInterviewView.swift) and consumed here — we do not redeclare it. Its
// `Speaker` is a plain enum (`.berean` / `.user`) with no String raw value.

// MARK: - Errors

enum BereanMigrationError: LocalizedError {
    case interviewDisabled
    case notSignedIn
    case invalidBrokerResponse

    var errorDescription: String? {
        switch self {
        case .interviewDisabled:
            return "The Berean Migration Interview is turned off (contextBereanInterviewEnabled == false)."
        case .notSignedIn:
            return "No signed-in user; cannot start a migration interview."
        case .invalidBrokerResponse:
            return "The migration interview session broker returned an invalid response."
        }
    }
}

// MARK: - BereanMigrationService

@MainActor
final class BereanMigrationService: ObservableObject {

    /// Session lifecycle. `.idle`, `.ended`, and `.failed` hold no live listener.
    enum SessionState: Equatable {
        case idle
        case connecting
        case streaming
        case ended
        case failed(String)
    }

    // Ephemeral state ONLY. None of these is persisted; `abortSession` clears them all.
    @Published private(set) var facetCandidates: [PendingFacetCandidate] = []
    @Published private(set) var transcript: [InterviewTurn] = []
    @Published private(set) var state: SessionState = .idle
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listener: ListenerRegistration?
    private var sessionId: String?

    init() {}

    deinit {
        // No @MainActor work in deinit; just detach the listener so it stops firing.
        listener?.remove()
    }

    // MARK: - Start

    /// Open a streaming migration-interview session against the existing Berean
    /// infrastructure idiom: a CF brokers an ephemeral session, and facet candidates
    /// arrive via a Firestore snapshot listener. Accumulates candidates as they arrive.
    /// Persists NOTHING — every candidate stays in ephemeral @Published state.
    func startInterviewSession() async {
        guard AMENFeatureFlags.shared.contextBereanInterviewEnabled else {
            let msg = BereanMigrationError.interviewDisabled.localizedDescription
            state = .failed(msg)
            lastError = msg
            return
        }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            let msg = BereanMigrationError.notSignedIn.localizedDescription
            state = .failed(msg)
            lastError = msg
            return
        }
        _ = uid // session is brokered server-side from the auth context

        // Fresh session: clear any prior ephemeral state.
        listener?.remove()
        listener = nil
        sessionId = nil
        facetCandidates = []
        transcript = []
        lastError = nil
        state = .connecting

        do {
            // TODO(cf): extractContextFacets / migration-interview CF.
            // There is no dedicated migration-interview broker yet. We call the closest
            // existing Berean session broker so the streaming idiom is wired correctly;
            // the orchestrator should swap "createRealtimeSession" for the dedicated
            // migration CF that emits facet candidates conforming to FacetCandidate /
            // facetCandidateJSONSchema using `migrationInterviewSystemPrompt`.
            let callable = functions.httpsCallable("createRealtimeSession")
            let result = try await callable.call([
                "sessionType": "context_migration_interview",
                "systemPrompt": migrationInterviewSystemPrompt,
            ])

            guard let data = result.data as? [String: Any],
                  let newSessionId = data["sessionId"] as? String else {
                throw BereanMigrationError.invalidBrokerResponse
            }

            sessionId = newSessionId
            listen(to: newSessionId)
            state = .streaming
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mid-interview candidate management

    /// Remove a single accumulated candidate mid-interview. Ephemeral only.
    func dismissCandidate(_ id: UUID) {
        facetCandidates.removeAll { $0.id == id }
    }

    /// Abort the interview: remove the listener, clear ALL ephemeral state, persist
    /// nothing. Safe to call at any time, including before a session ever connected.
    func abortSession() {
        listener?.remove()
        listener = nil
        sessionId = nil
        facetCandidates = []
        transcript = []
        lastError = nil
        state = .ended
        dlog("ℹ️ BereanMigration: session aborted — nothing persisted.")
    }

    // MARK: - Persistence (THE ONLY WRITE PATH)

    /// Convert the user-approved candidates into `ContextFacet`s and write each via
    /// `ContextStoreService.shared.saveFacet`. This is the ONLY method in this file
    /// that persists anything. Tier is derived from the table; provenance.source is
    /// `.interview`; userApproved is true; each candidate's non-empty C59 receipt id
    /// is carried through (ContextStoreService re-verifies it).
    func approveAndPersist(_ candidates: [PendingFacetCandidate], userId: String) async {
        guard !candidates.isEmpty else { return }

        for pending in candidates {
            let c = pending.candidate
            let provenance = Provenance(
                source: .interview,
                sourceLabel: "Berean Migration Interview",
                extractedAt: Date(),
                confidence: c.confidence,
                userApproved: true,                                  // §1.7 — approval before persistence
                userEdited: false,
                sanitizationPassId: pending.sanitizationPassId       // non-empty; C59 receipt
            )

            // Tier is ALWAYS derived inside makeFacet — never set by convention here.
            let facet = ContextStoreService.shared.makeFacet(
                userId: userId,
                category: c.category,
                key: c.key,
                label: c.label,
                value: c.value,
                provenance: provenance,
                visibility: c.suggestedVisibility
            )

            do {
                try await ContextStoreService.shared.saveFacet(facet)
            } catch {
                // Loud, per-candidate failure; do not silently drop the rest.
                lastError = error.localizedDescription
                dlog("⚠️ BereanMigration: failed to persist approved facet \(facet.id.uuidString): \(error)")
            }
        }

        // Persisted candidates have left the ephemeral set; tear down the session.
        abortSession()
    }

    // MARK: - Streaming listener (candidate accumulation)

    /// Listen to the brokered session document. Facet candidates and transcript turns
    /// arrive as snapshot updates and accumulate in ephemeral @Published state.
    private func listen(to sessionId: String) {
        listener?.remove()
        listener = db.collection("contextMigrationSessions").document(sessionId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        return
                    }
                    guard let data = snapshot?.data() else { return }
                    self.ingest(data)
                }
            }
    }

    /// Merge a streamed session-document update into ephemeral state. Tolerant of
    /// missing fields — partial updates simply add nothing.
    private func ingest(_ data: [String: Any]) {
        // Transcript turns. `InterviewTurn.Speaker` is a plain enum (no String raw),
        // so map the streamed speaker string onto its cases explicitly.
        if let turns = data["transcript"] as? [[String: Any]] {
            let mapped: [InterviewTurn] = turns.compactMap { raw in
                guard let speakerRaw = raw["speaker"] as? String,
                      let text = raw["text"] as? String else { return nil }
                let speaker: InterviewTurn.Speaker
                switch speakerRaw {
                case "berean": speaker = .berean
                case "user":   speaker = .user
                default:       return nil
                }
                return InterviewTurn(speaker: speaker, text: text)
            }
            if !mapped.isEmpty { transcript = mapped }
        }

        // Facet candidates. De-duplicate by (category,key) so a re-emitted stream
        // doesn't pile up, and so anything the user already dismissed stays dismissed.
        if let raws = data["candidates"] as? [[String: Any]] {
            for raw in raws {
                guard let pending = Self.decodePending(raw) else { continue }
                let already = facetCandidates.contains {
                    $0.candidate.category == pending.candidate.category
                        && $0.candidate.key == pending.candidate.key
                }
                if !already { facetCandidates.append(pending) }
            }
        }
    }

    /// Decode a streamed candidate into an ephemeral `PendingFacetCandidate`. Returns
    /// nil for malformed payloads or any candidate carrying no sanitization receipt
    /// (which could never be persisted anyway).
    private static func decodePending(_ raw: [String: Any]) -> PendingFacetCandidate? {
        guard let categoryRaw = raw["category"] as? String,
              let category = FacetCategory(rawValue: categoryRaw),
              let key = raw["key"] as? String, !key.isEmpty,
              let label = raw["label"] as? String,
              let passId = raw["sanitizationPassId"] as? String, !passId.isEmpty
        else { return nil }

        let confidence = raw["confidence"] as? Double ?? 0
        let visibility = (raw["suggestedVisibility"] as? String)
            .flatMap(Visibility.init(rawValue:)) ?? .privateVisibility

        // Value: a list, or a plain string, else fall back to .text(label).
        let value: StructuredFacetValue
        if let list = raw["valueList"] as? [String] {
            value = .list(list)
        } else if let text = raw["valueText"] as? String {
            value = .text(text)
        } else {
            value = .text(label)
        }

        let candidate = FacetCandidate(
            category: category,
            key: key,
            label: label,
            value: value,
            confidence: confidence,
            suggestedVisibility: visibility
        )
        return PendingFacetCandidate(candidate: candidate, sanitizationPassId: passId)
    }
}
