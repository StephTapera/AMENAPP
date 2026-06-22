// AmenCommunityModerationDashboardView.swift
// AMENAPP — CommunityOS/Moderation
//
// Phase 4 Agent TS-d — Moderation & Governance
//
// Moderator dashboard for reviewing the content queue, taking actions,
// reviewing appeals, and viewing community health signals.
//
// Access: Requires Moderator+ role in the given context (enforced by Firestore rules
//   and by AmenModerationService.loadModQueue() via AmenRBACService pre-check).
//
// Design: White Liquid Glass — .ultraThinMaterial cards, .insetGrouped list,
//   NavigationStack with large title, system colors throughout.
//
// Phase 4 Agent TS-d

import SwiftUI

// MARK: - AmenCommunityModerationDashboardView

struct AmenCommunityModerationDashboardView: View {

    let contextType: String
    let contextId: String
    let moderatorId: String

    @StateObject private var service = AmenModerationService()
    @State private var loadError: String?
    @State private var selectedTab: ModDashTab = .queue
    // SECURITY FIX (CRITICAL 2026-06-11): Error state for moderation action failures.
    // Moderators must know if their action (remove, ban, escalate) or appeal review failed.
    @State private var actionError: String?

    // MARK: - Tab

    private enum ModDashTab: String, CaseIterable {
        case queue   = "Queue"
        case appeals = "Appeals"
        case health  = "Health"

