//
//  SpotlightIndexingService.swift
//  AMENAPP
//
//  CoreSpotlight indexing for posts and church notes so they appear
//  in iOS Spotlight search.
//
//  PRIVACY INVARIANT: Prayer content is NEVER donated to Spotlight.
//  Prayer posts are deeply personal and must not be readable by
//  the OS indexing pipeline or Siri ML. Only public (non-prayer) posts
//  are eligible for indexing.
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

    // UserDefaults key used to run the one-time prayer-purge migration.
    private static let prayerPurgeKey = "spotlight_prayer_purge_v1_complete"

    private init() {
        runPrayerPurgeMigrationIfNeeded()
    }

    // MARK: - One-time Migration: purge any previously indexed prayer items

    /// Deletes the "com.amenapp.prayers" domain if it was ever populated by an
    /// earlier build. Runs once per install; result is recorded in UserDefaults.
    private func runPrayerPurgeMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.prayerPurgeKey) else { return }
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: ["com.amenapp.prayers"]) { _ in }
        UserDefaults.standard.set(true, forKey: Self.prayerPurgeKey)
    }

    // MARK: - Index Posts

    func indexPost(_ post: Post) {
        // PRIVACY: never donate prayer content to Spotlight.
        guard post.category != .prayer else { return }

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
        // PRIVACY: filter out prayer posts before any indexing occurs.
        let eligible = posts.filter { $0.category != .prayer }
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
        // PRIVACY: never donate prayer content to Spotlight, even when saved.
        guard post.category != .prayer else { return }

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
