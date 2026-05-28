// AmenVerificationAdminView.swift
// AMENAPP — Verification & Trust System
//
// Admin review interface for verification requests.
// Entry is guarded by Firebase custom claim `admin: true`.
// Admin actions route to backend callables — the UI NEVER performs
// direct Firestore writes that could bypass server-side validation.
//
// IMPORTANT: Admin should NOT see raw ID images. Only provider reference IDs
// are shown; full document review must happen in the provider's secure dashboard.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenVerificationAdminView

struct AmenVerificationAdminView: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var viewModel = AdminVerificationViewModel()
    @State private var selectedRequest: AdminVerificationRow? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.authState {
                case .checking:
                    checkingAuthView
                case .notAdmin:
                    notAuthorizedView
                case .admin:
                    adminContent
                }
            }
            .navigationTitle("Verification Admin")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.checkAdminClaim() }
        }
    }

    // MARK: Auth States

    private var checkingAuthView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Checking authorization…")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Checking authorization")
    }

    private var notAuthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Not Authorized")
                .font(.custom("OpenSans-SemiBold", size: 20))
            Text("You do not have admin access to this section.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityLabel("Not authorized. You do not have admin access.")
    }

    // MARK: Admin Content

    private var adminContent: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if viewModel.requests.isEmpty {
                Text("No pending verification requests.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.requests) { row in
                    AdminRequestRow(row: row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .onTapGesture { selectedRequest = row }
                        .accessibilityLabel(rowAccessibilityLabel(row))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double-tap to review this request")
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.loadRequests() }
        .task { await viewModel.loadRequests() }
        .sheet(item: $selectedRequest) { row in
            AdminRequestDetailView(row: row, viewModel: viewModel)
        }
    }

    private func rowAccessibilityLabel(_ row: AdminVerificationRow) -> String {
        "\(row.requestType) request from \(row.displayIdentifier), status: \(row.status), created \(row.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - AdminRequestRow

private struct AdminRequestRow: View {
    let row: AdminVerificationRow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: row.requestType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(row.requestType.color)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(row.requestType.color.opacity(0.12))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.displayIdentifier)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .lineLimit(1)

                    Text(row.requestType.displayName)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    AdminStatusPill(status: row.status)

                    if let risk = row.riskLevel {
                        AdminRiskBadge(level: risk)
                    }

                    Spacer()

                    Text(row.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }
}

// MARK: - AdminStatusPill

private struct AdminStatusPill: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "pending":    return .orange
        case "approved":   return .green
        case "rejected":   return .red
        case "revoked":    return .red
        case "expired":    return Color(.systemGray)
        default:           return Color(.systemGray)
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.custom("OpenSans-SemiBold", size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - AdminRiskBadge

private struct AdminRiskBadge: View {
    let level: AdminVerificationRow.RiskLevel

    private var color: Color {
        switch level {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        Text(level.displayName)
            .font(.custom("OpenSans-SemiBold", size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .accessibilityLabel("Risk level: \(level.displayName)")
    }
}

// MARK: - AdminRequestDetailView

struct AdminRequestDetailView: View {
    let row: AdminVerificationRow
    @ObservedObject var viewModel: AdminVerificationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var isActioning = false
    @State private var actionError: String? = nil
    @State private var actionConfirmation: AdminAction? = nil

    enum AdminAction: Identifiable {
        case approve, reject, requestMoreInfo, revoke
        var id: String { "\(self)" }

        var title: String {
            switch self {
            case .approve:         return "Approve"
            case .reject:          return "Reject"
            case .requestMoreInfo: return "Request More Info"
            case .revoke:          return "Revoke"
            }
        }

        var confirmMessage: String {
            switch self {
            case .approve:         return "Approve this verification request?"
            case .reject:          return "Reject this verification request?"
            case .requestMoreInfo: return "Send a request for more information?"
            case .revoke:          return "Revoke this verification? This cannot be undone."
            }
        }

        var isDestructive: Bool { self == .reject || self == .revoke }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    detailHeader

                    Divider()

                    // Request details
                    requestDetailsSection

                    Divider()

                    // History
                    historySection

                    Divider()

                    // Reason field
                    reasonField

                    // Action buttons
                    actionButtons

                    if let error = actionError {
                        Text(error)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.red)
                    }

                    // ID document note
                    idDocumentNote
                }
                .padding(20)
            }
            .navigationTitle("Review Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                actionConfirmation?.confirmMessage ?? "",
                isPresented: Binding(
                    get: { actionConfirmation != nil },
                    set: { if !$0 { actionConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = actionConfirmation {
                    Button(
                        action.title,
                        role: action.isDestructive ? .destructive : nil
                    ) {
                        executeAction(action)
                    }
                    Button("Cancel", role: .cancel) { actionConfirmation = nil }
                }
            }
        }
    }

    // MARK: Detail Sections

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: row.requestType.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(row.requestType.color)
                .frame(width: 48, height: 48)
                .background(Circle().fill(row.requestType.color.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.requestType.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 18))

                AdminStatusPill(status: row.status)
            }
        }
    }

    private var requestDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request Details")
                .font(.custom("OpenSans-SemiBold", size: 15))

            detailRow(label: "User UID", value: row.truncatedUID)
            detailRow(label: "Request Type", value: row.requestType.displayName)

            if let risk = row.riskLevel {
                HStack {
                    Text("Risk Level")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    AdminRiskBadge(level: risk)
                }
            }

            detailRow(label: "Submitted", value: row.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let expiry = row.expiresAt {
                detailRow(label: "Expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
            }

            if let method = row.verificationMethod {
                detailRow(label: "Verification Method", value: method)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.custom("OpenSans-SemiBold", size: 15))

            detailRow(label: "Prior Requests", value: "\(row.priorRequestCount)")

            if row.impersonationReportCount > 0 {
                HStack {
                    Text("Impersonation Reports")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(row.impersonationReportCount)")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.red)
                }
            } else {
                detailRow(label: "Impersonation Reports", value: "None")
            }
        }
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reason (required)")
                .font(.custom("OpenSans-SemiBold", size: 14))

            Text("This reason will be logged in the audit trail and, for rejections, a safe version may be shown to the user.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)

            TextEditor(text: $reason)
                .font(.custom("OpenSans-Regular", size: 14))
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6))
                )
                .accessibilityLabel("Action reason (required)")
        }
    }

    private var actionButtons: some View {
        let canAct = !reason.trimmingCharacters(in: .whitespaces).isEmpty && !isActioning

        return VStack(spacing: 10) {
            // Only role verifications can be approved/revoked directly from the UI.
            // Identity/creator/org require the external admin dashboard.
            if row.requestType == .role {
                HStack(spacing: 10) {
                    actionButton(
                        title: "Approve",
                        icon: "checkmark.circle.fill",
                        color: .green,
                        enabled: canAct
                    ) { actionConfirmation = .approve }

                    actionButton(
                        title: "Reject",
                        icon: "xmark.circle.fill",
                        color: .red,
                        enabled: canAct
                    ) { actionConfirmation = .reject }
                }

                HStack(spacing: 10) {
                    actionButton(
                        title: "Request Info",
                        icon: "questionmark.circle.fill",
                        color: .blue,
                        enabled: canAct
                    ) { actionConfirmation = .requestMoreInfo }

                    actionButton(
                        title: "Revoke",
                        icon: "minus.circle.fill",
                        color: .orange,
                        enabled: canAct
                    ) { actionConfirmation = .revoke }
                }
            } else {
                // Non-role verifications require the external dashboard
                externalDashboardNote
            }
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(enabled ? .white : Color(.systemGray3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(enabled ? color : Color(.systemGray5))
                )
        }
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var externalDashboardNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Review in Admin Dashboard")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                Text("Identity, organization, and creator verifications must be reviewed and actioned through the Amen admin dashboard. This prevents client-side bypasses.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08))
        )
    }

    private var idDocumentNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("ID documents are not visible here. Full document review is available only in the secure identity provider dashboard. Provider reference ID: \(row.providerReferenceId ?? "N/A")")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6))
        )
        .accessibilityLabel("ID documents are not shown here for security reasons.")
    }

    // MARK: Helpers

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func executeAction(_ action: AdminAction) {
        isActioning = true
        actionError = nil
        actionConfirmation = nil

        Task {
            do {
                let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
                switch action {
                case .approve:
                    try await viewModel.approveRoleVerification(requestId: row.id, reason: trimmedReason)
                case .reject:
                    try await viewModel.rejectRoleVerification(requestId: row.id, reason: trimmedReason)
                case .revoke:
                    try await viewModel.revokeRoleVerification(requestId: row.id, reason: trimmedReason)
                case .requestMoreInfo:
                    try await viewModel.requestMoreInfo(requestId: row.id, reason: trimmedReason)
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    isActioning = false
                }
            }
        }
    }
}

