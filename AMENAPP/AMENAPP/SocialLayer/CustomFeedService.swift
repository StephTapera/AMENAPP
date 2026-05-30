// CustomFeedService.swift
// AMENAPP — SocialLayer
//
// Firestore-backed CRUD + reorder service for CustomFeedConfig.
// Contract types (CustomFeedConfig, CustomFeedSlot) live in ComposerContract.swift.
// Do NOT redefine those here.
//
// Firestore paths:
//   User feeds:   customFeeds/{userId}/feeds/{feedId}
//   Sort field:   sortOrder: Int
//
// All writes use merge: true for idempotency.

import Foundation
import FirebaseFirestore

// MARK: - CustomFeedService

@MainActor
final class CustomFeedService: ObservableObject {

    // MARK: Singleton

    static let shared = CustomFeedService()

    // MARK: Published state

    @Published var feeds: [CustomFeedConfig] = []
    @Published var isLoading = false

    // MARK: Private

    private var listenerRegistration: ListenerRegistration?
    private var currentUserId: String?

    private init() {}

    // MARK: - Collection reference helper

    private func feedsCollection(userId: String) -> CollectionReference {
        FirebaseManager.shared.firestore
            .collection("customFeeds")
            .document(userId)
            .collection("feeds")
    }

    // MARK: - Load (snapshot listener)

    /// Attaches a real-time Firestore listener ordered by `sortOrder`.
    /// Removes any existing listener before attaching a new one.
    /// Deduplicates rows on each snapshot using `id`.
    func loadFeeds(userId: String) async {
        // Detach stale listener if userId changed
        if userId != currentUserId {
            listenerRegistration?.remove()
            listenerRegistration = nil
        }
        currentUserId = userId

        guard listenerRegistration == nil else { return }

        isLoading = true

        listenerRegistration = feedsCollection(userId: userId)
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    print("[CustomFeedService] Listener error: \(error.localizedDescription)")
                    return
                }

                guard let docs = snapshot?.documents else { return }

                var seen = Set<UUID>()
                var parsed: [CustomFeedConfig] = []

                for doc in docs {
                    guard var config = Self.decode(doc) else { continue }
                    // Preserve firestoreId from document ID
                    if config.firestoreId == nil {
                        config.firestoreId = doc.documentID
                    }
                    guard !seen.contains(config.id) else { continue }
                    seen.insert(config.id)
                    parsed.append(config)
                }

