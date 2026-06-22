// RelationshipActivityService.swift
// AMENAPP
//
// Reads viewer-specific RelationshipActivityState from Firestore.
// Exposes a live listener for the active list and a batch-fetch for preloading.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class RelationshipActivityService {

    static let shared = RelationshipActivityService()

    private let db = Firestore.firestore()
    private var cache: [String: RelationshipActivityState] = [:]
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Current Viewer

    private var viewerId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Fetch Single

    func fetch(targetId: String) async -> RelationshipActivityState? {
        guard let viewerId else { return nil }
        let docId = "\(viewerId)_\(targetId)"

        if let cached = cache[docId] { return cached }

        do {
            let doc = try await db.collection("relationship_activity_state").document(docId).getDocument()
            guard let data = doc.data() else { return nil }
            let state = parse(data: data, viewerId: viewerId, targetId: targetId)
            cache[docId] = state
            return state
        } catch {
            dlog("[RelActivity] fetch error \(docId): \(error)")
            return nil
        }
    }

    // MARK: - Batch Fetch

    func fetchAll(targetIds: [String]) async -> [String: RelationshipActivityState] {
        guard let viewerId, !targetIds.isEmpty else { return [:] }

        var result: [String: RelationshipActivityState] = [:]
        var missing: [String] = []

        for targetId in targetIds {
            let docId = "\(viewerId)_\(targetId)"
            if let cached = cache[docId] {
                result[targetId] = cached
            } else {
                missing.append(targetId)
            }
        }

        // Composite IDs for whereField in query
        let missingDocIds = missing.map { "\(viewerId)_\($0)" }
        let chunks = missingDocIds.socialGraphChunked(into: 30)

        await withTaskGroup(of: [String: RelationshipActivityState].self) { group in
            for chunk in chunks {
                group.addTask {
                    await self.fetchChunk(chunk, viewerId: viewerId)
                }
            }
            for await partial in group {
                result.merge(partial) { $1 }
            }
        }

        for (targetId, state) in result {
            cache["\(viewerId)_\(targetId)"] = state
        }

        return result
    }

    private func fetchChunk(_ docIds: [String], viewerId: String) async -> [String: RelationshipActivityState] {
        do {
            let snap = try await db.collection("relationship_activity_state")
                .whereField(FieldPath.documentID(), in: docIds)
                .getDocuments()
            var result: [String: RelationshipActivityState] = [:]
            for doc in snap.documents {
                let parts = doc.documentID.split(separator: "_", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let targetId = String(parts[1])
                let state = parse(data: doc.data(), viewerId: viewerId, targetId: targetId)
                result[targetId] = state
            }
            return result
        } catch {
            dlog("[RelActivity] chunk fetch error: \(error)")
            return [:]
        }
    }

    // MARK: - Live Listener for Active List

    /// Starts a Firestore listener for all relationship states where viewerId = current user,
    /// filtered to a set of targetIds. Calls `onChange` on any update.
    func startListener(
        targetIds: [String],
        onChange: @escaping ([String: RelationshipActivityState]) -> Void
    ) {
        guard let viewerId else { return }
        stopAllListeners()

        let docIds = targetIds.map { "\(viewerId)_\($0)" }
        let chunks = docIds.socialGraphChunked(into: 30)

        for (i, chunk) in chunks.enumerated() {
            let reg = db.collection("relationship_activity_state")
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snap, error in
                    guard let self, let snap else { return }
                    var partial: [String: RelationshipActivityState] = [:]
                    for doc in snap.documents {
                        let parts = doc.documentID.split(separator: "_", maxSplits: 1)
                        guard parts.count == 2 else { continue }
                        let targetId = String(parts[1])
                        let state = self.parse(data: doc.data(), viewerId: viewerId, targetId: targetId)
                        self.cache[doc.documentID] = state
                        partial[targetId] = state
                    }
                    Task { @MainActor in onChange(partial) }
                }
            listeners["chunk_\(i)"] = reg
        }
    }

    func stopAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Invalidate

    func invalidate(targetId: String) {
        guard let viewerId else { return }
        cache.removeValue(forKey: "\(viewerId)_\(targetId)")
    }

    // MARK: - Parse

    private func parse(data: [String: Any], viewerId: String, targetId: String) -> RelationshipActivityState {
        var state = RelationshipActivityState(viewerId: viewerId, targetId: targetId)
        state.unseenPostCount = data["unseenPostCount"] as? Int ?? 0
        state.unseenPrayerCount = data["unseenPrayerCount"] as? Int ?? 0
        state.unseenNoteCount = data["unseenNoteCount"] as? Int ?? 0
        state.lastSeenAt = (data["lastSeenAt"] as? Timestamp)?.dateValue()
        state.lastActivityAt = (data["lastActivityAt"] as? Timestamp)?.dateValue()
        state.hasMutualInteraction = data["hasMutualInteraction"] as? Bool ?? false
        state.mutualTopics = data["mutualTopics"] as? [String] ?? []
        state.computedAt = (data["computedAt"] as? Timestamp)?.dateValue() ?? Date()
        return state
    }
}
