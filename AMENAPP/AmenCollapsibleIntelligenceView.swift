// AmenCollapsibleIntelligenceView.swift
// AMEN App — Collapsible Intelligence Layers
//
// Compresses long discussions into: what changed / what matters /
// unresolved points / key people / scripture refs / action items.
// Uses existing ConversationSummary — just presents it in a collapsible surface.

import SwiftUI

struct AmenCollapsibleIntelligenceView: View {
    let summary: ConversationSummary
    var onOpenThread: ((String) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            collapseHeader
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .animation(reduceMotion ? .none : .spring(response: 0.36, dampingFraction: 0.82), value: isExpanded)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Collapsed Header

    private var collapseHeader: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.80)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.50))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isExpanded ? "Summary" : collapsedHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .lineLimit(1)
                    if !isExpanded {
                        Text("\(summary.messageCount) messages · \(summary.topicClusters.count) topics")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.black.opacity(0.40))
                    }
                }

                Spacer(minLength: 0)

                if !summary.actionItems.filter({ $0.status == .pending }).isEmpty {
                    actionBadge
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse summary" : "Expand summary: \(collapsedHeadline)")
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().opacity(0.15)

            // What changed
            if !summary.summaryText.isEmpty {
                intelligenceSection(icon: "arrow.triangle.2.circlepath", title: "What changed") {
                    Text(summary.summaryText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Topic clusters — what matters
            if !summary.topicClusters.isEmpty {
                intelligenceSection(icon: "circle.hexagongrid.fill", title: "Key topics") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.topicClusters.prefix(3)) { cluster in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.black.opacity(0.12))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(cluster.confidencePrefix + cluster.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.black.opacity(0.68))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Unresolved questions
            if !summary.unresolvedQuestions.isEmpty {
                intelligenceSection(icon: "questionmark.circle", title: "Unresolved") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.unresolvedQuestions.prefix(3)) { q in
                            Text("· \(q.question)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.black.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Action items
            let pending = summary.actionItems.filter { $0.status == .pending }
            if !pending.isEmpty {
                intelligenceSection(icon: "checkmark.circle", title: "Action items") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pending.prefix(3)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.black.opacity(0.30))
                                Text(item.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.black.opacity(0.70))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            // Decisions
            let confirmed = summary.decisions.filter { $0.status == .confirmed || $0.status == .proposed }
            if !confirmed.isEmpty {
                intelligenceSection(icon: "checkmark.seal", title: "Decisions") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(confirmed.prefix(2)) { d in
                            Text("· \(d.summary)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.black.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if onDismiss != nil {
                HStack {
                    Spacer()
                    Button { onDismiss?() } label: {
                        Text("Dismiss")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Support

    @ViewBuilder
    private func intelligenceSection<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.42))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .textCase(.uppercase)
                    .kerning(0.4)
            }
            content()
        }
    }

    private var collapsedHeadline: String {
        summary.topicClusters.first?.title ?? "Discussion summary"
    }

    private var actionBadge: some View {
        let count = summary.actionItems.filter { $0.status == .pending }.count
        return Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.70)))
            .accessibilityLabel("\(count) pending action items")
    }
}

// MARK: - Preview

#Preview {
    let fakeSummary = ConversationSummary(
        id: "s1",
        spaceId: "sp1",
        threadId: nil,
        surface: .amenSpaces,
        summaryText: "The group discussed next Sunday's outreach event and prayer needs.",
        summaryType: .catchUp,
        topicClusters: [
            ConversationTopicCluster(
                id: "c1", title: "Outreach planning", summary: "Logistics for Sunday.",
                tags: [.task], messageCount: 12, participantCount: 5,
                createdAt: .now, updatedAt: .now, confidence: 0.88, messages: []
            )
        ],
        decisions: [],
        actionItems: [],
        unresolvedQuestions: [
            ConversationUnresolvedQuestion(
                id: "q1", question: "Who is bringing the van?", sourceSnippet: "",
                askedByDisplayName: "Marcus", threadId: "t1", askedAt: .now, dismissed: false
            )
        ],
        blockers: [],
        generatedAt: .now,
        coverageWindowStart: .now,
        coverageWindowEnd: .now,
        messageCount: 34,
        confidence: 0.82,
        provenance: ConversationSummaryProvenance(
            provider: "claude", modelVersion: "claude-sonnet-4-6",
            generatedAt: .now, compressionRatio: 0.14,
            moderationPassed: true, permissionsValidated: true
        )
    )

    AmenCollapsibleIntelligenceView(summary: fakeSummary)
        .padding()
        .background(Color(red: 0.96, green: 0.96, blue: 0.94))
}
