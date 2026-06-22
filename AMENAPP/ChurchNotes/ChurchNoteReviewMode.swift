//
//  ChurchNoteReviewMode.swift
//  AMENAPP
//
//  Review mode view with filters, summary counts, and scannable rendering.
//  Same data source as edit mode (blocks + richContentJSON).
//

import SwiftUI

struct ChurchNoteReviewMode: View {
    let attributedText: NSAttributedString
    let blocks: [ChurchNoteBlock]
    let tags: [String]

    @State private var activeFilter: ReviewFilter = .all

    enum ReviewFilter: String, CaseIterable, Identifiable {
        case all, highlights, prayers, actions, scriptures, quotes

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .highlights: return "Highlights"
            case .prayers: return "Prayers"
            case .actions: return "Actions"
            case .scriptures: return "Scriptures"
            case .quotes: return "Quotes"
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .highlights: return "highlighter"
            case .prayers: return "hands.sparkles"
            case .actions: return "checkmark.circle"
            case .scriptures: return "book"
            case .quotes: return "quote.opening"
            }
        }
    }

    // MARK: - Computed Counts

    private var highlightCount: Int {
        var count = 0
        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.backgroundColor, in: fullRange, options: []) { val, _, _ in
            if val != nil { count += 1 }
        }
        return count
    }

    private var prayerCount: Int { blocks.filter { $0.type == .prayer }.count }
    private var actionCount: Int { blocks.filter { $0.type == .action }.count }
    private var scriptureCount: Int { blocks.filter { $0.type == .scripture }.count }
    private var quoteCount: Int { blocks.filter { $0.type == .quote }.count }
    private var takeawayCount: Int { blocks.filter { $0.type == .takeaway }.count }

    private var filteredBlocks: [ChurchNoteBlock] {
        switch activeFilter {
        case .all: return blocks
        case .highlights: return blocks.filter { $0.highlight != nil }
        case .prayers: return blocks.filter { $0.type == .prayer }
        case .actions: return blocks.filter { $0.type == .action }
        case .scriptures: return blocks.filter { $0.type == .scripture }
        case .quotes: return blocks.filter { $0.type == .quote }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary card
            summaryCard

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ReviewFilter.allCases) { filter in
                        filterPill(filter)
                    }
                }
            }

            // Content
            if activeFilter == .all {
                // Full note text with enhanced highlights
                richTextPreview
            }

            // Blocks
            if !filteredBlocks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(filteredBlocks) { block in
                        reviewBlockCard(block)
                    }
                }
            } else if activeFilter != .all {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: activeFilter.icon)
                            .font(.systemScaled(24))
                            .foregroundStyle(.quaternary)
                        Text("No \(activeFilter.label.lowercased()) yet")
                            .font(.systemScaled(13))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            }

            // Tags
            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TAGS")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)

                    TagWrapLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.7))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemBackground).opacity(0.85))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
                                )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryItem(count: highlightCount, label: "Highlights", icon: "highlighter")
            summaryItem(count: prayerCount, label: "Prayers", icon: "hands.sparkles")
            summaryItem(count: actionCount, label: "Actions", icon: "checkmark.circle")
            summaryItem(count: scriptureCount, label: "Scriptures", icon: "book")
            summaryItem(count: quoteCount + takeawayCount, label: "Notes", icon: "lightbulb")
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func summaryItem(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.systemScaled(12))
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .font(.systemScaled(16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.systemScaled(9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter Pill

    private func filterPill(_ filter: ReviewFilter) -> some View {
        Button {
            withAnimation(CNToken.Anim.quickTap) {
                activeFilter = filter
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.systemScaled(10))
                Text(filter.label)
                    .font(.systemScaled(12, weight: .medium))
            }
            .foregroundStyle(activeFilter == filter ? Color.primary : Color.secondary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(activeFilter == filter ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(activeFilter == filter ? 0.12 : 0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rich Text Preview

    private var richTextPreview: some View {
        Group {
            if attributedText.length > 0 {
                AttributedTextView(attributedText: attributedText)
                    .frame(minHeight: 60)
            } else {
                Text("No content yet")
                    .font(.systemScaled(14))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Review Block Card

    private func reviewBlockCard(_ block: ChurchNoteBlock) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CNToken.BlockBorder.color(for: block.type))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: block.type.icon)
                        .font(.systemScaled(10, weight: .medium))
                        .foregroundStyle(CNToken.BlockBorder.color(for: block.type))
                    Text(block.type.displayName)
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Text(block.text)
                    .font(.systemScaled(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(CNToken.Radius.block), style: .continuous)
                .fill(CNToken.BlockTint.tint(for: block.type).opacity(1.0 + CNToken.Review.highlightBoost))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(CNToken.Radius.block), style: .continuous)
                .strokeBorder(CNToken.BlockBorder.color(for: block.type).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Attributed Text View (read-only renderer for review mode)

private struct AttributedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.attributedText = attributedText
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.attributedText = attributedText
    }
}
