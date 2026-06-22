// PostCardAuthorBylineView.swift
// AMENAPP
//
// Display-only author byline driven entirely by PostCardRenderModel.
// No action callbacks — tap handling stays in PostCard.
// Safe to use anywhere the author block needs to be rendered without card context.

import SwiftUI

// MARK: - PostCardAuthorBylineView

struct PostCardAuthorBylineView: View {
    let model: PostCardRenderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameRow
            subtitleRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Name row

    private var nameRow: some View {
        HStack(spacing: 8) {
            // Author name + verified badge
            HStack(spacing: 4) {
                Text(model.authorDisplayName)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if model.authorIsVerified {
                    VerifiedBadge(type: model.authorVerificationType, size: 14)
                        .accessibilityLabel("Verified \(model.authorVerificationType.rawValue)")
                }
            }
            .layoutPriority(-1)

            // Pinned indicator
            if model.isPinned {
                pinnedCapsule
            }

            // Category badge
            if model.category.showCategoryBadge {
                categoryCapsule
            }

            // AI content source label
            if let source = model.contentSource, !source.isEmpty {
                aiSourceCapsule(source: source)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Subtitle row (timestamp + edited + topic + AI usage)

    private var subtitleRow: some View {
        HStack(spacing: 6) {
            Text(model.timeAgoDisplay)
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .fixedSize()

            if model.wasEdited {
                Text("· Edited")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if let tag = model.topicTag, !tag.isEmpty {
                Text("•").foregroundStyle(.secondary)
                Text(tag)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }

            if let usage = model.aiUsage, usage.usedAI {
                PostAILabelPill(aiUsage: usage)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Badge helpers

    private var pinnedCapsule: some View {
        HStack(spacing: 3) {
            Image(systemName: "pin.fill")
                .font(.systemScaled(10, weight: .semibold))
                .accessibilityHidden(true)
            Text("Pinned")
                .font(AMENFont.bold(11))
        }
        .foregroundStyle(.gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.gray.opacity(0.15)))
        .fixedSize()
        .accessibilityLabel("Pinned post")
    }

    private var categoryCapsule: some View {
        Group {
            if !model.category.displayName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: model.category.icon)
                        .font(.systemScaled(10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(model.category.displayName)
                        .font(AMENFont.bold(11))
                }
                .foregroundStyle(model.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(model.category.color.opacity(0.15)))
                .fixedSize()
            }
        }
    }

    private func aiSourceCapsule(source: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.systemScaled(9, weight: .semibold))
                .accessibilityHidden(true)
            Text("via \(source)")
                .font(.systemScaled(10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.purple.opacity(0.8))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.8))
        .fixedSize()
        .accessibilityLabel("AI generated via \(source)")
    }
}
