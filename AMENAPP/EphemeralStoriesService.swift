//
//  EphemeralStoriesService.swift
//  AMENAPP
//
//  Feature 21: Daily Devotional Stories — 24-hour ephemeral content.
//  Scripture reflections, prayer prompts, worship moments that disappear.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class EphemeralStoriesService: ObservableObject {
    static let shared = EphemeralStoriesService()

    @Published var activeStories: [StoryGroup] = []
    @Published var myStory: [StoryItem] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let collection = "stories"
    private let ttl: TimeInterval = 86400 // 24 hours

    private init() {}

    // MARK: - Models

    struct StoryItem: Identifiable, Codable {
        var id: String
        let authorId: String
        let authorName: String
        let authorProfileImageURL: String?
        let contentType: StoryContentType
        let text: String?
        let imageURL: String?
        let verseReference: String?
        let verseText: String?
        let backgroundColor: String? // hex
        let createdAt: Date
        var viewedBy: [String]
        var expiresAt: Date

        var isExpired: Bool { Date() > expiresAt }
    }

    enum StoryContentType: String, Codable {
        case text          // Plain text on colored background
        case scripture     // Bible verse with reflection
        case prayerPrompt  // Prayer prompt card
        case photo         // Image with optional caption
        case worship       // Worship moment (song + caption)
    }

    struct StoryGroup: Identifiable {
        let id: String // authorId
        let authorName: String
        let authorProfileImageURL: String?
        let stories: [StoryItem]
        let hasUnviewed: Bool
    }

    // MARK: - Create Story

    func createStory(
        contentType: StoryContentType,
        text: String? = nil,
        imageURL: String? = nil,
        verseReference: String? = nil,
        verseText: String? = nil,
        backgroundColor: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let user = UserService.shared.currentUser

        let story = StoryItem(
            id: UUID().uuidString,
            authorId: uid,
            authorName: user?.displayName ?? "You",
            authorProfileImageURL: user?.profileImageURL,
            contentType: contentType,
            text: text,
            imageURL: imageURL,
            verseReference: verseReference,
            verseText: verseText,
            backgroundColor: backgroundColor,
            createdAt: Date(),
            viewedBy: [],
            expiresAt: Date().addingTimeInterval(ttl)
        )

        try await db.collection(collection).document(story.id).setData([
            "id": story.id,
            "authorId": story.authorId,
            "authorName": story.authorName,
            "authorProfileImageURL": story.authorProfileImageURL as Any,
            "contentType": story.contentType.rawValue,
            "text": story.text as Any,
            "imageURL": story.imageURL as Any,
            "verseReference": story.verseReference as Any,
            "verseText": story.verseText as Any,
            "backgroundColor": story.backgroundColor as Any,
            "createdAt": Timestamp(date: story.createdAt),
            "viewedBy": [],
            "expiresAt": Timestamp(date: story.expiresAt),
        ])
    }

    // MARK: - Fetch Stories

    func fetchActiveStories() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        defer { isLoading = false }

        let now = Timestamp(date: Date())

        guard let snapshot = try? await db.collection(collection)
            .whereField("expiresAt", isGreaterThan: now)
            .order(by: "expiresAt", descending: false)
            .limit(to: 100)
            .getDocuments() else { return }

        var grouped: [String: [StoryItem]] = [:]

        for doc in snapshot.documents {
            let data = doc.data()
            guard let authorId = data["authorId"] as? String,
                  let createdTs = data["createdAt"] as? Timestamp,
                  let expiresTs = data["expiresAt"] as? Timestamp else { continue }

            let item = StoryItem(
                id: doc.documentID,
                authorId: authorId,
                authorName: data["authorName"] as? String ?? "Unknown",
                authorProfileImageURL: data["authorProfileImageURL"] as? String,
                contentType: StoryContentType(rawValue: data["contentType"] as? String ?? "text") ?? .text,
                text: data["text"] as? String,
                imageURL: data["imageURL"] as? String,
                verseReference: data["verseReference"] as? String,
                verseText: data["verseText"] as? String,
                backgroundColor: data["backgroundColor"] as? String,
                createdAt: createdTs.dateValue(),
                viewedBy: data["viewedBy"] as? [String] ?? [],
                expiresAt: expiresTs.dateValue()
            )

            grouped[authorId, default: []].append(item)
        }

        // Build story groups
        activeStories = grouped.map { authorId, stories in
            let hasUnviewed = stories.contains { !$0.viewedBy.contains(uid) }
            return StoryGroup(
                id: authorId,
                authorName: stories.first?.authorName ?? "Unknown",
                authorProfileImageURL: stories.first?.authorProfileImageURL,
                stories: stories.sorted { $0.createdAt < $1.createdAt },
                hasUnviewed: hasUnviewed
            )
        }.sorted { $0.hasUnviewed && !$1.hasUnviewed }

        // Separate own stories
        myStory = grouped[uid] ?? []
    }

    // MARK: - Mark as Viewed

    func markViewed(storyId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection(collection).document(storyId).updateData([
            "viewedBy": FieldValue.arrayUnion([uid]),
        ])
    }
}
