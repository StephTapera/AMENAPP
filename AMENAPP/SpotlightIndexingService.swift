//
//  SpotlightIndexingService.swift
//  AMENAPP
//
//  CoreSpotlight indexing for posts, prayers, and church notes
//  so they appear in iOS Spotlight search.
//

import Foundation
import CoreSpotlight
import MobileCoreServices
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SpotlightIndexingService {
    static let shared = SpotlightIndexingService()
    private let searchableIndex = CSSearchableIndex.default()
    private init() {}

    // MARK: - Visibility Guard

    /// Returns true only when a post is safe to expose in iOS Spotlight.
    /// Conditions that block indexing:
    ///   • visibility is not `.everyone` (followers-only or community-only posts stay private)
    ///   • category is `.prayer` (prayer requests are personal and must not leak)
    ///   • `removed` flag is set (moderation-removed content must never surface)
    private func isSpotlightIndexable(_ post: Post) -> Bool {
        guard post.visibility == .everyone else { return false }
        guard post.category != .prayer else { return false }
        guard !post.removed else { return false }
        return true
    }

    // MARK: - Index Posts

    func indexPost(_ post: Post) {
        // Security guard: only index publicly visible, non-removed, non-prayer posts.
        guard isSpotlightIndexable(post) else {
            // If the post was previously indexed but no longer qualifies, remove it.
            deindexPost(postId: post.firebaseId ?? post.id.uuidString)
            return
        }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = "\(post.authorName)'s \(post.category.rawValue.capitalized)"
        attributeSet.contentDescription = String(post.content.prefix(200))
        attributeSet.keywords = buildKeywords(for: post)
        attributeSet.creator = post.authorName
        attributeSet.contentCreationDate = post.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: "post_\(post.firebaseId ?? post.id.uuidString)",
            domainIdentifier: "com.amenapp.posts",
            attributeSet: attributeSet
        )
        item.expirationDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())

        searchableIndex.indexSearchableItems([item])
    }

    func indexPosts(_ posts: [Post]) {
        // Filter to only spotlight-eligible posts before building any CSSearchableItem.
        let eligible = posts.filter { isSpotlightIndexable($0) }

        // De-index any posts in the batch that failed the guard (e.g. since-removed posts).
        let ineligibleIds = posts
            .filter { !isSpotlightIndexable($0) }
            .map { "post_\($0.firebaseId ?? $0.id.uuidString)" }
        if !ineligibleIds.isEmpty {
            searchableIndex.deleteSearchableItems(withIdentifiers: ineligibleIds)
        }

        guard !eligible.isEmpty else { return }

        let items = eligible.map { post -> CSSearchableItem in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = "\(post.authorName)'s \(post.category.rawValue.capitalized)"
            attributeSet.contentDescription = String(post.content.prefix(200))
            attributeSet.keywords = buildKeywords(for: post)
            attributeSet.creator = post.authorName
            attributeSet.contentCreationDate = post.createdAt

            let item = CSSearchableItem(
                uniqueIdentifier: "post_\(post.firebaseId ?? post.id.uuidString)",
                domainIdentifier: "com.amenapp.posts",
                attributeSet: attributeSet
            )
            item.expirationDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())
            return item
        }

        searchableIndex.indexSearchableItems(items)
    }

    // MARK: - Index Church Notes

    func indexChurchNote(id: String, title: String, content: String, churchName: String?, date: Date) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title.isEmpty ? "Church Notes" : title
        attributeSet.contentDescription = String(content.prefix(300))
        attributeSet.keywords = ["church", "notes", "sermon"]
        if let church = churchName {
            attributeSet.keywords?.append(church)
        }
        attributeSet.contentCreationDate = date

        let item = CSSearchableItem(
            uniqueIdentifier: "churchnote_\(id)",
            domainIdentifier: "com.amenapp.churchnotes",
            attributeSet: attributeSet
        )

        searchableIndex.indexSearchableItems([item])
    }

    // MARK: - Index Saved Posts

    func indexSavedPost(_ post: Post) {
        // Security guard: apply the same visibility/removal/category rules for saved posts.
        guard isSpotlightIndexable(post) else {
            removeSavedPost(post.firebaseId ?? post.id.uuidString)
            return
        }

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = "Saved: \(post.authorName)'s Post"
        attributeSet.contentDescription = String(post.content.prefix(200))
        attributeSet.keywords = ["saved", "bookmark"] + buildKeywords(for: post)
        attributeSet.contentCreationDate = post.createdAt

        let item = CSSearchableItem(
            uniqueIdentifier: "saved_\(post.firebaseId ?? post.id.uuidString)",
            domainIdentifier: "com.amenapp.saved",
            attributeSet: attributeSet
        )

        searchableIndex.indexSearchableItems([item])
    }

    // MARK: - Remove

    func removePost(_ postId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["post_\(postId)"])
    }

    func removeSavedPost(_ postId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["saved_\(postId)"])
    }

    func removeAllItems() {
        searchableIndex.deleteAllSearchableItems()
    }

    /// De-indexes a post from Spotlight by its Firebase or UUID identifier.
    /// Call this whenever a post is deleted, removed by moderation, or its
    /// visibility is changed away from `.everyone`.
    func deindexPost(postId: String) {
        searchableIndex.deleteSearchableItems(withIdentifiers: [
            "post_\(postId)",
            "saved_\(postId)"
        ])
    }

    // MARK: - Handle Spotlight Launch

    /// Call from AppDelegate/SceneDelegate when user taps a Spotlight result
    func handleSpotlightActivity(_ activity: NSUserActivity) -> (type: String, id: String)? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }

        if identifier.hasPrefix("post_") {
            return ("post", String(identifier.dropFirst(5)))
        } else if identifier.hasPrefix("churchnote_") {
            return ("churchnote", String(identifier.dropFirst(11)))
        } else if identifier.hasPrefix("saved_") {
            return ("saved", String(identifier.dropFirst(6)))
        }

        return nil
    }

    // MARK: - Helpers

    private func buildKeywords(for post: Post) -> [String] {
        var keywords: [String] = [post.category.rawValue, "amen", "faith"]
        if let topic = post.topicTag {
            keywords.append(topic)
        }
        // Add first few meaningful words
        let words = post.content.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
            .prefix(5)
        keywords.append(contentsOf: words)
        return keywords
    }
}
