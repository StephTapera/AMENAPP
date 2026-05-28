// AmenConversationOSCards.swift
// AMEN Conversation OS — Liquid Glass UI Cards
//
// Liquid Glass design rules:
// - Ambient, contextual, subtle, spatial, calm, non-intrusive
// - .ultraThinMaterial backgrounds — no glass-on-glass stacking
// - White background / black text for content areas
// - Reduce Motion / Reduce Transparency fallback always present
// - No aggressive popups. No spammy overlays.
// - Every button must be wired — no silent no-ops.

import SwiftUI

// MARK: - Catch-Up Card (main summary surface)

struct AmenCatchUpCard: View {
    let summary: ConversationSummary
    @ObservedObject var viewModel: AmenConversationOSViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Header
                HStack {
                    Label("Catch-Up", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    AmenAIUsageLabel(text: "AI-assisted")
                    Button {
                        Task { await viewModel.dismissSummary() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss this summary")
                }

                // Confidence wording
                if !summary.isHighConfidence {
                    Label("Based on available messages", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Summary text
                Text(summary.confidenceLabel + summary.summaryText)
                    .font(.body)
                    .foregroundStyle(.primary)

                // Coverage window
                Text("Covers \(formattedWindow(summary.coverageWindowStart, summary.coverageWindowEnd)) · \(summary.messageCount) messages")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Divider()

                // Topic Clusters
                if !summary.topicClusters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Topics")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.topicClusters) { cluster in
                            AmenTopicClusterChip(cluster: cluster) {
                                viewModel.selectCluster(cluster)
                            }
                        }
                    }
                }

                // Decisions
                if !summary.decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decisions")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.decisions) { decision in
                            AmenConversationDecisionCard(decision: decision, viewModel: viewModel)
                        }
                    }
                }

                // Actions
                if !summary.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.actionItems.filter { $0.status == .pending }) { action in
                            AmenConversationActionCard(action: action, viewModel: viewModel)
                        }
                    }
                }

                // Unresolved Questions
                if !summary.unresolvedQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unresolved Questions")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.unresolvedQuestions.filter { !$0.dismissed }) { question in
                            AmenUnresolvedQuestionCard(question: question) {
                                viewModel.dismissQuestion(question)
                            }
                        }
                    }
                }

                // Blockers
                if !summary.blockers.filter({ !$0.resolved }).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blockers")
                            .font(.subheadline.weight(.semibold))
                        ForEach(summary.blockers.filter { !$0.resolved }) { blocker in
                            AmenBlockerCard(blocker: blocker)
                        }
                    }
                }
            }
            .padding()
        }
        .background(reduceTransparency ? Color(uiColor: .systemBackground) : .clear)
    }

    private func formattedWindow(_ start: Date, _ end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}

// MARK: - Topic Cluster Chip

struct AmenTopicClusterChip: View {
    let cluster: ConversationTopicCluster
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(cluster.messageCount) messages · \(cluster.participantCount) participants")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cluster.title). \(cluster.messageCount) messages. Tap to expand.")
    }
}

// MARK: - Decision Card

struct AmenConversationDecisionCard: View {
    let decision: ConversationDecision
    @ObservedObject var viewModel: AmenConversationOSViewModel

    private var statusColor: Color {
        switch decision.status {
        case .confirmed: return .green
        case .challenged: return .red
        case .outdated: return .gray
        case .proposed: return .blue
        case .reversed: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(decision.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                if !decision.isHighConfidence {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(decision.summary)
                .font(.footnote)
                .foregroundStyle(.primary)

            if !decision.sourceSnippet.isEmpty {
                Text("\u{201C}\(decision.sourceSnippet.prefix(100))\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if decision.status == .proposed {
                HStack(spacing: 8) {
                    Button("Confirm") {
                        Task { await viewModel.confirmDecision(decision) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Confirm this decision")

                    Button("Challenge") {
                        Task { await viewModel.challengeDecision(decision) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Challenge this decision")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension ConversationDecision {
    var isHighConfidence: Bool { confidence >= 0.75 }
}

// MARK: - Action Item Card

struct AmenConversationActionCard: View {
    let action: ConversationActionItem
    @ObservedObject var viewModel: AmenConversationOSViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                if let assignee = action.assigneeDisplayName {
                    Text("Assigned to \(assignee)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let due = action.dueDate {
                    Label(due.formatted(.relative(presentation: .named)), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    Button("Mark Done") {
                        Task { await viewModel.markActionResolved(action) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Mark action item as done")

                    Button("Dismiss") {
                        Task { await viewModel.dismissAction(action) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss this action item")
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Unresolved Question Card

struct AmenUnresolvedQuestionCard: View {
    let question: ConversationUnresolvedQuestion
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(question.question)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Text("Asked by \(question.askedByDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss this unresolved question")
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Blocker Card

struct AmenBlockerCard: View {
    let blocker: ConversationBlocker

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(blocker.description)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                if !blocker.sourceSnippet.isEmpty {
                    Text("\u{201C}\(blocker.sourceSnippet.prefix(80))\u{201D}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Blocker: \(blocker.description)")
    }
}

// MARK: - Org Memory Card

struct AmenOrgMemoryCard: View {
    let memory: ConversationOrganizationalMemory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(memory.weekLabel, systemImage: "building.2")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    AmenAIUsageLabel(text: "AI-assisted")
                }

                Text(memory.summaryText)
                    .font(.body)

                if !memory.recurringTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recurring Topics")
                            .font(.subheadline.weight(.semibold))
                        let columns = [GridItem(.adaptive(minimum: 80), spacing: 6)]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                            ForEach(memory.recurringTopics, id: \.self) { topic in
                                Text(topic)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                if !memory.collaborationPatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collaboration Patterns")
                            .font(.subheadline.weight(.semibold))
                        ForEach(memory.collaborationPatterns, id: \.self) { pattern in
                            Label(pattern, systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

