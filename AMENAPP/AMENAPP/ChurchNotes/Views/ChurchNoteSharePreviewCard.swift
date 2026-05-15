// ChurchNoteSharePreviewCard.swift
// AMENAPP
//
// Visibility-safe post card preview for a ChurchNoteV2.
// Only renders blocks marked .shareable or .selectedForPostPreview.
// Never exposes .privateOnly blocks, even if called incorrectly.
// Used in: post creation composer, share sheet preview, post card in feed.

import SwiftUI

// MARK: - Share Preview Card (async-loading, feed-ready)

struct ChurchNoteSharePreviewCard: View {

    let noteId: String
    let noteTitle: String?
    let churchName: String?

    @State private var shareableBlocks: [ChurchNoteBlockV2] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else if shareableBlocks.isEmpty {
                noShareableBlocksState
            } else {
                blockList
            }
            cardFooter
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .task {
            shareableBlocks = await ChurchNoteBlockRepository.shared.shareableBlocks(noteId: noteId)
            isLoading = false
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(noteTitle ?? "Church Note")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let church = churchName {
                    Text(church)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Block List (capped at 4 for preview)

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 14)

            ForEach(shareableBlocks.prefix(4)) { block in
                SharePreviewBlockRow(block: block)
                    .padding(.horizontal, 14)
            }

            if shareableBlocks.count > 4 {
                Text("+ \(shareableBlocks.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Empty State

    private var noShareableBlocksState: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("No shareable blocks selected")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var cardFooter: some View {
        HStack {
            Image(systemName: "app.badge.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("AMEN Notes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - Share Preview Block Row (compact, safe renderer)

struct SharePreviewBlockRow: View {

    let block: ChurchNoteBlockV2

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left semantic accent line
            Rectangle()
                .fill(block.semanticType.accentColor.opacity(0.5))
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                if block.type == .verseEmbed, let payload = block.versePayload {
                    Text(payload.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(block.semanticType.accentColor)
                    Text(payload.verseText.isEmpty ? payload.reference : payload.verseText)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                } else if block.type == .callout, let style = block.calloutPayload?.style {
                    Text(style.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(style.borderColor)
                    Text(block.text.isEmpty ? (block.calloutPayload?.prompt ?? "") : block.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                } else if block.type == .checklist, let payload = block.checklistPayload {
                    Text(payload.category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(payload.items.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(item.completed ? .primary : Color(.tertiaryLabel))
                                .accessibilityHidden(true)
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(item.completed ? .secondary : .primary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    if block.type != .paragraph {
                        Text(block.type.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(block.semanticType.accentColor)
                    }
                    Text(block.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }
        }
    }
}

// MARK: - Inline post card preview (used when composing a post)

struct ChurchNoteInlineAttachment: View {

    let note: ChurchNoteV2
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Church Note" : note.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(note.blockCount) block\(note.blockCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove note attachment")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}


