// PinnedPostsStore.swift
// AMENAPP — Profile Header v2
//
// 3-slot pin system. Stores postIds in users/{uid}.profile.pinSlots (array, max 3).
// Separate from the legacy single-pin `pinnedPostId` field — do not mix.
//
// Cloud Function: `updatePinSlots` receives { postIds: [String] }.
// Firestore listener: users/{userId} → profile.pinSlots

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - PinnedPostPreview

/// Lightweight resolved preview for a pinned post slot.
/// Populated by fetching `posts/{postId}` after each Firestore slot update.
public struct PinnedPostPreview: Identifiable, Hashable {
    public let id: String           // postId
    public var content: String
    public var type: String         // "prayer", "testimony", "verse", "openTable", etc.
    public var imageURL: String?
    public var pinnedAt: Date?
    public var authorId: String
}

// MARK: - PinSlotError

enum PinSlotError: LocalizedError {
    case alreadyAtCapacity
    case postAlreadyPinned(String)
    case postNotFound(String)

    var errorDescription: String? {
        switch self {
        case .alreadyAtCapacity:
            return "You already have 3 pinned posts. Remove one before pinning another."
        case .postAlreadyPinned(let id):
            return "Post \(id) is already pinned."
        case .postNotFound(let id):
            return "Post \(id) could not be found."
        }
    }
}

// MARK: - PinnedPostsStore

@MainActor
@Observable
public final class PinnedPostsStore {

    // MARK: - Public state

    /// Ordered list of up to 3 postIds, decoded from Firestore `profile.pinSlots`.
    private(set) var pinSlotIds: [String] = []

    /// Resolved previews for each pinned postId, in slot order.
    private(set) var pinnedPreviews: [PinnedPostPreview] = []

    private(set) var isLoading = false

    // MARK: - Private

    private let userId: String
    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private var listenerRegistration: ListenerRegistration?

    // MARK: - Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Lifecycle

    /// Attach the Firestore real-time listener for `users/{userId}.profile.pinSlots`.
    func start() {
        guard listenerRegistration == nil else { return }

        listenerRegistration = db
            .collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("⚠️ [PinnedPostsStore] listener error: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data() else { return }

                // Decode profile.pinSlots as [String]
                let slots: [String]
                if let profile = data["profile"] as? [String: Any],
                   let rawSlots = profile["pinSlots"] as? [String] {
                    slots = Array(rawSlots.prefix(3))
                } else {
                    slots = []
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pinSlotIds = slots
                    await self.resolvePreviews(for: slots)
                }
            }

        dlog("▶ [PinnedPostsStore] listener started for \(userId)")
    }

    /// Detach the Firestore listener and clear in-memory state.
    func stop() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        dlog("⏹ [PinnedPostsStore] listener stopped for \(userId)")
    }

    // MARK: - Queries

    func isPostPinned(_ postId: String) -> Bool {
        pinSlotIds.contains(postId)
    }

    // MARK: - Mutations

    /// Pin a post by appending its id to the current slot array (max 3).
    /// Throws `PinSlotError.alreadyAtCapacity` when all 3 slots are occupied.
    /// Throws `PinSlotError.postAlreadyPinned` when the post is already in a slot.
    func pinPost(_ postId: String) async throws {
        guard !pinSlotIds.contains(postId) else {
            throw PinSlotError.postAlreadyPinned(postId)
        }
        guard pinSlotIds.count < 3 else {
            throw PinSlotError.alreadyAtCapacity
        }

        let newSlots = pinSlotIds + [postId]
        try await callUpdatePinSlots(newSlots)
    }

    /// Unpin a post by removing its id from the current slot array.
    /// Silently succeeds if the post was not pinned.
    func unpinPost(_ postId: String) async throws {
        let newSlots = pinSlotIds.filter { $0 != postId }
        try await callUpdatePinSlots(newSlots)
    }

    /// Persist a new slot ordering.  The array must contain only ids already
    /// present in `pinSlotIds` (caller is responsible for drag-to-reorder logic).
    func reorder(_ newOrder: [String]) async throws {
        // Accept only ids that are actually in current slots; drop any extras.
        let validated = newOrder.filter { pinSlotIds.contains($0) }
        try await callUpdatePinSlots(validated)
    }

    // MARK: - Private helpers

    private func callUpdatePinSlots(_ postIds: [String]) async throws {
        isLoading = true
        defer { isLoading = false }

        dlog("📌 [PinnedPostsStore] updatePinSlots → \(postIds)")
        let result = try await functions
            .httpsCallable("updatePinSlots")
            .call(["postIds": postIds])
        dlog("✅ [PinnedPostsStore] updatePinSlots result: \(result.data)")
    }

    /// Fetch `posts/{postId}` for each id, preserving slot order.
    /// Existing previews whose ids have not changed are reused to avoid flicker.
    private func resolvePreviews(for slotIds: [String]) async {
        guard !slotIds.isEmpty else {
            pinnedPreviews = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        var resolved: [PinnedPostPreview] = []

        await withTaskGroup(of: (Int, PinnedPostPreview?).self) { group in
            for (index, postId) in slotIds.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil) }
                    return (index, await self.fetchPreview(postId: postId))
                }
            }

            var indexed = [(Int, PinnedPostPreview?)]()
            for await result in group {
                indexed.append(result)
            }

            // Restore slot order
            indexed.sort { $0.0 < $1.0 }
            resolved = indexed.compactMap { $0.1 }
        }

        pinnedPreviews = resolved
    }

    private func fetchPreview(postId: String) async -> PinnedPostPreview? {
        do {
            let snapshot = try await db.collection("posts").document(postId).getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                dlog("⚠️ [PinnedPostsStore] post \(postId) not found")
                return nil
            }

            let content = data["content"] as? String ?? ""
            let typeRaw = data["category"] as? String ?? "openTable"
            let imageURL = (data["imageURLs"] as? [String])?.first
            let authorId = data["authorId"] as? String ?? ""
            let pinnedAt: Date?
            if let ts = data["pinnedAt"] as? Timestamp {
                pinnedAt = ts.dateValue()
            } else {
                pinnedAt = nil
            }

            return PinnedPostPreview(
                id: postId,
                content: content,
                type: typeRaw,
                imageURL: imageURL,
                pinnedAt: pinnedAt,
                authorId: authorId
            )
        } catch {
            dlog("⚠️ [PinnedPostsStore] fetchPreview(\(postId)) error: \(error.localizedDescription)")
            return nil
        }
    }
}
