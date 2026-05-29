import SwiftUI

// MARK: - ExperienceSafetyConsole

/// Moderator-only view for managing safety, reports, and slow mode for an experience.
struct ExperienceSafetyConsole: View {

    let experience: ContextualExperience
    let userRole: OrgMemberRole

    @State private var reports: [ExperienceContentReport] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var isSlowModeOn = false
    @State private var showLockConfirmation = false
    @State private var isTogglingSlowMode = false
    @State private var isLocking = false

    @Environment(\.dismiss) private var dismiss

    private let service = ContextualExperienceService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                safetyConfigSection
                reportQueueSection
                if userRole.isAdmin {
                    controlsSection
                }
            }
            .listStyle(.insetGrouped)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Safety Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .accessibilityLabel("Close safety console")
                }
            }
        }
        .task { await loadReports() }
        .alert("Lock Experience?", isPresented: $showLockConfirmation) {
            Button("Lock", role: .destructive) {
                Task { await lockExperience() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will immediately prevent all participants from joining or interacting. This cannot be undone without admin support.")
        }
    }

    // MARK: - Safety config section

    private var safetyConfigSection: some View {
        Section("Safety Configuration") {
            safetyBadgeRow(
                label: "Youth Protection",
                icon: "person.badge.shield.checkmark.fill",
                enabled: experience.safety.requiresYouthProtection
            )
            safetyBadgeRow(
                label: "Grief Mode",
                icon: "heart.circle.fill",
                enabled: experience.safety.griefSensitiveMode
            )
            safetyBadgeRow(
                label: "Require Approval to Join",
                icon: "person.badge.plus.fill",
                enabled: experience.safety.requireApprovalToJoin
            )
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 20)
                Text("Moderation Level")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Text(experience.safety.moderationStrictness.capitalized)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Moderation level: \(experience.safety.moderationStrictness)")
        }
    }

    private func safetyBadgeRow(label: String, icon: String, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(
                    enabled
                        ? AmenTheme.Colors.statusSuccess
                        : AmenTheme.Colors.textSecondary
                )
                .frame(width: 20)
            Text(label)
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Text(enabled ? "ON" : "OFF")
                .font(AMENFont.bold(11))
                .foregroundStyle(
                    enabled
                        ? AmenTheme.Colors.statusSuccess
                        : AmenTheme.Colors.textSecondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        enabled
                            ? AmenTheme.Colors.statusSuccess.opacity(0.12)
                            : AmenTheme.Colors.surfaceChip
                    )
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(enabled ? "On" : "Off")")
    }

    // MARK: - Report queue section

    private var reportQueueSection: some View {
        Section("Report Queue (\(reports.count))") {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading reports...")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.leading, 8)
                }
            } else if reports.isEmpty {
                Label("No pending reports", systemImage: "checkmark.shield.fill")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .accessibilityLabel("No pending reports")
            } else {
                ForEach(reports) { report in
                    reportRow(report)
                }
            }
        }
    }

    private func reportRow(_ report: ExperienceContentReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.reason)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                statusPill(report.status)
            }
            Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(AMENFont.regular(11))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            if report.status == .pending {
                HStack(spacing: 8) {
                    reportActionButton(
                        label: "Approve",
                        color: AmenTheme.Colors.statusSuccess
                    ) {
                        Task { await handleReport(report, action: "approve") }
                    }
                    reportActionButton(
                        label: "Reject",
                        color: AmenTheme.Colors.statusWarning
                    ) {
                        Task { await handleReport(report, action: "reject") }
                    }
                    reportActionButton(
                        label: "Escalate",
                        color: AmenTheme.Colors.statusError
                    ) {
                        Task { await handleReport(report, action: "escalate") }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Report: \(report.reason), status: \(report.status.rawValue)")
    }

    private func statusPill(_ status: ExperienceContentReport.ReportStatus) -> some View {
        let color: Color = {
            switch status {
            case .pending:   return AmenTheme.Colors.statusWarning
            case .approved:  return AmenTheme.Colors.statusSuccess
            case .rejected:  return AmenTheme.Colors.textSecondary
            case .escalated: return AmenTheme.Colors.statusError
            }
        }()
        return Text(status.rawValue.capitalized)
            .font(AMENFont.bold(10))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func reportActionButton(
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            Text(label)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(color.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Controls section (admin only)

    private var controlsSection: some View {
        Section("Controls") {
            Toggle(isOn: Binding(
                get: { isSlowModeOn },
                set: { newVal in
                    HapticManager.impact(style: .light)
                    Task { await toggleSlowMode(newVal) }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "tortoise.fill")
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Slow Mode")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Limits how often members can post")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
            .disabled(isTogglingSlowMode)
            .accessibilityLabel("Slow mode toggle")
            .accessibilityHint("Limits how often members can post")

            Button(role: .destructive) {
                HapticManager.impact(style: .light)
                showLockConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                    Text(isLocking ? "Locking…" : "Lock Experience")
                        .font(AMENFont.semiBold(15))
                }
                .foregroundStyle(AmenTheme.Colors.statusError)
            }
            .disabled(isLocking || experience.isKillSwitched)
            .accessibilityLabel("Lock experience")
            .accessibilityHint("Prevents all interactions in this experience")
        }
    }

    // MARK: - Actions

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await service.fetchReports(experienceId: experience.id ?? "")
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func handleReport(
        _ report: ExperienceContentReport,
        action: String
    ) async {
        do {
            try await service.moderateContent(
                experienceId: experience.id ?? "",
                contentType: "report",
                contentId: report.id ?? "",
                action: action,
                reason: nil
            )
            await loadReports()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleSlowMode(_ enabled: Bool) async {
        isTogglingSlowMode = true
        do {
            try await service.setSlowMode(experienceId: experience.id ?? "", enabled: enabled)
            isSlowModeOn = enabled
        } catch {
            self.error = error.localizedDescription
        }
        isTogglingSlowMode = false
    }

    private func lockExperience() async {
        isLocking = true
        do {
            try await service.lockExperience(experienceId: experience.id ?? "")
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isLocking = false
        }
    }
}

// MARK: - ExperienceContentReport model (local to console)

struct ExperienceContentReport: Identifiable, Codable {
    var id: String?
    var reason: String
    var status: ReportStatus
    var createdAt: Date

    enum ReportStatus: String, Codable {
        case pending, approved, rejected, escalated
    }
}
