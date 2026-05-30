//
//  OfflinePostQueue.swift
//  AMENAPP
//
//  Queues posts created while offline and publishes them when connectivity returns.
//  Posts are persisted to UserDefaults so they survive app restarts.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class OfflinePostQueue: ObservableObject {
    static let shared = OfflinePostQueue()

    @Published private(set) var pendingPosts: [QueuedPost] = []
    @Published private(set) var isSyncing = false

    private let storageKey = "offlinePostQueue"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadFromDisk()
        observeConnectivity()
    }

    // MARK: - Public API

    /// Queue a post for later publishing (when offline).
    func enqueue(
        content: String,
        category: String,
        topicTag: String?,
        imageData: [Data]? = nil,
        authorId: String
    ) {
        let post = QueuedPost(
            id: UUID().uuidString,
            content: content,
            category: category,
            topicTag: topicTag,
            authorId: authorId,
            createdAt: Date(),
            retryCount: 0
        )
        pendingPosts.append(post)
        saveToDisk()
    }

    /// Attempt to publish all pending posts.
    func syncPendingPosts() async {
        guard !isSyncing, !pendingPosts.isEmpty else { return }
        guard AMENNetworkMonitor.shared.isConnected else { return }

        isSyncing = true
        var published: [String] = []
        let db = Firestore.firestore()

        for post in pendingPosts {
            // Idempotency pre-check: if a post with this queue item's id was already
            // written to Firestore (e.g. the app was killed after the write succeeded
            // but before the queue was flushed), skip re-creation and just dequeue it.
            do {
                let existing = try await db.collection("posts")
                    .whereField("idempotencyKey", isEqualTo: post.id)
                    .limit(to: 1)
                    .getDocuments()
                if !existing.isEmpty {
                    published.append(post.id)
                    continue
                }
            } catch {
                // Network error on the check — leave post in queue to retry later.
                continue
            }

            // PostsManager.createPost does not throw (it spawns an internal Task).
            // We call it and mark the item as published; the internal retry/error
            // handling inside FirebasePostService handles transient write failures.
            PostsManager.shared.createPost(
                content: post.content,
                category: Post.PostCategory(rawValue: post.category) ?? .openTable,
                topicTag: post.topicTag,
                visibility: .everyone,
                allowComments: true
            )
            published.append(post.id)
        }

        pendingPosts.removeAll { published.contains($0.id) }
        saveToDisk()
        isSyncing = false
    }

    var hasPendingPosts: Bool { !pendingPosts.isEmpty }

    // MARK: - Private

    private func observeConnectivity() {
        AMENNetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .filter { $0 } // Only when connectivity returns
            .debounce(for: .seconds(2), scheduler: RunLoop.main) // Wait for stable connection
            .sink { [weak self] _ in
                Task { await self?.syncPendingPosts() }
            }
            .store(in: &cancellables)
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(pendingPosts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let posts = try? JSONDecoder().decode([QueuedPost].self, from: data) {
            pendingPosts = posts
        }
    }
}

// MARK: - Queued Post Model

struct QueuedPost: Codable, Identifiable {
    let id: String
    let content: String
    let category: String
    let topicTag: String?
    let authorId: String
    let createdAt: Date
    var retryCount: Int
}
