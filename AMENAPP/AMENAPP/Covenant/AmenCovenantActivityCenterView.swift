import SwiftUI
import FirebaseCore
import FirebaseFirestore

// MARK: - Covenant Activity Center
// Slack/Teams-style activity feed. Groups by type, supports read/unread,
// deep link routing, priority ordering, and a "Catch me up" summary.

struct AmenCovenantActivityCenterView: View {
    @StateObject private var service = CovenantService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: CovenantActivity.ActivityType? = nil
    @State private var catchUpSummary: CovenantCatchUpSummary?
    @State private var catchUpLoading = false
    @State private var catchUpError: String?

    private var filtered: [CovenantActivity] {
        guard let filter = selectedFilter else { return service.activities }
        return service.activities.filter { $0.type == filter }
    }

    private var grouped: [String: [CovenantActivity]] {
        Dictionary(grouping: filtered) { activity in
            activity.groupId ?? activity.id ?? UUID().uuidString
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterPills
                    .padding(.vertical, 8)

                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        catchMeUpButton
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        if let summary = catchUpSummary {
                            CatchUpSummaryCard(summary: summary) {
                                catchUpSummary = nil
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { activity in
                                CovenantActivityRow(activity: activity) {
                                    Task { await service.markActivityRead(activity.id ?? "") }
                                }
                                Divider().padding(.leading, 62)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if service.activities.contains(where: { !$0.isRead }) {
                        Button("Mark All Read") {
                            Task { await service.markAllActivityRead() }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterPill(nil, label: "All", icon: "tray.fill")
                ForEach(CovenantActivity.ActivityType.allCases, id: \.self) { type in
                    filterPill(type, label: type.displayName, icon: type.icon)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func filterPill(_ type: CovenantActivity.ActivityType?, label: String, icon: String) -> some View {
        let selected = selectedFilter == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedFilter = type
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Color.purple : Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catch Me Up Button

    private var catchMeUpButton: some View {
        Button {
            Task {
                catchUpLoading = true
                catchUpError = nil
                let since = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
                do {
                    catchUpSummary = try await service.generateCatchUp(
                        covenantId: service.covenants.first?.id ?? "",
                        since: since
                    )
                } catch {
                    catchUpError = "Couldn't generate summary right now."
                }
                catchUpLoading = false
            }
        } label: {
            HStack(spacing: 10) {
                if catchUpLoading {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(14, weight: .semibold))
                }
                Text(catchUpLoading ? "Summarizing…" : "Catch me up")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.1))
                    .overlay(Capsule().stroke(Color.purple.opacity(0.2), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(catchUpLoading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.systemScaled(40))
                .foregroundStyle(.tertiary)
            Text("You're all caught up")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("New mentions, replies, and creator updates will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Activity Row

private struct CovenantActivityRow: View {
    let activity: CovenantActivity
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
            AmenCovenantDeepLinkResolver.shared.resolve(activity.deepLink)
        } label: {
            HStack(spacing: 14) {
                // Icon + unread indicator
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activity.type.icon)
                        .font(.systemScaled(16))
                        .foregroundStyle(priorityColor)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(priorityColor.opacity(0.12)))

                    if !activity.isRead {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -3)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(activity.type.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(priorityColor)
                        Spacer()
                        Text(activity.createdAt.dateValue(), style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(activity.title)
                        .font(.subheadline.weight(activity.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    if !activity.body.isEmpty {
                        Text(activity.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(activity.isRead ? Color.clear : Color.purple.opacity(0.03))
    }

    private var priorityColor: Color {
        switch activity.priority {
        case .urgent: return .red
        case .high:   return .orange
        case .normal: return .purple
        case .low:    return .secondary
        }
    }
}

// MARK: - Catch-Up Summary Card

private struct CatchUpSummaryCard: View {
    let summary: CovenantCatchUpSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Catch-Up Summary", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if !summary.decisions.isEmpty {
                summarySection("Decisions", items: summary.decisions, icon: "checkmark.circle")
            }
            if !summary.prayerUpdates.isEmpty {
                summarySection("Prayer Updates", items: summary.prayerUpdates, icon: "hands.sparkles")
            }
            if !summary.unansweredQuestions.isEmpty {
                summarySection("Open Questions", items: summary.unansweredQuestions, icon: "questionmark.circle")
            }
            if !summary.upcomingEvents.isEmpty {
                summarySection("Upcoming", items: summary.upcomingEvents, icon: "calendar")
            }
            if !summary.suggestedActions.isEmpty {
                summarySection("Suggested Actions", items: summary.suggestedActions, icon: "arrow.right.circle")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.purple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func summarySection(_ title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ActivityType CaseIterable

extension CovenantActivity.ActivityType: CaseIterable {
    public static var allCases: [CovenantActivity.ActivityType] {
        [.mention, .reply, .creatorAnnouncement, .newPaidPost, .eventReminder,
         .prayerFollowUp, .moderationNotice, .tierUpdate, .digestReady, .roomInvite]
    }
}
