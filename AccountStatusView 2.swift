//
//  AccountStatusView.swift
//  AMENAPP
//
//  Shows account standing, enforcement actions, and lets users submit appeals.
//  Reads from users/{uid}/moderation subcollection (enforcement actions).
//  Appeals are written to moderationAppeals/{appealId}.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct ModerationHistoryAction: Identifiable {
    let id: String
    let type: String          // "content_removed" | "warning" | "strike" | "restriction"
    let reason: String
    let contentPreview: String?
    let createdAt: Date
    let status: String        // "active" | "expired" | "appealed" | "resolved"
    let expiresAt: Date?
    var appealStatus: String? // nil | "pending" | "accepted" | "rejected"
}

enum AccountStanding {
    case goodStanding
    case warning(count: Int)
    case restricted(until: Date?)
    case suspended

    var label: String {
        switch self {
        case .goodStanding:       return "Good Standing"
        case .warning(let n):     return n == 1 ? "Warning Issued" : "\(n) Warnings"
        case .restricted:         return "Restricted"
        case .suspended:          return "Suspended"
        }
    }

    var icon: String {
        switch self {
        case .goodStanding:   return "checkmark.shield.fill"
        case .warning:        return "exclamationmark.triangle.fill"
        case .restricted:     return "hand.raised.fill"
        case .suspended:      return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .goodStanding:   return .green
        case .warning:        return .orange
        case .restricted:     return .red
        case .suspended:      return Color(.systemGray)
        }
    }
}

// MARK: - AccountStatusView

struct AccountStatusView: View {
    @State private var standing: AccountStanding = .goodStanding
    @State private var actions: [ModerationHistoryAction] = []
    @State private var isLoading = true
    @State private var selectedAction: ModerationHistoryAction?
    @State private var showAppealSheet = false

    private let db = Firestore.firestore()

    var body: some View {
        List {
            // Standing summary
            Section {
                HStack(spacing: 16) {
                    Image(systemName: standing.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(standing.color)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(standing.label)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(standing.color)
                        Text(standingDescription)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("ACCOUNT STANDING")
                    .font(.custom("OpenSans-Bold", size: 12))
            }

            // Enforcement actions
            if !actions.isEmpty {
                Section {
                    ForEach(actions) { action in
                        actionRow(action)
                    }
                } header: {
                    Text("ENFORCEMENT HISTORY")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Actions expire automatically. You may request a review for any active action.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
            } else if !isLoading {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.green)
                            Text("No enforcement actions")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Text("Your account has a clean history")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                }
            }

            // Info section
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text("AMEN reviews all appeals within 48 hours. Our Community Guidelines exist to keep this space safe and uplifting for everyone.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Account Status")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView().scaleEffect(1.2)
            }
        }
        .task { await loadStatus() }
        .sheet(isPresented: $showAppealSheet) {
            if let action = selectedAction {
                AppealSubmissionSheet(action: action) {
                    // Refresh after appeal submitted
                    Task { await loadStatus() }
                }
            }
        }
    }

    // MARK: - Action Row

    private func actionRow(_ action: ModerationHistoryAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForAction(action.type))
                    .foregroundStyle(colorForStatus(action.status))
                    .font(.system(size: 14))

                Text(labelForAction(action.type))
                    .font(.custom("OpenSans-SemiBold", size: 14))

                Spacer()

                Text(action.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(action.reason)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)

