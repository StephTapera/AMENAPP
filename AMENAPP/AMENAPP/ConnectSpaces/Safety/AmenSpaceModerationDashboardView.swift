// AmenSpaceModerationDashboardView.swift
// AMEN Connect + Spaces — Host / Moderator Dashboard
// Built 2026-06-02

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - Local stub types

struct AmenReportItem: Identifiable {
    let id: String
    var reportedBy: String
    var reason: String
    var contentPreview: String
    var reportedAt: Date
}

struct AmenJoinRequest: Identifiable {
    let id: String
    var userId: String
    var displayName: String
    var requestedAt: Date
}

struct AmenSpaceMember: Identifiable {
    let id: String
    var displayName: String
    var joinedAt: Date
    var role: MemberRole

    enum MemberRole: String {
        case member, mod, host
        var displayText: String { rawValue.capitalized }
        var badgeColor: Color {
            switch self {
            case .host:   return Color(hex: "D9A441")
            case .mod:    return Color(hex: "6E4BB5")
            case .member: return Color.white.opacity(0.35)
            }
        }
    }
}

// MARK: - Tab

private enum DashboardTab: String, CaseIterable {
    case reports = "Reports"
    case joinRequests = "Join Requests"
    case members = "Members"
}

// MARK: - Moderation action sheet

private struct AmenModerationActionSheet: View {
    let targetUserId: String
    let spaceId: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @State private var selectedAction: AmenModerationActionType = .mute
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?

    private let functions = Functions.functions()