        var symbolName: String {
            switch self {
            case .queue:   return "list.bullet.clipboard"
            case .appeals: return "arrow.uturn.backward.circle"
            case .health:  return "heart.text.clipboard"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                Divider().opacity(0.15)

                Group {
                    if service.isLoading {
                        loadingView
                    } else if let error = loadError {
                        errorView(error)
                    } else {
                        switch selectedTab {
                        case .queue:   queueSection
                        case .appeals: appealsSection
                        case .health:  healthSection
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadQueue()
            }
            .refreshable {
                await loadQueue()
            }
            .alert("Action Failed", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "An error occurred.")
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ModDashTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbolName)
                            .font(.systemScaled(15, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.systemScaled(11, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
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

    // MARK: - Queue Section

    @ViewBuilder
    private var queueSection: some View {
        let active = service.queueItems.filter { $0.status.requiresAttention }
        let reviewed = service.queueItems.filter { !$0.status.requiresAttention }

        List {
            if active.isEmpty && reviewed.isEmpty {
                ContentUnavailableView(
                    "No items in queue",
                    systemImage: "checkmark.seal",
                    description: Text("The moderation queue is clear.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { item in
                            AmenModerationQueueRow(item: item) { action, note in
                                Task {
                                    do {
                                        try await service.takeAction(
                                            itemId: item.id,
                                            action: action,
                                            note: note,
                                            moderatorId: moderatorId
                                        )
                                    } catch {
                                        await MainActor.run {
                                            actionError = "Action failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Label("Needs Review (\(active.count))", systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                if !reviewed.isEmpty {
                    Section {
                        ForEach(reviewed) { item in
                            AmenModerationQueueRow(item: item, onAction: { _, _ in })
                        }
                    } header: {
                        Label("Recently Resolved", systemImage: "checkmark.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Appeals Section

    @ViewBuilder
    private var appealsSection: some View {
        let pending = service.appeals.filter { $0.status == .pending }
        let resolved = service.appeals.filter { $0.status != .pending }

        List {
            if pending.isEmpty && resolved.isEmpty {
                ContentUnavailableView(
                    "No pending appeals",
                    systemImage: "arrow.uturn.backward.circle",
                    description: Text("No appeals are awaiting review.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if !pending.isEmpty {
                    Section("Pending Appeals") {
                        ForEach(pending) { appeal in
                            AmenAppealRow(appeal: appeal) { status, note in
                                Task {
                                    do {
                                        try await service.reviewAppeal(
                                            appealId: appeal.id,
                                            status: status,
                                            note: note,
                                            reviewerId: moderatorId
                                        )
                                    } catch {
                                        await MainActor.run {
                                            actionError = "Appeal review failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !resolved.isEmpty {
                    Section("Recent Decisions") {
                        ForEach(resolved) { appeal in
                            AmenAppealRow(appeal: appeal, onDecision: nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Health Section

    private var healthSection: some View {
        AmenCommunityHealthView(
            contextType: contextType,
            contextId: contextId
        )
    }

    // MARK: - Utility Views

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading queue…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading moderation queue")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Couldn't load queue")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await loadQueue() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Data

    private func loadQueue() async {
        loadError = nil
        do {
            try await service.loadModQueue(
                contextType: contextType,
                contextId: contextId,
                moderatorId: moderatorId
            )
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - AmenModerationQueueRow

struct AmenModerationQueueRow: View {

    let item: ModerationQueueItem
    var onAction: (ModerationActionType, String) -> Void

    @State private var showActionSheet: Bool = false
    @State private var actionNote: String = ""
    @State private var pendingAction: ModerationActionType?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: content type + risk tier badge + escalation warning
            HStack(spacing: 8) {
                Text(item.contentType.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if item.escalateImmediately {
                    Label("Urgent", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .accessibilityLabel("Urgent: requires immediate review")
                } else {
                    riskBadge(tier: item.riskTier)
                }

                statusBadge(status: item.status)
            }

            // Report reason
            Text(item.reportReason)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Content reference (truncated for readability)
            Text(item.contentRef)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            // Moderator note if already actioned
            if let note = item.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Action menu (only shown for items requiring attention)
            if item.status.requiresAttention {
                Menu {
                    ForEach(actionOptions, id: \.self) { action in
                        Button {
                            pendingAction = action
                            showActionSheet = true
                        } label: {
                            Label(action.displayLabel, systemImage: action.symbolName)
                        }
                    }
                } label: {
                    Label("Take action", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take moderation action on this item")
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showActionSheet) {
            actionNoteSheet
        }
    }

    // MARK: - Action Note Sheet

    @ViewBuilder
    private var actionNoteSheet: some View {
        if let action = pendingAction {
            NavigationStack {
                Form {
                    Section("Action") {
                        Label(action.displayLabel, systemImage: action.symbolName)
                            .font(.body.weight(.medium))
                    }
                    Section("Note (required)") {
                        TextField("Explain your decision…", text: $actionNote, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityLabel("Moderation decision note")
                    }
                }
                .navigationTitle("Confirm Action")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showActionSheet = false
                            actionNote = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") {
                            let note = actionNote
                            showActionSheet = false
                            actionNote = ""
                            onAction(action, note)
                        }
                        .disabled(actionNote.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Helpers

    private var actionOptions: [ModerationActionType] {
        switch item.status {
        case .escalated:
            return [.remove, .warn, .restore, .noAction]
        case .appealed:
            return [.appealGranted, .appealDenied]
        default:
            return [.remove, .warn, .ban, .escalate, .noAction]
        }
    }

    private func riskBadge(tier: String) -> some View {
        let color: Color = {
            switch tier {
            case "severe": return .red
            case "high":   return .orange
            case "medium": return .yellow
            default:       return .green
            }
        }()

        return Text(tier.capitalized)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1)
            }
            .accessibilityLabel("Risk level: \(tier)")
    }

    private func statusBadge(status: ModerationItemStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(uiColor: .systemGroupedBackground))
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayLabel)")
    }
}

// MARK: - AmenAppealRow

struct AmenAppealRow: View {

    let appeal: AmenModerationAppeal
    var onDecision: ((AppealStatus, String) -> Void)?

    @State private var showReviewSheet: Bool = false
    @State private var reviewNote: String = ""
    @State private var pendingStatus: AppealStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Appeal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                appealStatusBadge(appeal.status)
            }

            // Reason
            Text(appeal.reason)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            // Date
            Text(appeal.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Review note if resolved
            if let note = appeal.reviewNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Grant / Deny buttons — only for pending appeals with a callback
            if appeal.status == .pending, let handler = onDecision {
                HStack(spacing: 12) {
                    Button {
                        pendingStatus = .granted
                        showReviewSheet = true
                    } label: {
                        Label("Grant", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Grant this appeal")

                    Button {
                        pendingStatus = .denied
                        showReviewSheet = true
                    } label: {
                        Label("Deny", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Deny this appeal")
                }
                .sheet(isPresented: $showReviewSheet) {
                    reviewNoteSheet(handler: handler)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func reviewNoteSheet(handler: @escaping (AppealStatus, String) -> Void) -> some View {
        if let status = pendingStatus {
            NavigationStack {
                Form {
                    Section("Decision") {
                        Label(status == .granted ? "Grant Appeal" : "Deny Appeal",
                              systemImage: status == .granted ? "checkmark.circle" : "xmark.circle")
                    }
                    Section("Note (required)") {
                        TextField("Explain your decision…", text: $reviewNote, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityLabel("Appeal decision note")
                    }
                }
                .navigationTitle("Review Appeal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showReviewSheet = false
                            reviewNote = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") {
                            let note = reviewNote
                            showReviewSheet = false
                            reviewNote = ""
                            handler(status, note)
                        }
                        .disabled(reviewNote.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func appealStatusBadge(_ status: AppealStatus) -> some View {
        let color: Color = {
            switch status {
            case .pending: return .orange
            case .granted: return .green
            case .denied:  return .red
            }
        }()
        return Text(status.displayLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1)
            }
            .accessibilityLabel("Appeal status: \(status.displayLabel)")
    }
}

// MARK: - AmenCommunityHealthView

/// Displays aggregated, privacy-preserving community health signals.
/// No individual user attribution — counts only.
private struct AmenCommunityHealthView: View {

    let contextType: String
    let contextId: String

    @State private var signal: CommunityHealthSignal?
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading health data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading community health data")
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.systemScaled(36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let signal = signal {
                healthContent(signal)
            }
        }
        .task { await loadHealth() }
    }

    private func healthContent(_ signal: CommunityHealthSignal) -> some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Community Health")
                            .font(.headline)
                        Text("Last \(signal.period)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: signal.isHealthy ? "heart.fill" : "heart.slash")
                        .font(.systemScaled(28))
                        .foregroundStyle(signal.isHealthy ? Color.green : Color.orange)
                        .accessibilityLabel(signal.isHealthy ? "Healthy" : "Needs attention")
                }
                .padding(.vertical, 4)
            }

            Section("Reports") {
                metricRow("Total Reports", value: "\(signal.reportCount)", symbol: "flag")
                metricRow("Resolved", value: "\(signal.resolvedCount)", symbol: "checkmark.circle")
                metricRow(
                    "Resolution Rate",
                    value: String(format: "%.0f%%", signal.resolutionRate * 100),
                    symbol: "percent"
                )
            }

            Section("Response Time") {
                metricRow(
                    "Avg. Resolution Time",
                    value: String(format: "%.1f hours", signal.averageResolutionHours),
                    symbol: "clock"
                )
            }

            Section("Appeals") {
                metricRow(
                    "Appeals Granted",
                    value: "\(signal.appealGrantedCount)",
                    symbol: "arrow.uturn.backward.circle"
                )
            }

            Section {
                Text("Health signals are privacy-preserving and contain no individual user information.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func metricRow(_ label: String, value: String, symbol: String) -> some View {
        HStack {
            Label(label, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func loadHealth() async {
        isLoading = true
        defer { isLoading = false }
        do {
            signal = try await AmenModerationService().getCommunityHealth(
                contextType: contextType,
                contextId: contextId
            )
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    AmenCommunityModerationDashboardView(
        contextType: "church",
        contextId: "preview-church",
        moderatorId: "preview-mod"
    )
}
