// ChurchNoteShareCard.swift
// AMENAPP — MusicContentLayer
// Shareable post card UI for church/sermon notes

import SwiftUI

// MARK: - Data Model

struct ChurchNoteShareCardData: Codable, Sendable, Identifiable {
    let id: String
    let sermonTitle: String
    let speakerName: String
    let churchName: String
    let date: String
    let scriptureReferences: [String]
    let keyPoints: [String]
    let personalTakeaway: String?
    let actionSteps: [String]
    let prayerPrompt: String?
    let discussionQuestions: [String]
    let worshipPlaylistAttachmentID: String?
    let sermonAudioURL: URL?
    let visibility: String
    let createdAt: String
}

// MARK: - Supporting Views

private struct ScripturePill: View {
    let reference: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(reference)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(uiColor: .systemBackground))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        contrast == .increased
                            ? Color.primary.opacity(0.6)
                            : Color.white.opacity(0.25),
                        lineWidth: contrast == .increased ? 1.5 : 1
                    )
            }
            .accessibilityLabel("Scripture reference: \(reference)")
    }
}

private struct KeyPointRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Point \(index + 1): \(text)")
    }
}

private struct ActionStepRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16))
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Action step: \(text)")
    }
}

private struct ChurchNoteSharePrayerCard: View {
    let prompt: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hands.and.sparkles.fill")
                .foregroundStyle(.purple)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Prayer Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prompt)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.purple.opacity(0.06))
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    contrast == .increased
                        ? Color.purple.opacity(0.7)
                        : Color.white.opacity(0.2),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prayer prompt: \(prompt)")
    }
}

private struct GlassSectionCard<Content: View>: View {
    let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    contrast == .increased
                        ? Color.primary.opacity(0.5)
                        : Color.white.opacity(0.2),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

// MARK: - Main View

struct ChurchNoteShareCard: View {
    let data: ChurchNoteShareCardData

    @State private var isExpanded: Bool = false
    @State private var isSaved: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            headerView
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sermonTitleSection
                    scriptureSection
                    keyPointsSection
                    if let takeaway = data.personalTakeaway {
                        takeawaySection(takeaway)
                    }
                    actionStepsSection
                    if let prayer = data.prayerPrompt {
                        ChurchNoteSharePrayerCard(prompt: prayer)
                    }
                    if !data.discussionQuestions.isEmpty {
                        discussionSection
                    }
                }
                .padding(16)
            }
            footerView
        }
        .background {
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                Color.clear
            }
        }
    }

    // MARK: Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.churchName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(data.speakerName.prefix(1)))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(data.speakerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(data.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                visibilityBadge
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(data.speakerName), \(data.date)")
        }
        .padding(16)
        .background {
            if reduceTransparency {
                Color(uiColor: .secondarySystemBackground)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(Color.white.opacity(0.04)))
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(contrast == .increased ? 1 : 0.4)
        }
    }

    private var visibilityBadge: some View {
        let icon: String
        let label: String
        switch data.visibility {
        case "private":
            icon = "lock.fill"
            label = "Private"
        case "membersOnly":
            icon = "person.2.fill"
            label = "Members"
        default:
            icon = "globe"
            label = "Public"
        }
        return Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("Visibility: \(label)")
    }

    // MARK: Sermon Title

    private var sermonTitleSection: some View {
        Text(data.sermonTitle)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Scriptures

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !data.scriptureReferences.isEmpty {
                Text("Scriptures")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                ChurchNoteShareFlowLayout(spacing: 6) {
                    ForEach(data.scriptureReferences, id: \.self) { ref in
                        ScripturePill(reference: ref)
                    }
                }
            }
        }
    }

    // MARK: Key Points

    private var keyPointsSection: some View {
        GlassSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Key Points")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(data.keyPoints.enumerated()), id: \.offset) { idx, point in
                    KeyPointRow(index: idx, text: point)
                }
            }
        }
    }

    // MARK: Takeaway

    private func takeawaySection(_ text: String) -> some View {
        GlassSectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Personal Takeaway", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Action Steps

    private var actionStepsSection: some View {
        GlassSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Action Steps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(data.actionSteps, id: \.self) { step in
                    ActionStepRow(text: step)
                }
            }
        }
    }

    // MARK: Discussion Questions

    private var discussionSection: some View {
        GlassSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if reduceMotion {
                        isExpanded.toggle()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            isExpanded.toggle()
                        }
                    }
                } label: {
                    HStack {
                        Text("Discussion Questions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Discussion questions")
                .accessibilityHint(isExpanded ? "Collapse" : "Expand to see \(data.discussionQuestions.count) questions")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(data.discussionQuestions.enumerated()), id: \.offset) { idx, question in
                            HStack(alignment: .top, spacing: 8) {
                                Text("Q\(idx + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.purple)
                                    .frame(width: 24, alignment: .leading)
                                    .accessibilityHidden(true)
                                Text(question)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Question \(idx + 1): \(question)")
                        }
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
                }
            }
        }
    }

    // MARK: Footer

    private var footerView: some View {
        HStack(spacing: 0) {
            footerButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                label: isSaved ? "Saved" : "Save",
                tint: isSaved ? .purple : .primary
            ) {
                if reduceMotion {
                    isSaved.toggle()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isSaved.toggle()
                    }
                }
            }
            Divider().frame(height: 28)
            Text("Share and comments coming soon")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityLabel("Share and comments coming soon")
        }
        .padding(.vertical, 4)
        .background {
            if reduceTransparency {
                Color(uiColor: .secondarySystemBackground)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(Color.white.opacity(0.04)))
            }
        }
        .overlay(alignment: .top) {
            Divider().opacity(contrast == .increased ? 1 : 0.4)
        }
    }

    private func footerButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - FlowLayout (chip wrapping)

