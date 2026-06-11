// ChurchNoteSharePreviewCard.swift
// AMENAPP
//
// Visibility-safe post card preview for a ChurchNoteV2.
// Only renders blocks marked .shareable or .selectedForPostPreview.
// Never exposes .privateOnly blocks, even if called incorrectly.
// Used in: post creation composer, share sheet preview, post card in feed.

import SwiftUI
import UIKit

// MARK: - Share Preview Card (async-loading, feed-ready)

struct ChurchNoteSharePreviewCard: View {

    let noteId: String
    let noteTitle: String?
    let churchName: String?

    @State private var shareableBlocks: [ChurchNoteBlockV2] = []
    @State private var isLoading = true
    @State private var isCreatingShare = false
    @State private var shareStatusMessage: String?

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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.68))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
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
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ChurchNotesDesignTokens.Colors.personalTint, in: Circle())
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
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Scripture", systemImage: "book.closed")
                Label("Music", systemImage: "music.note")
                Spacer()
                Text("Private blocks hidden")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)

            if AMENFeatureFlags.shared.noteShareViewerEnabled {
                Button {
                    createPreviewLink()
                } label: {
                    Label(isCreatingShare ? "Preparing" : "Copy smart note link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isCreatingShare || shareableBlocks.isEmpty)
            }

            if let shareStatusMessage {
                Text(shareStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func createPreviewLink() {
        guard !isCreatingShare else { return }
        isCreatingShare = true
        shareStatusMessage = nil
        Task {
            defer { isCreatingShare = false }
            do {
                let policy = NoteShareAccessPolicy(
                    audience: .publicLink,
                    signedOutAccess: .denied,
                    followerPolicy: .disabled,
                    requiresAuth: true,
                    allowExternalIndexing: false
                )
                let result = try await NoteShareService.shared.createShare(
                    noteId: noteId,
                    selectedBlockIds: shareableBlocks.map(\.id),
                    accessPolicy: policy
                )
                let url = result.linkToken.map { "\(result.webFallbackPath)?token=\($0)" } ?? result.webFallbackPath
                UIPasteboard.general.string = url
                shareStatusMessage = "Smart note link copied"
            } catch {
                shareStatusMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Share Preview Block Row (compact, safe renderer)

struct SharePreviewBlockRow: View {

    let block: ChurchNoteBlockV2

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(ChurchNotesDesignTokens.Colors.personalTint, in: Circle())
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }
}
