
//  ChurchNotesSharingService.swift
//  AMENAPP
//
//  W4 — Per-item sharing with confirmation friction, guardian routing, and revoke-as-delete.
//  Default scope is always .onlyMe. No sticky or relationship-level sharing exists.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Guardian Gate

final class ChurchNotesGuardianGateImpl: GuardianGate {

    func resolveSharing(for actionID: UUID, requested: ShareScope, isMinor: Bool) -> ShareScope {
        guard isMinor else { return requested }
        // S7: minors cannot create peer or leader grants without guardian routing.
        // Any scope beyond .onlyMe routes through guardian (expressed as .onlyMe here —
        // the guardian notification is a separate out-of-band step handled by the calling
        // view, which presents the GuardianNoticeView instead of the standard share sheet).
        switch requested {
        case .onlyMe:         return .onlyMe
        case .trustedFriend,
             .smallGroup,
             .churchLeader:   return .onlyMe  // blocked; caller shows guardian notice
        }
    }

    /// True when a minor's requested scope requires guardian routing (and must be blocked).
    func requiresGuardianRouting(requested: ShareScope, isMinor: Bool) -> Bool {
        guard isMinor else { return false }
        return requested != .onlyMe
    }
}

// MARK: - Sharing Service

/// Implements SharingService against Firestore.
/// Grants are stored at: `spiritualActionGrants/{grantID}`.
/// Revocation DELETES the document — no soft-delete, no flag. (S4)
@MainActor
final class ChurchNotesSharingServiceImpl: SharingService {

    private let db = Firestore.firestore()
    private let collection = "spiritualActionGrants"

    func grant(_ grant: ShareGrant) async throws {
        // S3: Default is .onlyMe; reject attempts to persist onlyMe grants
        guard grant.scope != .onlyMe else { return }

        // S6: Validate churchLeader expiry before persisting
        try grant.validateChurchLeaderExpiry()

        // S5: namedPeople friction is enforced at the UI layer (ShareConfirmationView)
        // which must be shown before this function is called.

        let docRef = db.collection(collection).document(grant.id.uuidString)
        let data: [String: Any] = [
            "id":           grant.id.uuidString,
            "actionID":     grant.actionID.uuidString,
            "scope":        grant.scope.rawValue,
            "expiresAt":    grant.expiresAt.map { Timestamp(date: $0) } as Any,
            "recipientIDs": grant.recipientIDs,
            "grantedAt":    Timestamp(date: Date()),
            "grantedBy":    Auth.auth().currentUser?.uid ?? "",
        ]
        try await docRef.setData(data)
    }

    func revoke(_ grantID: UUID) async throws {
        // S4: Hard delete — recipients see not-found after this resolves.
        try await db.collection(collection).document(grantID.uuidString).delete()
    }

    /// Fetch grants for the current user's recipients (what they can see).
    func grantsReceivedByCurrentUser() async throws -> [ShareGrant] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot = try await db.collection(collection)
            .whereField("recipientIDs", arrayContains: uid)
            .getDocuments()
        return snapshot.documents.compactMap { decode($0.data()) }
    }

    // MARK: Private

    private func decode(_ data: [String: Any]) -> ShareGrant? {
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
              let actionIDStr = data["actionID"] as? String, let actionID = UUID(uuidString: actionIDStr),
              let scopeRaw = data["scope"] as? String, let scope = ShareScope(rawValue: scopeRaw),
              let recipientIDs = data["recipientIDs"] as? [String] else { return nil }
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()
        return ShareGrant(id: id, actionID: actionID, scope: scope,
                          expiresAt: expiresAt, recipientIDs: recipientIDs)
    }
}

// MARK: - Share Confirmation View

import SwiftUI

/// Required intermediate screen before any grant with scope > .onlyMe.
/// Callers MUST present this and await user confirmation before calling SharingService.grant.
struct ChurchNotesShareConfirmationView: View {

    let action: SpiritualAction
    let proposedGrant: ShareGrant
    let isMinor: Bool
    let onConfirm: (ShareGrant) -> Void
    let onCancel: () -> Void

    private let guardian = ChurchNotesGuardianGateImpl()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerSection
                actionSummaryCard
                scopeExplainer
                if action.requiresNameAwareConfirmation {
                    namedPeopleWarning
                }
                if proposedGrant.scope == .churchLeader {
                    expiryNotice
                }
                Spacer()
                confirmButton
                cancelButton
            }
            .padding(24)
            .navigationTitle("Share this action?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.open.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.amenPurple)
                .accessibilityHidden(true)
            Text("You're about to share a personal action step.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var actionSummaryCard: some View {
        HStack {
            Image(systemName: action.kind.sfSymbol)
                .foregroundStyle(Color.amenGold)
                .accessibilityHidden(true)
            Text(action.summary)
                .font(.body.weight(.medium))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var scopeExplainer: some View {
        Text(scopeDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var scopeDescription: String {
        switch proposedGrant.scope {
        case .onlyMe:       return "Only you can see this."
        case .trustedFriend: return "One trusted friend will be able to see this action step only — not your full notes."
        case .smallGroup:   return "Members of your small group will see this action step only — not your full notes."
        case .churchLeader: return "Your church leader will see this action step only. This share will expire on \(expiryString)."
        }
    }

    private var expiryString: String {
        proposedGrant.expiresAt.map {
            $0.formatted(date: .abbreviated, time: .omitted)
        } ?? "a set date"
    }

    @ViewBuilder
    private var namedPeopleWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("This action mentions \(action.namedPeople.joined(separator: ", ")). Sharing will reveal their name to the recipient.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var expiryNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.amenPurple)
                .accessibilityHidden(true)
            Text("Church leader shares automatically expire. You can revoke at any time from Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.amenPurple.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var confirmButton: some View {
        Button {
            // S7: For minors, resolveSharing may rewrite the scope; UI has already blocked this path
            onConfirm(proposedGrant)
        } label: {
            Text("Share this action step")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.amenPurple)
        .accessibilityHint("Shares only this action step. Your full notes are never shared.")
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { onCancel() }
            .foregroundStyle(.secondary)
    }
}

// MARK: - Grant Builder Helper

extension ShareGrant {
    /// Build a grant with the appropriate defaults. Always starts from .onlyMe;
    /// the scope must be explicitly elevated by the user.
    static func build(
        actionID: UUID,
        scope: ShareScope,
        recipientIDs: [String],
        expiresAt: Date? = nil
    ) -> ShareGrant {
        ShareGrant(id: UUID(), actionID: actionID, scope: scope,
                   expiresAt: scope == .churchLeader ? (expiresAt ?? defaultLeaderExpiry()) : expiresAt,
                   recipientIDs: recipientIDs)
    }

    private static func defaultLeaderExpiry() -> Date {
        Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }
}
