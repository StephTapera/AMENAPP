// AmenAccessPassAdminConsoleView.swift
// AMENAPP — Admin Console for Access Pass Management
//
// Creator/admin can manage all passes for a given target surface.
// Shows pass cards, request inbox, audit summary, and creation entry point.

import SwiftUI

struct AmenAccessPassAdminConsoleView: View {
    let targetType: AmenAccessTargetType
    let targetId: String
    let targetTitle: String
    var orgId: String?
    var churchId: String?
    var spaceId: String?

    @StateObject private var viewModel: AmenAccessPassAdminViewModel
    @State private var showCreateSheet = false
    @State private var selectedPass: AmenAccessPassSummary?
    @State private var newPassResponse: AmenCreateAccessPassResponse?

    init(
        targetType: AmenAccessTargetType,
        targetId: String,
        targetTitle: String,
        orgId: String? = nil,
        churchId: String? = nil,
        spaceId: String? = nil
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.orgId = orgId
        self.churchId = churchId
        self.spaceId = spaceId
        _viewModel = StateObject(wrappedValue: AmenAccessPassAdminViewModel(
            targetType: targetType, targetId: targetId
        ))
    }

    var body: some View {
        List {
            // Summary header
            summarySection

            // Active passes
            if !viewModel.activePasses.isEmpty {
                passesSection(title: "Active", passes: viewModel.activePasses)
            }

            // Inactive passes
            if !viewModel.inactivePasses.isEmpty {
                passesSection(title: "Inactive", passes: viewModel.inactivePasses)
            }

            // Pending requests
            if !viewModel.pendingRequests.isEmpty {
                requestsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Access Passes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard AMENFeatureFlags.shared.accessPassAdminConsoleEnabled else { return }
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new access pass")
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showCreateSheet) {
            AmenAccessPassCreateSheet(
                targetType: targetType,
                targetId: targetId,
                targetTitle: targetTitle,
                orgId: orgId,
                churchId: churchId,
                spaceId: spaceId
            ) { response in
                newPassResponse = response
                Task { await viewModel.load() }
            }
        }
        .sheet(item: $selectedPass) { pass in
            NavigationStack {
                AmenAccessPassQRCodeView(
                    pass: pass,
                    universalLink: newPassResponse?.universalLink ?? "https://amen.app/access/\(pass.accessPassId)"
                ) {
                    Task {
                        try? await AmenAccessPassService.shared.revokeAccessPass(accessPassId: pass.accessPassId)
                        AmenAccessPassAnalytics.shared.logRevoked(passId: pass.accessPassId, targetType: pass.targetType)
                        await viewModel.load()
                    }
                    selectedPass = nil
                } onRotateToken: {
                    Task { await viewModel.load() }
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(targetTitle)
                        .font(.headline)
                    Text(targetType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.activePasses.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func passesSection(title: String, passes: [AmenAccessPassSummary]) -> some View {
        Section(title) {
            ForEach(passes) { pass in
                Button {
                    selectedPass = pass
                } label: {
                    PassRowView(pass: pass)
                }
                .swipeActions(edge: .trailing) {
                    if pass.status == .active {
                        Button("Pause") {
                            Task {
                                try? await AmenAccessPassService.shared.pauseAccessPass(accessPassId: pass.accessPassId)
                                AmenAccessPassAnalytics.shared.logPaused(passId: pass.accessPassId)
                                await viewModel.load()
                            }
                        }
                        .tint(.orange)
                    }
                    if pass.status == .paused {
                        Button("Resume") {
                            Task {
                                try? await AmenAccessPassService.shared.resumeAccessPass(accessPassId: pass.accessPassId)
                                AmenAccessPassAnalytics.shared.logResumed(passId: pass.accessPassId)
                                await viewModel.load()
                            }
                        }
                        .tint(.green)
                    }
                    Button("Revoke", role: .destructive) {
                        Task {
                            try? await AmenAccessPassService.shared.revokeAccessPass(accessPassId: pass.accessPassId)
                            AmenAccessPassAnalytics.shared.logRevoked(passId: pass.accessPassId, targetType: pass.targetType)
                            await viewModel.load()
                        }
                    }
                }
            }
        }
    }

    private var requestsSection: some View {
        Section("Pending Requests (\(viewModel.pendingRequests.count))") {
            ForEach(viewModel.pendingRequests) { request in
                RequestRowView(request: request) {
                    Task {
                        try? await AmenAccessPassService.shared.approveAccessRequest(requestId: request.requestId)
                        await viewModel.load()
                    }
                } onDeny: {
                    Task {
                        try? await AmenAccessPassService.shared.denyAccessRequest(requestId: request.requestId)
                        await viewModel.load()
                    }
                }
            }
        }
    }
}

// MARK: - Row Views

private struct PassRowView: View {
    let pass: AmenAccessPassSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pass.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    StatusBadgeView(status: pass.status)
                    Text(pass.mode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let exp = pass.expiresAt {
                    Text("Expires \(exp.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(pass.usesCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let max = pass.maxUses {
                    Text("/ \(max)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("uses")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct RequestRowView: View {
    let request: AmenAccessRequest
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.requesterDisplayName ?? "Someone")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(request.createdAt.formatted(.relative(presentation: .numeric)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Approve request from \(request.requesterDisplayName ?? "user")")

                Button("Deny", role: .destructive) { onDeny() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Deny request from \(request.requesterDisplayName ?? "user")")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ViewModel

@MainActor
final class AmenAccessPassAdminViewModel: ObservableObject {
    let targetType: AmenAccessTargetType
    let targetId: String

    @Published var passes: [AmenAccessPassSummary] = []
    @Published var pendingRequests: [AmenAccessRequest] = []
    @Published var isLoading = false
    @Published var error: String?

    var activePasses: [AmenAccessPassSummary] {
        passes.filter { $0.status == .active || $0.status == .paused }
    }

    var inactivePasses: [AmenAccessPassSummary] {
        passes.filter { $0.status == .revoked || $0.status == .expired }
    }

    init(targetType: AmenAccessTargetType, targetId: String) {
        self.targetType = targetType
        self.targetId = targetId
    }

    func load() async {
        isLoading = true
        do {
            async let passesResult = AmenAccessPassService.shared.listAccessPassesForTarget(
                targetType: targetType, targetId: targetId
            )
            async let requestsResult = AmenAccessPassService.shared.listAccessRequestsForTarget(
                targetType: targetType, targetId: targetId
            )
            let (fetchedPasses, fetchedRequests) = try await (passesResult, requestsResult)
            passes = fetchedPasses
            pendingRequests = fetchedRequests.filter { $0.status == .pending }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
