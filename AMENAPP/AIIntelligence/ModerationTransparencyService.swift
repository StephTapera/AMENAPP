// ModerationTransparencyService.swift
// AMENAPP
//
// Wave 2 — Constitutional Moderation + Audit Trail.
//
// Read-only projection over the EXISTING append-only moderation audit log
// (moderationAuditLogs/, written by ModerationAuditLogService) into user-facing
// ModerationReceipts that name the ConstitutionalPrinciple invoked, plus a real
// Appeal submission into the EXISTING moderation_appeals/ queue (ModerationAppeal).
//
// NON-NEGOTIABLE (build brief §2):
//   - Every receipt field is read from a real audit entry — confidence is the
//     real model confidence, modelUsed/ruleTriggered are the real provider/
//     categories. Nothing is invented.
//   - The principle invoked is a deterministic classification of the real action
//     type (documented below), not a decorative label.
//   - The Appeal action writes to the real moderation_appeals collection — it is
//     not a dead button (§2.6). If Firestore rules deny the read/write, the UI
//     shows an honest unavailable state rather than fabricated history.
//
// Disjoint from the moderation write-path: this service only reads + appeals.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ModerationTransparencyService: ObservableObject {

    @Published private(set) var receipts: [ModerationReceipt] = []
    @Published private(set) var isLoading = false
    /// Honest state when the audit collection cannot be read (e.g. rules) — we
    /// never substitute fabricated history.
    @Published private(set) var unavailableReason: String? = nil

    private let db = Firestore.firestore()

    // MARK: - Load the current user's moderation history

    func load(limit: Int = 50) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            unavailableReason = "Sign in to see moderation actions on your content."
            return
        }
        isLoading = true
        unavailableReason = nil
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("moderationAuditLogs")
                .whereField("userId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()

            let entries = snapshot.documents.compactMap { doc in
                try? doc.data(as: ModerationAuditEntry.self)
            }

            // Resolve which entries already have an appeal on file.
            let appeals = await loadAppealStatuses(for: uid)
            receipts = entries.map { makeReceipt(from: $0, appeals: appeals) }
            if receipts.isEmpty {
                unavailableReason = nil // genuine empty — no actions taken
            }
        } catch {
            // Most likely Firestore rules deny client reads of the audit log.
            unavailableReason = "Moderation history is currently unavailable."
            dlog("⚠️ [ModerationTransparency] read failed: \(error.localizedDescription)")
        }
    }

    private func loadAppealStatuses(for uid: String) async -> [String: TrustAppealStatus] {
        do {
            let snapshot = try await db.collection("moderation_appeals")
                .whereField("user_id", isEqualTo: uid)
                .getDocuments()
            var map: [String: TrustAppealStatus] = [:]
            for doc in snapshot.documents {
                guard let actionId = doc.data()["enforcement_action_id"] as? String else { continue }
                let raw = doc.data()["status"] as? String ?? "pending"
                map[actionId] = mapAppealStatus(raw)
            }
            return map
        } catch {
            return [:]
        }
    }

    // MARK: - Appeal (writes to the real moderation_appeals queue)

    /// Submits an appeal for a moderation event. Returns true on a successful
    /// write to the real queue. Mirrors the ModerationAppeal wire shape.
    func submitAppeal(for receipt: ModerationReceipt, statement: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let trimmed = String(statement.prefix(1000))
        let payload: [String: Any] = [
            "user_id": uid,
            "enforcement_action_id": receipt.eventId,
            "status": ModerationAppeal.AppealStatus.pending.rawValue,
            "user_statement": trimmed,
            "submitted_at": Timestamp(date: Date())
        ]
        do {
            _ = try await db.collection("moderation_appeals").addDocument(data: payload)
            // Reflect the new status locally so the UI updates immediately.
            if let idx = receipts.firstIndex(where: { $0.eventId == receipt.eventId }) {
                receipts[idx] = receipt.withAppealStatus(.submitted)
            }
            return true
        } catch {
            dlog("⚠️ [ModerationTransparency] appeal write failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Mapping (real audit entry → user-facing receipt)

    private func makeReceipt(
        from entry: ModerationAuditEntry,
        appeals: [String: TrustAppealStatus]
    ) -> ModerationReceipt {
        let action = mapAction(entry.action)
        let existingAppeal = appeals[entry.auditId]
        let actionable = action != .allowed

        return ModerationReceipt(
            eventId: entry.auditId,
            action: action,
            principleInvoked: principle(for: action, categories: entry.categories),
            confidence: confidence(from: entry.confidence),
            modelUsed: "\(entry.provider)/\(entry.modelVersion)",
            ruleTriggered: entry.categories.isEmpty ? "—" : entry.categories.joined(separator: ", "),
            appealStatus: existingAppeal ?? (actionable ? .available : .none),
            humanReviewAvailable: actionable
        )
    }

    private func mapAction(_ action: ModerationAuditEntry.Action) -> TrustModerationAction {
        switch action {
        case .allow:                      return .allowed
        case .warnUser, .warnRecipient:   return .warned
        case .holdForReview:              return .hidden
        case .blockContent:               return .removed
        case .strikeAccount, .freezeAccount: return .removed
        }
    }

    /// Deterministic classification of the real action into the constitutional
    /// principle it serves. Documented mapping — not an invented per-event label.
    private func principle(
        for action: TrustModerationAction,
        categories: [String]
    ) -> ConstitutionalPrinciple {
        switch action {
        case .allowed:     return .humansBeforeAlgorithms      // reviewed, left up
        case .warned:      return .restorationBeforePunishment // warn before harsher action
        case .hidden:      return .contextBeforeOutrage        // held pending context
        case .downranked:  return .truthBeforeVirality         // reduced amplification
        case .removed:     return .dignityBeforeEngagement     // protects people over reach
        }
    }

    private func confidence(from score: Double) -> ReceiptConfidence {
        let pct = Int((score * 100).rounded())
        if score >= 0.75 {
            return ReceiptConfidence(band: .high, basis: "Model confidence \(pct)%", score: score)
        } else if score >= 0.5 {
            return ReceiptConfidence(band: .medium, basis: "Model confidence \(pct)%", score: score)
        } else {
            return ReceiptConfidence(band: .low, basis: "Low model confidence \(pct)%", score: score)
        }
    }

    private func mapAppealStatus(_ raw: String) -> TrustAppealStatus {
        switch raw {
        case "pending":      return .submitted
        case "under_review": return .underReview
        case "resolved":     return .upheld // outcome detail lives on the appeal doc
        default:             return .submitted
        }
    }
}

private extension ModerationReceipt {
    func withAppealStatus(_ status: TrustAppealStatus) -> ModerationReceipt {
        ModerationReceipt(
            eventId: eventId,
            action: action,
            principleInvoked: principleInvoked,
            confidence: confidence,
            modelUsed: modelUsed,
            ruleTriggered: ruleTriggered,
            appealStatus: status,
            humanReviewAvailable: humanReviewAvailable
        )
    }
}
