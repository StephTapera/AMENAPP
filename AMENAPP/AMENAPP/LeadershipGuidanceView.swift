//
//  LeadershipGuidanceView.swift
//  AMENAPP
//
//  Authority Alignment System — human leader referral surface.
//
//  Surfaces when the Authority Alignment System detects that a conversation
//  topic exceeds AI scope and requires human pastoral wisdom. Use cases:
//    - Crisis escalation (crisisEscalation flag)
//    - Pastoral complexity (pastoralEscalation flag)
//    - Controversial doctrine (controversialDoctrine flag)
//    - Scrupulosity spiral risk (scrupulosityRisk flag)
//
//  This is NOT a replacement for pastoral care — it is a bridge to it.
//  The view's tone is warm, not alarming. The user should feel supported,
//  not redirected because Berean "failed."
//
//  Gated behind `authorityAlignmentEnabled`.
//
//  Non-negotiables:
//    - Crisis resources (988, etc.) are always shown for crisisEscalation
//    - AI cannot claim to have referred the user without user's explicit action
//    - Leader connection is always user-initiated — never automatic
//    - Privacy: the leader sees only a brief summary, not the conversation transcript
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Leadership Guidance View

struct LeadershipGuidanceView: View {
    let sensitivityFlags: [SensitivityFlag]
    let contextSummary: String
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LeadershipGuidanceViewModel()
    @State private var showConnectSheet = false

    private var isCrisis: Bool {
        sensitivityFlags.contains(.crisisEscalation)
    }

    private var primaryFlag: SensitivityFlag {
        // Priority order: crisis > pastoral > doctrine > scrupulosity > default
        for flag in [SensitivityFlag.crisisEscalation, .pastoralEscalation,
                     .controversialDoctrine, .scrupulosityRisk] {
            if sensitivityFlags.contains(flag) { return flag }
        }
        return sensitivityFlags.first ?? .pastoralEscalation
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    guidanceHeader

                    // Crisis resources (highest priority — always shown first)
                    if isCrisis {
                        crisisResourcesSection
                    }

                    // What Berean can/can't do
                    scopeCard

                    // Connected leaders
                    leaderConnectionSection

                    // Connect a new leader CTA
                    connectLeaderCTA

                    // Footer humility note
                    footerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle(isCrisis ? "You're Not Alone" : "Connect with a Leader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectLeaderSheet()
        }
        .task { await viewModel.loadConnectedLeaders() }
    }

    // MARK: - Header

    private var guidanceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isCrisis ? "heart.fill" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(isCrisis ? .red : .blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(AMENFont.bold(18))
                        .foregroundStyle(.primary)

                    Text(headerSubtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }

            Text(headerBody)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCrisis ? Color.red.opacity(0.06) : Color.blue.opacity(0.06))
        )
    }

    private var headerTitle: String {
        switch primaryFlag {
        case .crisisEscalation:         return "Please reach out to someone"
        case .pastoralEscalation:       return "A pastor can help here"
        case .controversialDoctrine:    return "This deserves a conversation"
        case .scrupulosityRisk:         return "God's grace is enough"
        default:                        return "Connect with a leader"
        }
    }

    private var headerSubtitle: String {
        switch primaryFlag {
        case .crisisEscalation:         return "You don't have to go through this alone"
        case .pastoralEscalation:       return "Some questions need human wisdom"
        case .controversialDoctrine:    return "Traditions differ — a pastor can guide you"
        case .scrupulosityRisk:         return "Anxiety about getting it right is normal"
        default:                        return "Berean can help you prepare to talk"
        }
    }

    private var headerBody: String {
        switch primaryFlag {
        case .crisisEscalation:
            return "I care about you. What you're going through matters. Berean is an AI tool — I can offer scripture and presence, but I can't be the human connection you may need right now."
        case .pastoralEscalation:
            return "This is a great question to bring to your pastor. They know you, your context, and your community in ways I simply can't. I'd love to help you prepare for that conversation."
        case .controversialDoctrine:
            return "Different Christian traditions interpret this differently, and both interpretations have serious biblical scholars behind them. Your pastor can help you navigate this within your community's context."
        case .scrupulosityRisk:
            return "I want to gently note that we've been circling this question a few times. That pattern sometimes reflects anxiety rather than genuine theological need. A pastor or Christian counselor can be a wonderful support here."
        default:
            return "Your pastor or a trusted spiritual mentor can offer wisdom that goes beyond what I'm able to provide. I'm here to help you think and prepare."
        }
    }

    // MARK: - Crisis Resources

    private var crisisResourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Immediate Support")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            LeadershipCrisisRow(
                icon: "phone.fill",
                title: "988 Suicide & Crisis Lifeline",
                subtitle: "Call or text 988 (US) — available 24/7",
                accentColor: .red
            )

            LeadershipCrisisRow(
                icon: "message.fill",
                title: "Crisis Text Line",
                subtitle: "Text HOME to 741741 (US/UK/CA)",
                accentColor: .red
            )

            LeadershipCrisisRow(
                icon: "person.2.fill",
                title: "Your pastor or a trusted adult",
                subtitle: "Reach out to someone you trust today",
                accentColor: .blue
            )
        }
    }

    // MARK: - Scope Card

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Berean can & can't do")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ScopeRow(can: true,  text: "Explore scripture alongside you")
                ScopeRow(can: true,  text: "Help you prepare questions for your pastor")
                ScopeRow(can: true,  text: "Share multiple perspectives with humility")
                ScopeRow(can: false, text: "Know your full situation and story")
                ScopeRow(can: false, text: "Provide pastoral care or counseling")
                ScopeRow(can: false, text: "Replace human wisdom and relationship")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    // MARK: - Leader Connection Section

    @ViewBuilder
    private var leaderConnectionSection: some View {
        if !viewModel.connectedLeaders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your Connected Leaders")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                Text("These leaders have agreed to support you. They can see a brief summary if you choose to share.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)

                ForEach(viewModel.connectedLeaders) { leader in
                    LeaderConnectionRow(leader: leader)
                }
            }
        }
    }

    // MARK: - Connect Leader CTA

    private var connectLeaderCTA: some View {
        Button {
            showConnectSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect a pastor or mentor")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)

                    Text("Give them optional access to your discipleship journey")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Berean does not automatically share your conversations. Any sharing with a connected leader requires your explicit approval.")
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }
}

