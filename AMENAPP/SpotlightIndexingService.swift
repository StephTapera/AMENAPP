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

    // MARK: - Index Posts

    func indexPost(_ post: Post) {
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
        let items = posts.map { post -> CSSearchableItem in
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
