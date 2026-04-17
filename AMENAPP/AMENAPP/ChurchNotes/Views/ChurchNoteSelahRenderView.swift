// ChurchNoteSelahRenderView.swift
// AMENAPP
//
// Selah surface for a ChurchNoteV2 — calm, reflection-focused rendering.
// Shows blocks filtered by semantic type with a recap strip at the top.
// Private-only blocks are shown with a lock badge (not hidden) in Selah,
// because this is a personal reflection space — the owner's view.

import SwiftUI

// MARK: - Selah Filter

enum SelahNoteFilter: String, CaseIterable, Identifiable {
    case all
    case insights          // keyTruth, verseInsight
    case prayers           // prayerPoint
    case actions           // actionStep
    case questions         // question
    case pinned            // any pinned block

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:       return "All"
        case .insights:  return "Insights"
        case .prayers:   return "Prayers"
        case .actions:   return "Actions"
        case .questions: return "Questions"
        case .pinned:    return "Pinned"
        }
    }

    var icon: String {
        switch self {
        case .all:       return "rectangle.grid.1x2"
        case .insights:  return "lightbulb.fill"
        case .prayers:   return "hands.sparkles.fill"
        case .actions:   return "checkmark.circle.fill"
        case .questions: return "questionmark.circle"
        case .pinned:    return "pin.fill"
        }
    }

    func matches(_ block: ChurchNoteBlockV2) -> Bool {
        switch self {
        case .all:       return true
        case .insights:  return [.keyTruth, .verseInsight].contains(block.semanticType) || block.type == .verseEmbed
        case .prayers:   return block.semanticType == .prayerPoint || block.type == .prayer
        case .actions:   return block.semanticType == .actionStep || block.type == .action || block.type == .checklist
        case .questions: return block.semanticType == .question
        case .pinned:    return block.pinnedState != .none
        }
    }

    private func contains<T: Equatable>(_ value: T, in arr: [T]) -> Bool {
        arr.contains(value)
    }
}

// MARK: - View

struct ChurchNoteSelahRenderView: View {

    let noteId: String
    @Environment(\.dismiss) private var dismiss

    @State private var blocks: [ChurchNoteBlockV2] = []
    @State private var isLoading = true
    @State private var activeFilter: SelahNoteFilter = .all

    private var filtered: [ChurchNoteBlockV2] {
        blocks.filter { activeFilter.matches($0) }
    }

    private var actionItems: [ChurchNoteBlockV2] {
        blocks.filter { $0.semanticType == .actionStep || $0.type == .action || $0.type == .checklist }
    }

    private var prayerItems: [ChurchNoteBlockV2] {
        blocks.filter { $0.semanticType == .prayerPoint || $0.type == .prayer }
    }

    private var keyInsights: [ChurchNoteBlockV2] {
        blocks.filter { $0.semanticType == .keyTruth || $0.type == .takeaway }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else {
                        recapStrip
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        filterBar
                            .padding(.horizontal, 16)

                        if filtered.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(filtered) { block in
                                    SelahBlockCard(block: block)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Selah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadBlocks()
            }
        }
    }

    // MARK: - Recap Strip

    private var recapStrip: some View {
        HStack(spacing: 0) {
            recapStat(count: keyInsights.count, label: "Insight", icon: "lightbulb.fill", color: Color(hex: "F4C430"))
            Divider().frame(height: 30)
            recapStat(count: prayerItems.count, label: "Prayer", icon: "hands.sparkles.fill", color: Color(hex: "E8A0A8"))
            Divider().frame(height: 30)
            recapStat(count: actionItems.count, label: "Action", icon: "checkmark.circle.fill", color: Color(hex: "7DBD8A"))
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func recapStat(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label) block\(count == 1 ? "" : "s")")
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SelahNoteFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func filterChip(_ filter: SelahNoteFilter) -> some View {
        let selected = activeFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeFilter = filter
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(filter.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Color.primary : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No blocks match this filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Load

    private func loadBlocks() async {
        blocks = await ChurchNoteBlockRepository.shared.selahBlocks(noteId: noteId)
        isLoading = false
    }
}

// MARK: - Selah Block Card

struct SelahBlockCard: View {

    let block: ChurchNoteBlockV2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: block.semanticType.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(block.semanticType.accentColor)
                    .accessibilityHidden(true)
                Text(block.semanticType.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(block.semanticType.accentColor)
                    .textCase(.uppercase)
                Spacer()
                if block.pinnedState != .none {
                    Image(systemName: block.pinnedState.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(block.pinnedState.displayName)
                }
                if block.visibility == .privateOnly {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .accessibilityLabel("Private block")
                }
            }

            blockBody

            if let payload = block.versePayload, !payload.reference.isEmpty {
                Text(payload.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            block.semanticType.accentColor.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(block.semanticType.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var blockBody: some View {
        if block.type == .verseEmbed, let payload = block.versePayload {
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.verseText.isEmpty ? payload.reference : payload.verseText)
                    .font(.body)
                    .italic()
                    .foregroundStyle(.primary)
                if let commentary = payload.commentary, !commentary.isEmpty {
                    Text(commentary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else if block.type == .callout, let style = block.calloutPayload?.style {
            VStack(alignment: .leading, spacing: 4) {
                if let prompt = block.calloutPayload?.prompt, !prompt.isEmpty, block.text.isEmpty {
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text(block.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            .padding(10)
            .background(style.fillColor, in: RoundedRectangle(cornerRadius: 10))
        } else if block.type == .checklist, let payload = block.checklistPayload {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(payload.items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.completed ? .primary : Color(.tertiaryLabel))
                            .font(.system(size: 15))
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(.subheadline)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? .secondary : .primary)
                    }
                }
            }
        } else {
            Text(block.text.isEmpty ? "—" : block.text)
                .font(.body)
                .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


