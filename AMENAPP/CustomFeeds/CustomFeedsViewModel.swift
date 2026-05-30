// CustomFeedsViewModel.swift
// AMENAPP — Custom Feeds feature (Agent G)
//
// @Observable view-model that manages a user's custom feed list.
// Firestore path: users/{uid}/customFeeds/{feedId}
//
// Rules:
//  - All writes are idempotent (merge: true for updates).
//  - Built-in feeds are seeded on first load and cannot be deleted.
//  - sortOrder is kept consistent after every reorder.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@Observable
@MainActor
final class CustomFeedsViewModel {

    // MARK: - Observed state

    var feeds: [CustomFeedConfig] = []
    var isLoading: Bool = false
    var editMode: EditMode = .inactive

    // MARK: - Private

    private var db = Firestore.firestore()

    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: - Load

    /// Loads feeds from Firestore sorted by sortOrder.
    /// Seeds defaultFeeds for new users when the collection is empty.
    func loadFeeds() async {
        guard let uid else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .order(by: "sortOrder")
                .getDocuments(source: .default)

            let decoded: [CustomFeedConfig] = snapshot.documents.compactMap { doc in
                var config = try? Firestore.Decoder().decode(CustomFeedConfig.self, from: doc.data())
                config?.firestoreId = doc.documentID
                return config
            }

            if decoded.isEmpty {
                // Seed defaults for a new user
                let defaults = CustomFeedConfig.defaultFeeds(ownerId: uid)
                feeds = defaults
                await persistAll(defaults, uid: uid)
            } else {
                feeds = decoded
            }
        } catch {
            dlog("CustomFeedsViewModel.loadFeeds error: \(error.localizedDescription)")
        }
    }

    // MARK: - Save / Update

    /// Upserts a single feed document (merge: true so partial updates are safe).
    func saveFeed(_ feed: CustomFeedConfig) async {
        guard let uid else { return }
        do {
            let docId = feed.firestoreId ?? feed.id.uuidString
            let data = try Firestore.Encoder().encode(feed)
            try await db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .document(docId)
                .setData(data, merge: true)

            // Update local copy
            if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                var updated = feed
                updated.firestoreId = docId
                feeds[idx] = updated
            }
        } catch {
            dlog("CustomFeedsViewModel.saveFeed error: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    /// Deletes a non-built-in feed from Firestore and the local list.
    func deleteFeed(_ feed: CustomFeedConfig) async {
        guard !feed.isBuiltIn else { return }
        guard let uid else { return }
        guard let docId = feed.firestoreId else { return }

        feeds.removeAll { $0.id == feed.id }

        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .document(docId)
                .delete()
        } catch {
            dlog("CustomFeedsViewModel.deleteFeed error: \(error.localizedDescription)")
        }
    }

    // MARK: - Reorder

    /// Reorders feeds in response to List .onMove, then persists updated sortOrder values.
    func reorder(from source: IndexSet, to destination: Int) {
        feeds.move(fromOffsets: source, toOffset: destination)
        for (idx, _) in feeds.enumerated() {
            feeds[idx].sortOrder = idx
        }
        let snapshot = feeds
        Task {
            await persistSortOrders(snapshot)
        }
    }

    // MARK: - Create

    /// Creates a brand-new user-defined feed, appends it locally, and writes to Firestore.
    func createFeed(
        name: String,
        description: String,
        isPublic: Bool,
        profileIds: [String],
        topicIds: [String]
    ) async {
        guard let uid else { return }
        let newSortOrder = feeds.count
        var config = CustomFeedConfig(
            id: UUID(),
            firestoreId: nil,
            name: name,
            feedDescription: description,
            isPublic: isPublic,
            profileIds: profileIds,
            topicIds: topicIds,
            sortOrder: newSortOrder,
            createdAt: Date(),
            ownerId: uid,
            isBuiltIn: false
        )
        let docId = config.id.uuidString
        config.firestoreId = docId
        feeds.append(config)

        do {
            let data = try Firestore.Encoder().encode(config)
            try await db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .document(docId)
                .setData(data, merge: false)
        } catch {
            dlog("CustomFeedsViewModel.createFeed error: \(error.localizedDescription)")
            // Roll back local append on failure
            feeds.removeAll { $0.id == config.id }
        }
    }

    // MARK: - Private helpers

    private func persistAll(_ configs: [CustomFeedConfig], uid: String) async {
        let batch = db.batch()
        for var config in configs {
            let docId = config.firestoreId ?? config.id.uuidString
            config.firestoreId = docId
            let ref = db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .document(docId)
            if let data = try? Firestore.Encoder().encode(config) {
                batch.setData(data, forDocument: ref, merge: true)
            }
        }
        do {
            try await batch.commit()
            // Patch firestoreIds in-memory so subsequent saves use the correct doc ids
            for (idx, _) in feeds.enumerated() {
                if feeds[idx].firestoreId == nil {
                    feeds[idx].firestoreId = feeds[idx].id.uuidString
                }
            }
        } catch {
            dlog("CustomFeedsViewModel.persistAll error: \(error.localizedDescription)")
        }
    }

    private func persistSortOrders(_ snapshot: [CustomFeedConfig]) async {
        guard let uid else { return }
        let batch = db.batch()
        for config in snapshot {
            guard let docId = config.firestoreId else { continue }
            let ref = db
                .collection("users")
                .document(uid)
                .collection("customFeeds")
                .document(docId)
            batch.updateData(["sortOrder": config.sortOrder], forDocument: ref)
        }
        do {
            try await batch.commit()
        } catch {
            dlog("CustomFeedsViewModel.persistSortOrders error: \(error.localizedDescription)")
        }
    }
}
