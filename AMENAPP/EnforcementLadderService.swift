
//
//  EnforcementLadderService.swift
//  AMENAPP
//
//  Enforcement ladder service — enforces the constitution's Level 0–5 ladder
//  on the client side and provides the Transparency Centre data model.
//
//  The AUTHORITATIVE enforcement decision is always made server-side.
//  This service:
//    • Reads `user_trust/{uid}` to know the current account status.
//    • Reads `enforcement_actions/{id}` for the user's enforcement history.
//    • Checks capabilities before allowing actions (post, comment, DM, etc.).
//    • Surfaces the TransparencyCentreView with a plain-language history.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

// MARK: - EnforcementLadderService

@Observable
@MainActor
final class EnforcementLadderService {

    static let shared = EnforcementLadderService()
    private init() {}

    // MARK: - Published State

    /// Current trust profile for the signed-in user. nil = not yet loaded.
    private(set) var trustProfile: UserTrustProfile?

    /// Recent enforcement actions taken against this user.
    private(set) var enforcementHistory: [ConstitutionEnforcementAction] = []

    /// Whether the user's account is currently restricted in any way.
    var isRestricted: Bool {
        guard let p = trustProfile else { return false }
        return p.accountStatus != .active
    }

    var isFrozen: Bool {
        trustProfile?.accountStatus == .frozen
    }

    var isBanned: Bool {
        trustProfile?.accountStatus == .banned
    }

    // MARK: - Capability Checks

    /// Returns true if the current user is allowed to post.
    var canPost: Bool {
        trustProfile?.canPost ?? true
    }

    var canComment: Bool {
        trustProfile?.canComment ?? true
    }

    var canDM: Bool {
        trustProfile?.canDM ?? true
    }

    var canUploadMedia: Bool {
        trustProfile?.canUploadMedia ?? true
    }

    var canShareLinks: Bool {
        trustProfile?.canShareLinks ?? true
    }

    // MARK: - Load

    func loadCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTrustProfile(uid: uid) }
            group.addTask { await self.loadEnforcementHistory(uid: uid) }
        }
    }

    private func loadTrustProfile(uid: String) async {
        let db = Firestore.firestore()
        do {
            let doc = try await db.collection("user_trust").document(uid).getDocument()
            if doc.exists {
                trustProfile = try doc.data(as: UserTrustProfile.self)
            }
        } catch {
            // user_trust doc doesn't exist yet for new users — that's fine
        }
    }

    private func loadEnforcementHistory(uid: String) async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("enforcement_actions")
                .whereField("target_user_id", isEqualTo: uid)
                .order(by: "created_at", descending: true)
                .limit(to: 20)
                .getDocuments()
            enforcementHistory = snap.documents.compactMap {
                try? $0.data(as: ConstitutionEnforcementAction.self)
            }
        } catch {
            // Enforcement collection may be empty — not an error
        }
    }

    // MARK: - Appeal submission

    /// Submits a user appeal for an enforcement action.
    func submitAppeal(for action: ConstitutionEnforcementAction, statement: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid,
              let actionId = action.id else { return }

        let db = Firestore.firestore()
        let appeal: [String: Any] = [
            "user_id": uid,
            "enforcement_action_id": actionId,
            "content_id": action.contentId as Any,
            "content_type": action.contentType?.rawValue as Any,
            "status": "pending",
            "user_statement": String(statement.prefix(1000)),
            "submitted_at": FieldValue.serverTimestamp()
        ]

        try await db.collection("moderation_appeals").addDocument(data: appeal)
    }
}

// MARK: - Restriction Banner View

/// Banner displayed at the top of CreatePostView / MessagesView when the
/// user's account is restricted. Shows a plain-language summary and a
/// link to the Transparency Centre.
struct RestrictionBannerView: View {
    @Environment(\.openURL) private var openURL