                self.feeds = parsed
            }
    }

    // MARK: - Stop listening

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        currentUserId = nil
    }

    // MARK: - Create

    func createFeed(_ config: CustomFeedConfig) async throws {
        guard !config.ownerId.isEmpty else {
            throw CustomFeedServiceError.missingUserId
        }

        let docId = config.firestoreId ?? config.id.uuidString
        let data = Self.encode(config, docId: docId)

        do {
            try await feedsCollection(userId: config.ownerId)
                .document(docId)
                .setData(data, merge: true)
        } catch {
            throw CustomFeedServiceError.firestoreWriteFailed(error)
        }
    }

    // MARK: - Update

    func updateFeed(_ config: CustomFeedConfig) async throws {
        guard !config.ownerId.isEmpty else {
            throw CustomFeedServiceError.missingUserId
        }

        let docId = config.firestoreId ?? config.id.uuidString
        let data = Self.encode(config, docId: docId)

        do {
            try await feedsCollection(userId: config.ownerId)
                .document(docId)
                .setData(data, merge: true)
        } catch {
            throw CustomFeedServiceError.firestoreWriteFailed(error)
        }
    }

    // MARK: - Delete

    /// Only non-builtIn feeds may be deleted.
    func deleteFeed(id: UUID, userId: String) async throws {
        guard !userId.isEmpty else {
            throw CustomFeedServiceError.missingUserId
        }

        // Validate the feed is not built-in before hitting Firestore
        if let target = feeds.first(where: { $0.id == id }), target.isBuiltIn {
            throw CustomFeedServiceError.builtInDeletionForbidden
        }

        let docId = id.uuidString
        do {
            try await feedsCollection(userId: userId)
                .document(docId)
                .delete()
        } catch {
            throw CustomFeedServiceError.firestoreWriteFailed(error)
        }
    }

    // MARK: - Reorder

    /// Updates `sortOrder` for each feed in the given array using a batch write.
    func reorderFeeds(_ orderedFeeds: [CustomFeedConfig], userId: String) async throws {
        guard !userId.isEmpty else {
            throw CustomFeedServiceError.missingUserId
        }

        let db = FirebaseManager.shared.firestore
        let batch = db.batch()
        let collection = feedsCollection(userId: userId)

        for (index, var config) in orderedFeeds.enumerated() {
            config.sortOrder = index
            let docId = config.firestoreId ?? config.id.uuidString
            batch.setData(["sortOrder": index], forDocument: collection.document(docId), merge: true)
        }

        do {
            try await batch.commit()
        } catch {
            throw CustomFeedServiceError.firestoreWriteFailed(error)
        }
    }

    // MARK: - Seed defaults on first launch

    /// Checks whether any feed documents exist for `userId`. If none, batch-writes the
    /// default feeds from `CustomFeedConfig.defaultFeeds(ownerId:)`.
    func seedDefaultFeeds(userId: String) async throws {
        guard !userId.isEmpty else {
            throw CustomFeedServiceError.missingUserId
        }

        let snapshot = try await feedsCollection(userId: userId)
            .limit(to: 1)
            .getDocuments()

        guard snapshot.documents.isEmpty else { return }

        let defaults = CustomFeedConfig.defaultFeeds(ownerId: userId)
        let db = FirebaseManager.shared.firestore
        let batch = db.batch()
        let collection = feedsCollection(userId: userId)

        for config in defaults {
            let docId = config.id.uuidString
            let data = Self.encode(config, docId: docId)
            batch.setData(data, forDocument: collection.document(docId), merge: true)
        }

        do {
            try await batch.commit()
        } catch {
            throw CustomFeedServiceError.firestoreWriteFailed(error)
        }
    }

    // MARK: - Encode / Decode helpers

    private static func encode(_ config: CustomFeedConfig, docId: String) -> [String: Any] {
        let data: [String: Any] = [
            "id":              config.id.uuidString,
            "firestoreId":     docId,
            "name":            config.name,
            "feedDescription": config.feedDescription,
            "isPublic":        config.isPublic,
            "profileIds":      config.profileIds,
            "topicIds":        config.topicIds,
            "sortOrder":       config.sortOrder,
            "createdAt":       Timestamp(date: config.createdAt),
            "ownerId":         config.ownerId,
            "isBuiltIn":       config.isBuiltIn,
        ]
        return data
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> CustomFeedConfig? {
        let data = doc.data()

        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = data["name"] as? String,
            let ownerId = data["ownerId"] as? String
        else { return nil }

        let firestoreId    = data["firestoreId"] as? String ?? doc.documentID
        let feedDescription = data["feedDescription"] as? String ?? ""
        let isPublic       = data["isPublic"] as? Bool ?? false
        let profileIds     = data["profileIds"] as? [String] ?? []
        let topicIds       = data["topicIds"] as? [String] ?? []
        let sortOrder      = data["sortOrder"] as? Int ?? 0
        let isBuiltIn      = data["isBuiltIn"] as? Bool ?? false
        let createdAt: Date
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }

        return CustomFeedConfig(
            id: id,
            firestoreId: firestoreId,
            name: name,
            feedDescription: feedDescription,
            isPublic: isPublic,
            profileIds: profileIds,
            topicIds: topicIds,
            sortOrder: sortOrder,
            createdAt: createdAt,
            ownerId: ownerId,
            isBuiltIn: isBuiltIn
        )
    }
}
