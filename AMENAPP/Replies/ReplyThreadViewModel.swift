// ReplyThreadViewModel.swift
// AMENAPP — Replies/
//
// @Observable @MainActor view-model for a threaded reply tree rooted at a
// single Firestore post.  Loads replies, builds depth-2 tree, listens for
// real-time updates, and handles idempotent submit + amen toggle.
//
// Types used: ReplyNode, ComposerDraft  (ComposerContract.swift)
// Firestore path: posts/{rootPostId}/comments/{commentId}

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - ReplySortMode

enum ReplySortMode: String, CaseIterable, Identifiable {
    case top    = "Top"
    case newest = "Newest"

    var id: String { rawValue }
}

// MARK: - ReplyThreadViewModel

@MainActor
@Observable
final class ReplyThreadViewModel {

    // MARK: Public state

    var rootPostId: String
    var replies: [ReplyNode] = []
    var sortMode: ReplySortMode = .top {
        didSet {
            guard sortMode != oldValue else { return }
            stopListening()
            startListening()
        }
    }
    var isLoading = false
    var replyComposerDraft = ComposerDraft()
    var isReplyComposerPresented = false
    var activeParentId: String? = nil        // which reply is being replied to
    var errorMessage: String? = nil

    // MARK: Private state

    private var listenerRegistration: ListenerRegistration?
    private var submittedReplyIds: Set<String> = []   // idempotency guard
    private var hasMoreReplies = false

    // MARK: Init

    init(rootPostId: String) {
        self.rootPostId = rootPostId
    }

    // MARK: - Firestore helpers

    private var commentsCollection: CollectionReference {
        Firestore.firestore().collection("posts").document(rootPostId).collection("comments")
    }

    private var sortedQuery: Query {
        if sortMode == .newest {
            return commentsCollection
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
        } else {
            return commentsCollection
                .order(by: "amenCount", descending: true)
                .limit(to: 50)
        }
    }

    // MARK: - Load

    func loadReplies() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await sortedQuery.getDocuments()
            replies = buildTree(from: snapshot.documents)
            hasMoreReplies = snapshot.documents.count == 50
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Real-time listener

    func startListening() {
        listenerRegistration?.remove()
        listenerRegistration = sortedQuery.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot else { return }
            Task { @MainActor in
                self.replies = self.buildTree(from: snapshot.documents)
                self.hasMoreReplies = snapshot.documents.count == 50
            }
        }
    }

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    // MARK: - Tree builder

    /// Maps Firestore docs → flat [ReplyNode] then groups children under parents
    /// up to depth 2.  Nodes deeper than 2 remain as children of depth-2 nodes
    /// so the UI can show "View more replies".
    private func buildTree(from docs: [QueryDocumentSnapshot]) -> [ReplyNode] {
        let flat: [ReplyNode] = docs.compactMap { doc in
            let data = doc.data()
            guard
                let authorId   = data["authorId"]   as? String,
                let authorName = data["authorName"] as? String,
                let content    = data["content"]    as? String
            else { return nil }

            let createdAt: Date
            if let ts = data["createdAt"] as? Timestamp {
                createdAt = ts.dateValue()
            } else {
                createdAt = Date()
            }

            let initials = authorName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map { String($0) } }
                .joined()
                .uppercased()

            return ReplyNode(
                id:                     doc.documentID,
                postId:                 doc.documentID,
                parentId:               data["parentId"] as? String,
                rootPostId:             rootPostId,
                authorId:               authorId,
                authorName:             authorName,
                authorUsername:         data["authorUsername"] as? String,
                authorProfileImageURL:  data["authorProfileImageURL"] as? String,
                authorInitials:         initials.isEmpty ? "?" : initials,
                content:                content,
                createdAt:              createdAt,
                likeCount:              data["amenCount"]   as? Int ?? 0,
                replyCount:             data["replyCount"]  as? Int ?? 0,
                depth:                  0,
                children:               [],
                sortKey:                data["amenCount"] as? Double ?? 0
            )
        }

        // Build lookup
        var byId: [String: ReplyNode] = Dictionary(uniqueKeysWithValues: flat.map { ($0.id, $0) })

        // Attach children
        for node in flat {
            guard let parentId = node.parentId, byId[parentId] != nil else { continue }
            byId[parentId]!.children.append(node)
        }

        // Assign depths recursively (cap at 2 for render; tree is preserved)
        func assignDepth(_ node: inout ReplyNode, depth: Int) {
            node.depth = depth
            for i in node.children.indices {
                assignDepth(&node.children[i], depth: depth + 1)
            }
        }

        // Return only root nodes (parentId == nil or parentId not in set)
        let ids = Set(flat.map { $0.id })
        var roots = byId.values.filter { node in
            guard let pid = node.parentId else { return true }
            return !ids.contains(pid)
        }
        .sorted {
            sortMode == .newest
                ? $0.createdAt > $1.createdAt
                : $0.likeCount > $1.likeCount
        }

        for i in roots.indices {
            assignDepth(&roots[i], depth: 0)
        }
        return roots
    }

    // MARK: - Submit reply

    /// Writes a new reply to Firestore.  Idempotent: a stable client-side key
    /// derived from (currentUserId + rootPostId + parentId + content prefix)
    /// prevents duplicate submissions from rapid double-taps.
    func submitReply(content: String, parentId: String?) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let currentUser = Auth.auth().currentUser
        let authorId    = currentUser?.uid ?? "anonymous"
        let authorName  = currentUser?.displayName ?? "Anonymous"

        // Idempotency key
        let prefix      = String(trimmed.prefix(40))
        let key         = "\(authorId):\(rootPostId):\(parentId ?? "root"):\(prefix)"
        guard !submittedReplyIds.contains(key) else { return }
        submittedReplyIds.insert(key)

        let initials = authorName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()

        var payload: [String: Any] = [
            "authorId":       authorId,
            "authorName":     authorName,
            "authorInitials": initials.isEmpty ? "?" : initials,
            "content":        trimmed,
            "rootPostId":     rootPostId,
            "createdAt":      FieldValue.serverTimestamp(),
            "amenCount":      0,
            "replyCount":     0
        ]
        if let parentId {
            payload["parentId"] = parentId
        }

        do {
            _ = try await commentsCollection.addDocument(data: payload)
            // Increment replyCount on parent comment if this is a nested reply
            if let parentId {
                try await commentsCollection.document(parentId).updateData([
                    "replyCount": FieldValue.increment(Int64(1))
                ])
            }
        } catch {
            // Roll back idempotency key so user can retry
            submittedReplyIds.remove(key)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Toggle amen (like)

    func toggleLike(replyId: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let amenRef = commentsCollection
            .document(replyId)
            .collection("amens")
            .document(currentUserId)

        do {
            let snap = try await amenRef.getDocument()
            if snap.exists {
                try await amenRef.delete()
                try await commentsCollection.document(replyId).updateData([
                    "amenCount": FieldValue.increment(Int64(-1))
                ])
            } else {
                try await amenRef.setData(["likedAt": FieldValue.serverTimestamp()])
                try await commentsCollection.document(replyId).updateData([
                    "amenCount": FieldValue.increment(Int64(1))
                ])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load more (pagination placeholder)

    var canLoadMore: Bool { hasMoreReplies }

    func loadMore() async {
        // TODO: cursor-based pagination — extend query with startAfterDocument
    }
}