// MARK: - AdminVerificationRow (display model)

struct AdminVerificationRow: Identifiable {
    let id: String
    let uid: String
    let displayName: String?
    let requestType: RequestType
    let status: String
    let createdAt: Date
    let expiresAt: Date?
    let riskLevel: RiskLevel?
    let verificationMethod: String?
    let priorRequestCount: Int
    let impersonationReportCount: Int
    let providerReferenceId: String?

    var displayIdentifier: String {
        if let name = displayName, !name.isEmpty { return name }
        return truncatedUID
    }

    var truncatedUID: String {
        guard uid.count > 8 else { return uid }
        return String(uid.prefix(8)) + "…"
    }

    enum RequestType: String {
        case identity
        case organization
        case role
        case creator
        case email
        case phone

        var displayName: String {
            switch self {
            case .identity:     return "Identity"
            case .organization: return "Organization"
            case .role:         return "Role"
            case .creator:      return "Creator"
            case .email:        return "Email"
            case .phone:        return "Phone"
            }
        }

        var icon: String {
            switch self {
            case .identity:     return "person.text.rectangle.fill"
            case .organization: return "building.2.crop.circle.fill"
            case .role:         return "person.badge.shield.checkmark.fill"
            case .creator:      return "star.bubble.fill"
            case .email:        return "envelope.badge.shield.half.filled"
            case .phone:        return "iphone.badge.play"
            }
        }

