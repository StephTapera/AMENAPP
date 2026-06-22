//
//  BereanPostContext.swift
//  AMENAPP
//
//  Canonical routing payload for the Berean post-analysis flow.
//

import Foundation

struct BereanPostContext: Codable, Hashable {
    static let notificationUserInfoKey = "bereanPostContext"
    static let legacyPostIDKey = "postID"

    let postId: String
    let authorId: String
    let authorName: String
    let previewText: String
    let category: String
    let verseReference: String?
    let isSensitive: Bool

    func refreshed(from post: Post) -> BereanPostContext {
        // H-19: Only include post content if the post has not been flagged for review
        // or removed by moderation. If moderation fields are set, withhold previewText.
        // Guarded by flaggedForReview + removed until Post gains a dedicated moderationStatus enum.
        let safePreview: String
        if post.removed || post.flaggedForReview {
            safePreview = ""
        } else {
            safePreview = String(post.content.prefix(200))
        }

        return BereanPostContext(
            postId: postId,
            authorId: post.authorId,
            authorName: post.authorName,
            previewText: safePreview,
            category: post.category.rawValue,
            verseReference: post.verseReference ?? verseReference,
            isSensitive: post.hasSensitiveContent
        )
    }

    var deepLinkPath: String {
        "amen://berean/post/\(postId)"
    }

    var initialPrompt: String {
        var parts: [String] = [
            "I'm reflecting on a \(category) post in AMEN.",
            "Post ID: \(postId)",
            "Author: \(authorName)"
        ]

        if let verseReference, !verseReference.isEmpty {
            parts.append("Attached verse: \(verseReference)")
        }

        // M-12: When isSensitive is true, only include the category rather than raw previewText
        // to avoid exposing sensitive post content to the LLM payload.
        let contextText = isSensitive
            ? "Category: \(category)"
            : "Post content: \(previewText)"

        if isSensitive {
            parts.append("This is a private or sensitive post. Do not reveal or quote hidden details. Offer a careful biblical reflection based only on the safe summary.")
        }

        parts.append(contextText)
        parts.append("Help me understand what stands out spiritually, what scripture themes connect, and one wise next question to ask.")

        return parts.joined(separator: "\n")
    }

    var userInfo: [String: Any] {
        [
            Self.notificationUserInfoKey: [
                "postId": postId,
                "authorId": authorId,
                "authorName": authorName,
                "previewText": previewText,
                "category": category,
                "verseReference": verseReference as Any,
                "isSensitive": isSensitive,
            ],
            Self.legacyPostIDKey: postId,
        ]
    }

    init(
        postId: String,
        authorId: String,
        authorName: String,
        previewText: String,
        category: String,
        verseReference: String?,
        isSensitive: Bool
    ) {
        self.postId = postId
        self.authorId = authorId
        self.authorName = authorName
        self.previewText = previewText
        self.category = category
        self.verseReference = verseReference
        self.isSensitive = isSensitive
    }

    init?(userInfo: [AnyHashable: Any]) {
        if let raw = userInfo[Self.notificationUserInfoKey] as? [String: Any],
           let postId = raw["postId"] as? String {
            self.postId = postId
            self.authorId = raw["authorId"] as? String ?? ""
            self.authorName = raw["authorName"] as? String ?? "Unknown"
            self.previewText = raw["previewText"] as? String ?? "Open this post in Berean."
            self.category = raw["category"] as? String ?? "post"
            self.verseReference = raw["verseReference"] as? String
            self.isSensitive = raw["isSensitive"] as? Bool ?? false
            return
        }

        if let postId = userInfo[Self.legacyPostIDKey] as? String {
            self.postId = postId
            self.authorId = ""
            self.authorName = "Unknown"
            self.previewText = "Open this post in Berean."
            self.category = "post"
            self.verseReference = nil
            self.isSensitive = false
            return
        }

        return nil
    }
}