private struct ChurchNoteShareFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + (rows.last?.isEmpty == false ? spacing : 0) > availableWidth {
                rows.append([subview])
                currentRowWidth = size.width
            } else {
                rows[rows.count - 1].append(subview)
                currentRowWidth += size.width + (rows.last?.count ?? 0 > 1 ? spacing : 0)
            }
        }

        var totalHeight: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            totalHeight += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: availableWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + (rows.last?.isEmpty == false ? spacing : 0) > bounds.width {
                rows.append([subview])
                currentRowWidth = size.width
            } else {
                rows[rows.count - 1].append(subview)
                currentRowWidth += size.width + (rows.last?.count ?? 0 > 1 ? spacing : 0)
            }
        }

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}

// MARK: - Preview

#Preview("Church Note Share Card") {
    ScrollView {
        ChurchNoteShareCard(
            data: ChurchNoteShareCardData(
                id: "note-001",
                sermonTitle: "Walking in the Spirit: Bearing Fruit in Every Season",
                speakerName: "Pastor Marcus Williams",
                churchName: "Cornerstone Fellowship",
                date: "June 10, 2026",
                scriptureReferences: ["Galatians 5:22–23", "John 15:5", "Romans 8:11"],
                keyPoints: [
                    "The fruit of the Spirit is not a checklist but evidence of abiding in Christ.",
                    "Love is the root — all other fruits grow from it.",
                    "Seasons of pruning are necessary for greater fruitfulness."
                ],
                personalTakeaway: "I need to stop striving and start abiding. The pressure I feel to perform is not from God.",
                actionSteps: [
                    "Spend 10 minutes in silent prayer each morning this week.",
                    "Memorize Galatians 5:22–23.",
                    "Text one person you've been avoiding to reconcile."
                ],
                prayerPrompt: "Lord, teach me to abide in You so that Your fruit flows naturally from my life. Prune what needs pruning.",
                discussionQuestions: [
                    "Which fruit of the Spirit feels most lacking in your life right now?",
                    "What does it look like practically to 'abide in the vine' during a busy week?",
                    "Can you share a time when a season of pruning led to unexpected growth?"
                ],
                worshipPlaylistAttachmentID: "playlist-abc123",
                sermonAudioURL: nil,
                visibility: "public",
                createdAt: "2026-06-10T11:30:00Z"
            )
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