        var color: Color {
            switch self {
            case .identity:     return .indigo
            case .organization: return .blue
            case .role:         return .green
            case .creator:      return .orange
            case .email:        return Color(.systemGray)
            case .phone:        return Color(.systemGray)
            }
        }
    }

    enum RiskLevel {
        case low, medium, high, critical

        var displayName: String {
            switch self {
            case .low:      return "Low"
            case .medium:   return "Medium"
            case .high:     return "High"
            case .critical: return "Critical"
            }
        }
    }
}

// MARK: - AdminVerificationViewModel

@MainActor
final class AdminVerificationViewModel: ObservableObject {

    enum AuthState { case checking, notAdmin, admin }

    @Published private(set) var authState: AuthState = .checking
    @Published private(set) var requests: [AdminVerificationRow] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()

    // MARK: Auth

    func checkAdminClaim() async {
        guard let user = Auth.auth().currentUser else {
            authState = .notAdmin
            return
        }
        do {
            let result = try await user.getIDTokenResult(forcingRefresh: false)
            let isAdmin = (result.claims["admin"] as? Bool) == true
            authState = isAdmin ? .admin : .notAdmin
        } catch {
            authState = .notAdmin
        }
    }

    // MARK: Data Loading

    func loadRequests() async {
        guard authState == .admin else { return }
        isLoading = true
        do {
            let snapshot = try await db
                .collection("verificationAuditLogs")
                .whereField("status", isEqualTo: "pending")
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            requests = snapshot.documents.compactMap { doc in
                AdminVerificationRow(from: doc)
            }
        } catch {
            // Swallow — caller can retry via pull-to-refresh
        }
        isLoading = false
    }

    // MARK: Admin Actions (role verification only — backend callables)

    func approveRoleVerification(requestId: String, reason: String) async throws {
        try await callAdminFunction(
            name: "approveRoleVerification",
            requestId: requestId,
            reason: reason
        )
        await loadRequests()
    }

    func rejectRoleVerification(requestId: String, reason: String) async throws {
        try await callAdminFunction(
            name: "revokeRoleVerification",
            requestId: requestId,
            reason: reason,
            additionalParams: ["action": "reject"]
        )
        await loadRequests()
    }

    func revokeRoleVerification(requestId: String, reason: String) async throws {
        try await callAdminFunction(
            name: "revokeRoleVerification",
            requestId: requestId,
            reason: reason,
            additionalParams: ["action": "revoke"]
        )
        await loadRequests()
    }

    func requestMoreInfo(requestId: String, reason: String) async throws {
        try await callAdminFunction(
            name: "requestVerificationInfo",
            requestId: requestId,
            reason: reason
        )
        await loadRequests()
    }

    // MARK: Firebase Callable Helper

    private func callAdminFunction(
        name: String,
        requestId: String,
        reason: String,
        additionalParams: [String: Any] = [:]
    ) async throws {
        // Uses the FirebaseFunctions SDK via AmenVerificationService callable bridge.
        // Keeping import surface minimal — AmenVerificationService owns the Functions instance.
        var params: [String: Any] = [
            "requestId": requestId,
            "reason": reason,
        ]
        for (key, value) in additionalParams {
            params[key] = value
        }
        try await AmenVerificationService.shared.callAdminFunction(name: name, params: params)
    }
}

// MARK: - AdminVerificationRow Firestore Init

private extension AdminVerificationRow {
    init?(from document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let uid = data["uid"] as? String,
              let typeRaw = data["requestType"] as? String,
              let status = data["status"] as? String,
              let createdTimestamp = data["createdAt"] as? Timestamp
        else { return nil }

        self.id = document.documentID
        self.uid = uid
        self.displayName = data["displayName"] as? String
        self.requestType = RequestType(rawValue: typeRaw) ?? .identity
        self.status = status
        self.createdAt = createdTimestamp.dateValue()
        self.expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()
        self.verificationMethod = data["verificationMethod"] as? String
        self.priorRequestCount = data["priorRequestCount"] as? Int ?? 0
        self.impersonationReportCount = data["impersonationReportCount"] as? Int ?? 0
        self.providerReferenceId = data["providerReferenceId"] as? String

        if let riskRaw = data["riskLevel"] as? String {
            switch riskRaw {
            case "low":      self.riskLevel = .low
            case "medium":   self.riskLevel = .medium
            case "high":     self.riskLevel = .high
            case "critical": self.riskLevel = .critical
            default:         self.riskLevel = nil
            }
        } else {
            self.riskLevel = nil
        }
    }
}
