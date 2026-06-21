// SmartCommentCard.swift
// AMENAPP — Smart Comments Wave 1
//
// Renders a single SmartComment. Opaque white card — NO glass behind text
// (no-glass-on-glass rule). Glass pills are used only for floating reaction controls.
//
// INVARIANT: This view never renders a hidden/blocked comment directly.
//            SmartCommentsSheet must filter via visibleComments() before passing here.

import SwiftUI
import Foundation
import UIKit

struct SmartCommentCard: View {

    let comment: SmartComment

    /// When true, shows a calm "Pending safety review" caption beneath the body.
    /// Non-punitive — the user knows their comment is being reviewed, not rejected.
    var isPending: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: avatar + author name + timestamp
            HStack(alignment: .top, spacing: 10) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(authorDisplayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(relativeTimestamp)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    // Body text
                    Text(comment.body)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Scripture chip — shown when a bible verse or reference is detected
            if let scriptureEntity = scriptureEntity {
                ScriptureChipView(entity: scriptureEntity)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            // Pending caption — calm, non-punitive
            if isPending || comment.moderationStatus == .pendingReview {
                Text("Pending safety review")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            // Reaction pills
            if !reactionSummaries.isEmpty {
                HStack(spacing: 8) {
                    ForEach(reactionSummaries, id: \.kind) { summary in
                        ReactionPillView(summary: summary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer().frame(height: 14)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Card Background

    /// Opaque white background — no glass behind comment text.
    /// Reduce-transparency fallback: solid systemBackground in both modes.
    @ViewBuilder
    private var cardBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 36, height: 36)
            .overlay(
                Text(avatarInitials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    // MARK: - Computed Properties

    private var avatarInitials: String {
        // userId is the only identifier we have in SmartComment; use its prefix as fallback.
        let prefix = String(comment.userId.prefix(2)).uppercased()
        return prefix.isEmpty ? "??" : prefix
    }

    private var authorDisplayName: String {
        // SmartComment doesn't carry a display name — the mapping layer strips it for privacy.
        // Show the userId prefix as a handle. Wave 2 will resolve display names.
        "User"
    }

    private var relativeTimestamp: String {
        let date = Date(timeIntervalSince1970: comment.createdAt)
        return date.timeAgoDisplay()
    }

    /// The first scripture entity detected in this comment, if any.
    private var scriptureEntity: DetectedEntity? {
        guard AMENFeatureFlags.shared.commentEntityDetectionEnabled else { return nil }
        return comment.detectedEntities.first {
            $0.kind == .bibleVerse || $0.kind == .bibleReference
        }
    }

    /// Aggregated reaction counts per kind.
    private var reactionSummaries: [ReactionSummary] {
        var counts: [CommentReactionKind: Int] = [:]
        for reaction in comment.reactions {
            counts[reaction.kind, default: 0] += 1
        }
        return counts
            .filter { $0.value > 0 }
            .map { ReactionSummary(kind: $0.key, count: $0.value) }
            .sorted { $0.kind.sortPriority < $1.kind.sortPriority }
    }
}

// MARK: - Supporting Types

private struct ReactionSummary {
    let kind: CommentReactionKind
    let count: Int
}

private extension CommentReactionKind {
    var sortPriority: Int {
        switch self {
        case .amen:      return 0
        case .pray:      return 1
        case .testimony: return 2
        case .save:      return 3
        }
    }

    var sfSymbol: String {
        switch self {
        case .amen:      return "hands.clap.fill"
        case .pray:      return "hands.and.sparkles.fill"
        case .testimony: return "quote.bubble.fill"
        case .save:      return "bookmark.fill"
        }
    }

    var label: String {
        switch self {
        case .amen:      return "Amen"
        case .pray:      return "Pray"
        case .testimony: return "Testimony"
        case .save:      return "Save"
        }
    }
}

// MARK: - Reaction Pill

private struct ReactionPillView: View {
    let summary: ReactionSummary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: summary.kind.sfSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
            Text("\(summary.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var pillBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemGray5)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Scripture Chip

/// Small inline chip showing the detected scripture reference.
/// Full preview card with verse text is Wave 3.
private struct ScriptureChipView: View {
    let entity: DetectedEntity

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "book.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue.opacity(0.8))
            Text(entity.rawText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.5)
                )
        )
    }
}