// MARK: - Crisis Resource Row

private struct LeadershipCrisisRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accentColor.opacity(0.06))
        )
    }
}

// MARK: - Scope Row

private struct ScopeRow: View {
    let can: Bool
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: can ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(can ? .green : Color.secondary.opacity(0.5))

            Text(text)
                .font(AMENFont.regular(13))
                .foregroundStyle(can ? .primary : .secondary)
        }
    }
}

// MARK: - Leader Connection Row

private struct LeaderConnectionRow: View {
    let leader: LeaderConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                Text(leader.leaderDisplayName)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                if let role = leader.leaderRole {
                    Text(role)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Text(leader.profileSharingEnabled ? "Profile sharing: On" : "Profile sharing: Off")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(leader.profileSharingEnabled ? .green : .secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

// MARK: - Connect Leader Sheet

private struct ConnectLeaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var leaderUsername = ""
    @State private var leaderRole = ""
    @State private var shareProfile = false
    @State private var isSending = false
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pastor or mentor's AMEN username", text: $leaderUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Their role (e.g. Pastor, Mentor)", text: $leaderRole)
                } header: {
                    Text("Leader details")
                } footer: {
                    Text("They'll receive a connection request and can choose to accept or decline.")
                }

                Section {
                    Toggle("Share my discipleship journey", isOn: $shareProfile)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("If enabled, your connected leader can see your focus areas and recent study activity — not your private conversations.")
                }

                if didSend {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connection request sent.")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("Connect a Leader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Request") {
                        sendRequest()
                    }
                    .disabled(leaderUsername.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
            }
        }
    }

    private func sendRequest() {
        isSending = true
        // TODO: Call Cloud Function `createLeaderConnection`
        // For now, simulate a success after 1s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSending = false
            didSend = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
private final class LeadershipGuidanceViewModel: ObservableObject {
    @Published var connectedLeaders: [LeaderConnection] = []
    @Published var isLoading = false

    private lazy var db = Firestore.firestore()

    func loadConnectedLeaders() async {
        guard AMENFeatureFlags.shared.authorityAlignmentEnabled,
              let uid = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("leaderConnections")
                .whereField("consentGranted", isEqualTo: true)
                .getDocuments()

            connectedLeaders = snap.documents.compactMap { doc -> LeaderConnection? in
                let data = doc.data()
                guard let leaderUserId = data["leaderUserId"] as? String,
                      let displayName = data["leaderDisplayName"] as? String,
                      let ts = data["connectedAt"] as? Timestamp else { return nil }
                return LeaderConnection(
                    id: doc.documentID,
                    userId: uid,
                    leaderUserId: leaderUserId,
                    leaderDisplayName: displayName,
                    leaderRole: data["leaderRole"] as? String,
                    consentGranted: data["consentGranted"] as? Bool ?? false,
                    profileSharingEnabled: data["profileSharingEnabled"] as? Bool ?? false,
                    connectedAt: ts.dateValue(),
                    revokedAt: nil
                )
            }
        } catch {
            dlog("[LeadershipGuidance] Failed to load leaders: \(error.localizedDescription)")
        }
    }
}
