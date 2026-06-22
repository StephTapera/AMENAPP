// TopicModerationFilter.swift
// AMENAPP
//
// Filters topic feed results to exclude blocked, muted, flagged,
// and removed posts. Reuses existing BlockService and moderation metadata.

import Foundation

@MainActor
final class TopicModerationFilter {

    static let shared = TopicModerationFilter()

    private init() {}

    // MARK: - Public API

    /// Filter an array of posts for topic feed display.
    /// Removes:
    ///   - Posts by blocked users (in either direction)
    ///   - Posts flagged for review / removed by moderation
    ///   - Posts with sensitive content (unless user opts in)
    func filter(posts: [Post], showSensitive: Bool = false) -> [Post] {
        let blockedIds = BlockService.shared.blockedUsers

        return posts.filter { post in
            // Exclude posts by blocked users
            guard !blockedIds.contains(post.authorId) else { return false }

            // Exclude removed / under-review posts
            guard !post.removed else { return false }
            guard !post.flaggedForReview else { return false }

            // Exclude sensitive content unless opted in
            if post.hasSensitiveContent && !showSensitive {
                return false
            }

            return true
        }
    }
}
