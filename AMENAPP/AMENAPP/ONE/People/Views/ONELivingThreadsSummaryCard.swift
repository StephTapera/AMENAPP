// ONELivingThreadsSummaryCard.swift
// ONE — Collapsible on-device Living Threads AI card.
// Privacy invariant: this summary is never uploaded. The user controls every share.

import SwiftUI

struct ONELivingThreadsSummaryCard: View {
    let summary: ONELivingThreadSummary
    var onShareItem: ((String) -> Void)? = nil

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasContent: Bool {
        !summary.decisions.isEmpty || !summary.promises.isEmpty ||
        !summary.tasks.isEmpty || !summary.importantDates.isEmpty ||
        !summary.prayerRequests.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .stroke(ONE.Colors.glassWarm.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.top, ONE.Spacing.sm)
            .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: isExpanded)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: ONE.Spacing.sm) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 12))
                    .foregroundStyle(ONE.Colors.witnessGold)

                Text("Living Threads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("On-device")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ONE.Colors.privateIndigo)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ONE.Colors.privateIndigo.opacity(0.10)))

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Living Threads summary, on-device only")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to view decisions, tasks, and prayer requests")
    }

    // MARK: Expanded content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.md) {
            Divider().padding(.top, ONE.Spacing.sm)

            if !summary.decisions.isEmpty {
                listSection("Decisions", icon: "checkmark.seal.fill",
                            tint: ONE.Colors.repairGreen, items: summary.decisions)
            }
            if !summary.promises.isEmpty {
                listSection("Promises", icon: "hands.clap.fill",
                            tint: ONE.Colors.witnessGold, items: summary.promises)
            }
            if !summary.tasks.isEmpty {
                tasksSection
            }
            if !summary.importantDates.isEmpty {
                datesSection
            }
            if !summary.prayerRequests.isEmpty {
                listSection("Prayer Requests", icon: "hands.sparkles.fill",
                            tint: ONE.Colors.privateIndigo, items: summary.prayerRequests)
            }

            privacyNote
        }
    }

    // MARK: Sections

    private func listSection(_ title: String, icon: String, tint: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                itemRow(item)
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            Label("Tasks", systemImage: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ONE.Colors.decayAmber)
            ForEach(summary.tasks) { task in
                HStack(alignment: .top, spacing: ONE.Spacing.xs) {
                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(task.isComplete ? ONE.Colors.repairGreen : .secondary)
                    Text(task.description)
                        .font(.system(size: 13))
                        .foregroundStyle(task.isComplete ? .secondary : .primary)
                        .strikethrough(task.isComplete)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if let share = onShareItem {
                        shareBtn(task.description, action: share)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(task.isComplete ? "Completed" : "Pending") task: \(task.description)")
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.xs) {
            Label("Dates", systemImage: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ONE.Colors.ephemeralRed)
            ForEach(Array(summary.importantDates.enumerated()), id: \.offset) { _, d in
                itemRow(d.label)
            }
        }
    }

    // MARK: Helpers

    private func itemRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: ONE.Spacing.xs) {
            Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let share = onShareItem { shareBtn(text, action: share) }
        }
    }

    private func shareBtn(_ text: String, action: @escaping (String) -> Void) -> some View {
        Button { action(text) } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share: \(text)")
    }

    private var privacyNote: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text("These notes stay on your device until you choose to share them.")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .padding(.top, ONE.Spacing.xs)
    }
}