            if let preview = action.contentPreview, !preview.isEmpty {
                Text("\"\(preview)\"")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                // Status badge
                appealBadge(action.appealStatus)

                Spacer()

                // Appeal button — only for active actions with no pending appeal
                if action.status == "active" && action.appealStatus == nil {
                    Button {
                        selectedAction = action
                        showAppealSheet = true
                    } label: {
                        Text("Request Review")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func appealBadge(_ status: String?) -> some View {
        if let status {
            let (label, color): (String, Color) = switch status {
            case "pending":  ("Review Pending", .orange)
            case "accepted": ("Resolved", .green)
            case "rejected": ("Not Overturned", Color(.systemGray))
            default:         ("Unknown", Color(.systemGray))
            }
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
        }
    }

    // MARK: - Helpers

    private var standingDescription: String {
        switch standing {
        case .goodStanding:
            return "Your account is in full compliance with AMEN's Community Guidelines."
        case .warning(let n):
            return "You have \(n) active warning\(n > 1 ? "s" : "") on your account. Continued violations may lead to restrictions."
        case .restricted(let until):
            if let date = until {
                return "Some features are temporarily limited until \(date.formatted(date: .long, time: .omitted))."
            }
            return "Some account features are temporarily limited."
        case .suspended:
            return "Your account is suspended. Please contact support for more information."
        }
    }

    private func iconForAction(_ type: String) -> String {
        switch type {
        case "content_removed": return "trash.fill"
        case "warning":         return "exclamationmark.triangle.fill"
        case "strike":          return "xmark.circle.fill"
        case "restriction":     return "hand.raised.fill"
        default:                return "info.circle.fill"
        }
    }

    private func labelForAction(_ type: String) -> String {
        switch type {
        case "content_removed": return "Content Removed"
        case "warning":         return "Warning"
        case "strike":          return "Strike"
        case "restriction":     return "Restriction Applied"
        default:                return "Enforcement Action"
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "active":   return .orange
        case "expired":  return Color(.systemGray)
        case "resolved": return .green
        default:         return Color(.systemGray)
        }
    }

    // MARK: - Load

    private func loadStatus() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        do {
            // Load enforcement actions from subcollection
            let snap = try await db.collection("users").document(uid)
                .collection("moderation")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            var loaded: [ModerationHistoryAction] = []
            for doc in snap.documents {
                let d = doc.data()
                let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let expiresAt = (d["expiresAt"] as? Timestamp)?.dateValue()
                let action = ModerationHistoryAction(
                    id: doc.documentID,
                    type: d["type"] as? String ?? "warning",
                    reason: d["reason"] as? String ?? "Community Guidelines violation",
                    contentPreview: d["contentPreview"] as? String,
                    createdAt: createdAt,
                    status: d["status"] as? String ?? "active",
                    expiresAt: expiresAt,
                    appealStatus: d["appealStatus"] as? String
                )
                loaded.append(action)
            }

            // Derive standing from active actions
            let activeActions = loaded.filter { $0.status == "active" }
            let strikes = activeActions.filter { $0.type == "strike" }.count
            let warnings = activeActions.filter { $0.type == "warning" }.count
            let restriction = activeActions.first { $0.type == "restriction" }

            let derivedStanding: AccountStanding
            if strikes >= 3 {
                derivedStanding = .suspended
            } else if let r = restriction {
                derivedStanding = .restricted(until: r.expiresAt)
            } else if warnings > 0 || strikes > 0 {
                derivedStanding = .warning(count: warnings + strikes)
            } else {
                derivedStanding = .goodStanding
            }

            await MainActor.run {
                actions = loaded
                standing = derivedStanding
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - AppealSubmissionSheet

struct AppealSubmissionSheet: View {
    @Environment(\.dismiss) var dismiss
    let action: ModerationHistoryAction
    let onSubmitted: () -> Void

    @State private var appealText = ""
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 24)

                    Text("Request a Review")
                        .font(.custom("OpenSans-Bold", size: 22))

                    Text("Explain why you believe this action was made in error. Our moderation team will review your appeal within 48 hours.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Action summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("Action being reviewed:")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                    Text(labelForAction(action.type) + " — " + action.reason)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                // Appeal text
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your explanation")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(appealText.count)/500")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(appealText.count > 450 ? .orange : .secondary)
                    }

                    TextEditor(text: $appealText)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: appealText) { _, new in
                            if new.count > 500 { appealText = String(new.prefix(500)) }
                        }
                }
                .padding(.horizontal)

                if let err = errorMessage {
                    Text(err)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await submitAppeal() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Submit Appeal")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray : Color.blue,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .disabled(appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Appeal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Appeal Submitted", isPresented: $showConfirmation) {
                Button("OK") {
                    onSubmitted()
                    dismiss()
                }
            } message: {
                Text("We'll review your appeal and notify you within 48 hours.")
            }
        }
    }

    private func submitAppeal() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSubmitting = true

        do {
            let appealId = UUID().uuidString
            try await db.collection("moderationAppeals").document(appealId).setData([
                "userId": uid,
                "actionId": action.id,
                "actionType": action.type,
                "reason": appealText.trimmingCharacters(in: .whitespacesAndNewlines),
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp()
            ])

            // Mark action as appealed in the moderation subcollection
            try await db.collection("users").document(uid)
                .collection("moderation").document(action.id)
                .updateData(["appealStatus": "pending"])

            await MainActor.run {
                isSubmitting = false
                showConfirmation = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to submit appeal. Please try again."
                isSubmitting = false
            }
        }
    }

    private func labelForAction(_ type: String) -> String {
        switch type {
        case "content_removed": return "Content Removed"
        case "warning":         return "Warning"
        case "strike":          return "Strike"
        case "restriction":     return "Restriction Applied"
        default:                return "Enforcement Action"
        }
    }
}