    private let availableActions: [AmenModerationActionType] = [
        .mute, .unmute, .block, .removePost, .removeModRole, .reportToReviewQueue
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    Picker("Action Type", selection: $selectedAction) {
                        ForEach(availableActions, id: \.self) { action in
                            Text(action.displayText).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Reason") {
                    TextField("Describe the reason…", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Reason for moderation action")
                }

                if let error = submitError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Moderation Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitAction()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    .accessibilityLabel("Submit moderation action")
                }
            }
            .overlay {
                if isSubmitting {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Submitting…")
                        .tint(Color(hex: "6E4BB5"))
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func submitAction() {
        let cleanReason = reason.trimmingCharacters(in: .whitespaces)
        guard !cleanReason.isEmpty else { return }
        isSubmitting = true
        submitError = nil
        Task {
            defer { isSubmitting = false }
            do {
                guard let performedBy = Auth.auth().currentUser?.uid else {
                    submitError = "You must be signed in."
                    return
                }
                let callable = functions.httpsCallable(AmenSpacesPhase1Callable.submitModerationAction.rawValue)
                _ = try await callable.call([
                    "targetUserId": targetUserId,
                    "spaceId": spaceId,
                    "actionType": selectedAction.rawValue,
                    "reason": cleanReason,
                    "performedBy": performedBy
                ])
                onSubmit()
            } catch {
                submitError = error.localizedDescription
            }
        }
    }
}

private extension AmenModerationActionType {
    var displayText: String {
        switch self {
        case .mute:              return "Mute"
        case .unmute:            return "Unmute"
        case .block:             return "Block"
        case .removePost:        return "Remove Post"
        case .approveJoin:       return "Approve Join"
        case .denyJoin:          return "Deny Join"
        case .assignModRole:     return "Assign Mod Role"
        case .removeModRole:     return "Remove Mod Role"
        case .reportToReviewQueue: return "Report to Review Queue"
        }
    }
}

// MARK: - Reports tab

private struct ReportsTabView: View {
    let spaceId: String
    let isHost: Bool
    let reports: [AmenReportItem]
    let isLoading: Bool

    @State private var selectedReport: AmenReportItem?
    @State private var showActionSheet: Bool = false

    var body: some View {
        Group {
            if isLoading {
                loadingView()
            } else if reports.isEmpty {
                emptyView(icon: "flag.slash", message: "No reports at this time.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(reports) { report in
                            reportRow(report)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showActionSheet) {
            if let report = selectedReport {
                AmenModerationActionSheet(
                    targetUserId: report.reportedBy,
                    spaceId: spaceId,
                    onSubmit: {
                        showActionSheet = false
                        selectedReport = nil
                    },
                    onCancel: {
                        showActionSheet = false
                        selectedReport = nil
                    }
                )
            }
        }
    }

    private func reportRow(_ report: AmenReportItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.reason)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Reported by \(report.reportedBy.prefix(12))")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.reportedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
            }

            Text(report.contentPreview)
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if isHost {
                Button {
                    selectedReport = report
                    showActionSheet = true
                } label: {
                    Text("Review")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(hex: "6E4BB5"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: "6E4BB5").opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color(hex: "6E4BB5").opacity(0.3), lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review report from \(report.reportedBy.prefix(12))")
            }
        }
        .padding(14)
        .background(Color(hex: "0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Report: \(report.reason) from \(report.reportedBy.prefix(12))")
    }
}

// MARK: - Join Requests tab

private struct JoinRequestsTabView: View {
    let spaceId: String
    let requests: [AmenJoinRequest]
    let isLoading: Bool
    let onDecision: () -> Void

    @State private var processingIds: Set<String> = []
    @State private var decisionErrors: [String: String] = [:]

    private let functions = Functions.functions()

    var body: some View {
        Group {
            if isLoading {
                loadingView()
            } else if requests.isEmpty {
                emptyView(icon: "person.badge.clock", message: "No pending join requests.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(requests) { request in
                            joinRequestRow(request)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func joinRequestRow(_ request: AmenJoinRequest) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: "245B8F"))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(request.displayName.prefix(1)).uppercased())
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.displayName)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(request.requestedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.systemScaled(11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if processingIds.contains(request.id) {
                ProgressView()
                    .tint(Color(hex: "6E4BB5"))
            } else {
                HStack(spacing: 8) {
                    actionButton(
                        label: "Approve",
                        color: Color(hex: "D9A441"),
                        action: { process(request: request, approve: true) }
                    )
                    actionButton(
                        label: "Deny",
                        color: Color.white.opacity(0.3),
                        action: { process(request: request, approve: false) }
                    )
                }
            }
        }
        .padding(14)
        .background(Color(hex: "0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if let error = decisionErrors[request.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Join request from \(request.displayName)")
    }

    private func actionButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(color.opacity(0.4), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func process(request: AmenJoinRequest, approve: Bool) {
        processingIds.insert(request.id)
        decisionErrors.removeValue(forKey: request.id)
        Task {
            defer { processingIds.remove(request.id) }
            do {
                let callable = functions.httpsCallable(AmenSpacesPhase1Callable.reviewJoinRequest.rawValue)
                _ = try await callable.call([
                    "requestId": request.id,
                    "spaceId": spaceId,
                    "userId": request.userId,
                    "approved": approve
                ])
                onDecision()
            } catch {
                decisionErrors[request.id] = error.localizedDescription
            }
        }
    }
}

// MARK: - Members tab

private struct MembersTabView: View {
    let spaceId: String
    let isHost: Bool
    let members: [AmenSpaceMember]
    let isLoading: Bool

    @State private var searchText: String = ""
    @State private var selectedMember: AmenSpaceMember?
    @State private var showActionSheet: Bool = false

    private var filteredMembers: [AmenSpaceMember] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return members }
        return members.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .accessibilityHidden(true)
                TextField("Search members…", text: $searchText)
                    .font(.systemScaled(14))
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search members")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.12)

            Group {
                if isLoading {
                    loadingView()
                } else if filteredMembers.isEmpty {
                    emptyView(icon: "person.2.slash", message: searchText.isEmpty ? "No members yet." : "No members match your search.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredMembers) { member in
                                memberRow(member)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .sheet(isPresented: $showActionSheet) {
            if let member = selectedMember {
                AmenModerationActionSheet(
                    targetUserId: member.id,
                    spaceId: spaceId,
                    onSubmit: {
                        showActionSheet = false
                        selectedMember = nil
                    },
                    onCancel: {
                        showActionSheet = false
                        selectedMember = nil
                    }
                )
            }
        }
    }

    private func memberRow(_ member: AmenSpaceMember) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: "6E4BB5").opacity(0.7))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.systemScaled(14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Joined \(member.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.systemScaled(10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Role badge
            Text(member.role.displayText)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(member.role.badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(member.role.badgeColor.opacity(0.1))
                        .overlay { Capsule().strokeBorder(member.role.badgeColor.opacity(0.35), lineWidth: 1) }
                }
                .accessibilityLabel("Role: \(member.role.displayText)")

            if isHost && member.role != .host {
                Menu {
                    Button("Mute") {
                        selectedMember = member
                        showActionSheet = true
                    }
                    Button("Remove", role: .destructive) {
                        selectedMember = member
                        showActionSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.systemScaled(16))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Member options for \(member.displayName)")
            }
        }
        .padding(12)
        .background(Color(hex: "0D0D0D"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(member.displayName), \(member.role.displayText)")
    }
}

// MARK: - Shared sub-views

@ViewBuilder
private func loadingView() -> some View {
    VStack(spacing: 14) {
        ProgressView()
            .tint(Color(hex: "6E4BB5"))
        Text("Loading…")
            .font(.systemScaled(13))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel("Loading")
}

private func emptyView(icon: String, message: String) -> some View {
    VStack(spacing: 14) {
        Image(systemName: icon)
            .font(.systemScaled(36))
            .foregroundStyle(Color.white.opacity(0.2))
            .accessibilityHidden(true)
        Text(message)
            .font(.systemScaled(14))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel(message)
}

// MARK: - ViewModel

@MainActor
private final class AmenSpaceModerationDashboardViewModel: ObservableObject {
    @Published var reports: [AmenReportItem] = []
    @Published var joinRequests: [AmenJoinRequest] = []
    @Published var members: [AmenSpaceMember] = []
    @Published var isLoadingReports: Bool = false
    @Published var isLoadingJoinRequests: Bool = false
    @Published var isLoadingMembers: Bool = false
    @Published var loadError: String?

    let spaceId: String
    private let functions = Functions.functions()

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func loadAll() {
        loadReports()
        loadJoinRequests()
        loadMembers()
    }

    func loadReports() {
        isLoadingReports = true
        Task {
            defer { isLoadingReports = false }
            // Stub: production would query Firestore reports subcollection
            try? await Task.sleep(nanoseconds: 500_000_000)
            reports = []
        }
    }

    func loadJoinRequests() {
        isLoadingJoinRequests = true
        Task {
            defer { isLoadingJoinRequests = false }
            try? await Task.sleep(nanoseconds: 400_000_000)
            joinRequests = []
        }
    }

    func loadMembers() {
        isLoadingMembers = true
        Task {
            defer { isLoadingMembers = false }
            try? await Task.sleep(nanoseconds: 450_000_000)
            members = []
        }
    }
}

// MARK: - Main view

struct AmenSpaceModerationDashboardView: View {
    let spaceId: String
    let isHost: Bool

    @StateObject private var viewModel: AmenSpaceModerationDashboardViewModel
    @State private var selectedTab: DashboardTab = .reports

    init(spaceId: String, isHost: Bool) {
        self.spaceId = spaceId
        self.isHost = isHost
        _viewModel = StateObject(wrappedValue: AmenSpaceModerationDashboardViewModel(spaceId: spaceId))
    }

    var body: some View {
        VStack(spacing: 0) {
            glassTabSelector
            Divider().opacity(0.12)

            Group {
                switch selectedTab {
                case .reports:
                    ReportsTabView(
                        spaceId: spaceId,
                        isHost: isHost,
                        reports: viewModel.reports,
                        isLoading: viewModel.isLoadingReports
                    )
                case .joinRequests:
                    JoinRequestsTabView(
                        spaceId: spaceId,
                        requests: viewModel.joinRequests,
                        isLoading: viewModel.isLoadingJoinRequests,
                        onDecision: { viewModel.loadJoinRequests() }
                    )
                case .members:
                    MembersTabView(
                        spaceId: spaceId,
                        isHost: isHost,
                        members: viewModel.members,
                        isLoading: viewModel.isLoadingMembers
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "070607"))
        .task {
            viewModel.loadAll()
        }
    }

    // MARK: - Glass tab selector (chrome — glass per design rule)

    private var glassTabSelector: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.systemScaled(13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color(hex: "D9A441") : Color.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color(hex: "D9A441").opacity(0.12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color(hex: "D9A441").opacity(0.3), lineWidth: 1)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("Host view") {
    AmenSpaceModerationDashboardView(spaceId: "s1", isHost: true)
        .frame(height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Mod view") {
    AmenSpaceModerationDashboardView(spaceId: "s1", isHost: false)
        .frame(height: 600)
        .preferredColorScheme(.dark)
}