    let profile: UserTrustProfile
    @State private var showTransparency = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showTransparency = true
                } label: {
                    Text("Details")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(tint.opacity(0.08))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(0.2))
                    .frame(height: 0.5)
            }
        }
        .sheet(isPresented: $showTransparency) {
            TransparencyCentreView()
        }
    }

    private var icon: String {
        switch profile.accountStatus {
        case .warned:        return "exclamationmark.triangle.fill"
        case .restricted:    return "minus.circle.fill"
        case .cooldown:      return "clock.fill"
        case .frozen:        return "lock.fill"
        case .banned:        return "xmark.circle.fill"
        default:             return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch profile.accountStatus {
        case .warned:        return .orange
        case .restricted:    return .orange
        case .cooldown:      return .yellow
        case .frozen:        return .red
        case .banned:        return .red
        default:             return .blue
        }
    }

    private var title: String {
        switch profile.accountStatus {
        case .warned:     return "Account Warning"
        case .restricted: return "Posting Restricted"
        case .cooldown:   return "Posting Paused"
        case .frozen:     return "Account Suspended"
        case .banned:     return "Account Banned"
        default:          return "Account Notice"
        }
    }

    private var subtitle: String {
        switch profile.accountStatus {
        case .warned:
            return "You've received a warning. Further violations may lead to restrictions."
        case .restricted:
            return "Some features are limited. Tap Details to learn more."
        case .cooldown:
            if let exp = profile.cooldownExpiresAt {
                let remaining = exp.dateValue().timeIntervalSince(Date())
                if remaining > 0 {
                    let hours = Int(remaining / 3600)
                    return "You can post again in \(max(1, hours)) hour\(hours == 1 ? "" : "s")."
                }
            }
            return "Posting is temporarily paused."
        case .frozen:
            if let exp = profile.freezeExpiresAt {
                let remaining = exp.dateValue().timeIntervalSince(Date())
                if remaining > 0 {
                    let days = Int(remaining / 86400)
                    return "Account suspended for \(max(1, days)) more day\(days == 1 ? "" : "s")."
                }
            }
            return "Your account has been suspended."
        case .banned:
            return "Your account has been permanently banned for repeated violations."
        default:
            return "There is a notice on your account."
        }
    }
}

// MARK: - Transparency Centre

/// Sheet that shows the user's enforcement history, active restrictions,
/// and allows them to file an appeal.
struct TransparencyCentreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = EnforcementLadderService.shared
    @State private var showingAppealSheet = false
    @State private var selectedAction: ConstitutionEnforcementAction?

    var body: some View {
        NavigationStack {
            List {
                // ── Account Status ──────────────────────────────────────────
                if let profile = service.trustProfile {
                    Section("Account Status") {
                        HStack {
                            Label(profile.trustLevel.rawValue.capitalized, systemImage: "person.badge.shield.checkmark.fill")
                            Spacer()
                            Text(profile.accountStatus.rawValue.capitalized)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(statusColor(profile.accountStatus))
                        }

                        if profile.strikes > 0 {
                            HStack {
                                Label("Active Strikes", systemImage: "exclamationmark.circle")
                                Spacer()
                                Text("\(profile.strikes)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Text("Account in good standing")
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // ── Enforcement History ────────────────────────────────────
                if service.enforcementHistory.isEmpty {
                    Section("Enforcement History") {
                        Label("No enforcement actions on record.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Section("Enforcement History") {
                        ForEach(service.enforcementHistory) { action in
                            EnforcementActionRow(action: action) {
                                selectedAction = action
                                showingAppealSheet = true
                            }
                        }
                    }
                }

                // ── Community Guidelines Link ──────────────────────────────
                Section {
                    Link(destination: URL(string: "https://amenapp.com/guidelines")!) {
                        Label("Community Guidelines", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://amenapp.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Transparency Centre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAppealSheet) {
                if let action = selectedAction, let actionId = action.id {
                    AppealSubmissionView(enforcementId: actionId)
                }
            }
            .task {
                await service.loadCurrentUser()
            }
        }
    }

    private func statusColor(_ status: UserTrustProfile.AccountStatus) -> Color {
        switch status {
        case .active:     return .green
        case .warned:     return .orange
        case .restricted: return .orange
        case .cooldown:   return .yellow
        case .frozen:     return .red
        case .banned:     return .red
        case .blocked:    return .red
        }
    }
}

// MARK: - Enforcement Action Row

private struct EnforcementActionRow: View {
    let action: ConstitutionEnforcementAction
    let onAppeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(action.action.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(action.createdAt.dateValue(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = action.reasonSummary as String? {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Appeal button — only if within the appeal window
            if canAppeal {
                Button(action: onAppeal) {
                    Label("File an Appeal", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var canAppeal: Bool {
        guard let deadline = action.appealDeadline else { return false }
        return deadline.dateValue() > Date()
    }
}

// Note: AppealSubmissionView is defined in SafetyUIComponents.swift (takes enforcementId: String).
