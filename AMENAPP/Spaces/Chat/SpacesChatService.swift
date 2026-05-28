// SpacesChatService.swift
// AMENAPP — Spaces v2 Chat Layer (Agent B)
//
// Real-time chat service: threads, messages, reactions, read-state,
// typing indicators (RTDB), and Berean @mention invocation.
//
// Architecture rules:
//   - All @Published mutations happen on MainActor.
//   - Soft-delete only: never call .delete() on a Firestore document.
//   - All ListenerRegistration refs are stored and cancelled in deinit / stopListening().
//   - No force-unwraps anywhere.
//   - No Combine: async/await + AsyncStream only.

import Foundation
import FirebaseFirestore
import FirebaseDatabase
import FirebaseAuth

// MARK: - SpacesChatService

@MainActor
final class SpacesChatService: ObservableObject {

    // MARK: Published state

    /// Threads filtered by `currentFilter`.
    @Published var threads: [ThreadSummary] = []
    /// Current active tab filter.
    @Published var currentFilter: ThreadFilter = .all
    /// Messages for the currently open thread, soft-deleted entries included (rendered as placeholder).
    @Published var messages: [SpacesChatMessage] = []
    /// Currently typing users in the open thread.
    @Published var typingUsers: [SpacesChatTypingIndicator] = []
    /// Error surface for the owning view to display.
    @Published var lastError: String?

    // MARK: Private state

    /// Raw (unfiltered) thread list; filter is applied client-side.
    private var allThreads: [ThreadSummary] = []
    /// Thread IDs the current user has marked as VIP.
    var vipThreadIds: Set<String> = []

    private let db = Firestore.firestore()
    private let rtdb = Database.database().reference()

    /// Retained Firestore listener handles — cancelled on stopListening() / deinit.
    private var threadListener: ListenerRegistration?
    private var messageListener: ListenerRegistration?

    /// Currently observed thread/space pair (for typing RTDB cleanup).
    private var activeThreadId: String?
    private var activeSpaceId: String?

    /// RTDB handle for the typing observer.
    private var typingObserverHandle: DatabaseHandle?

    // MARK: - Init / deinit

    init() {}

    deinit {
        // Must detach on a background thread; deinit is non-isolated.
        let tl = threadListener
        let ml = messageListener
        tl?.remove()
        ml?.remove()
        // RTDB typing observer removed synchronously (safe from any thread).
        if let handle = typingObserverHandle,
           let spaceId = activeSpaceId,
           let threadId = activeThreadId {
            let ref = Database.database().reference()
                .child("typing").child(spaceId).child(threadId)
            ref.removeObserver(withHandle: handle)
        }
    }

    // MARK: - Thread List

    /// Attaches a Firestore real-time listener on `spaces/{spaceId}/threads`.
    /// Applies client-side filter based on `filter`.
    func loadThreads(spaceId: String, filter: ThreadFilter) async {
        currentFilter = filter
        threadListener?.remove()
        threadListener = nil

        let ref = db.collection("spaces").document(spaceId).collection("threads")
            .order(by: "lastMessageAt", descending: true)

        threadListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard let snapshot else { return }

            let decoded: [ThreadSummary] = snapshot.documents.compactMap { doc in
                self.decodeThread(doc: doc)
            }
            self.allThreads = decoded
            self.applyFilter()
        }
    }

    /// Switches the active filter and re-applies it over the already-loaded thread list.
    func setFilter(_ filter: ThreadFilter) {
        currentFilter = filter
        applyFilter()
    }

    private func applyFilter() {
        switch currentFilter {
        case .all:
            threads = allThreads
        case .vip:
            threads = allThreads.filter { vipThreadIds.contains($0.id) }
        case .unreads:
            threads = allThreads.filter { $0.unreadCount > 0 }
        case .external:
            threads = allThreads.filter { $0.hasExternalMembers }
        }
    }

    // MARK: - Messages

    /// Attaches a Firestore real-time listener on the thread's messages subcollection.
    /// Soft-deleted messages are included; the view renders them as a "removed" placeholder.
    func loadMessages(threadId: String, spaceId: String) async {
        messageListener?.remove()
        messageListener = nil
        activeThreadId = threadId
        activeSpaceId = spaceId

        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages")
            .order(by: "createdAt", descending: false)

        messageListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard let snapshot else { return }

            let decoded: [SpacesChatMessage] = snapshot.documents.compactMap { doc in
                self.decodeMessage(doc: doc)
            }
            self.messages = decoded
        }
    }

    // MARK: - Send Message

    /// Writes a new message to `spaces/{spaceId}/threads/{threadId}/messages/{UUID}`.
    /// Validates body is non-empty and ≤ 4000 characters.
    func sendMessage(threadId: String, spaceId: String, body: String, replyToId: String?) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChatError.emptyMessage
        }
        guard trimmed.count <= 4000 else {
            throw ChatError.messageTooLong(limit: 4000, actual: trimmed.count)
        }
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChatError.notAuthenticated
        }
        let displayName = Auth.auth().currentUser?.displayName ?? "Member"

        let messageId = UUID().uuidString
        var payload: [String: Any] = [
            "id": messageId,
            "threadId": threadId,
            "spaceId": spaceId,
            "authorId": userId,
            "authorDisplayName": displayName,
            "body": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "reactions": [String: [String]](),
            "attachments": [[String: Any]](),
            "isDeleted": false
        ]
        if let replyToId {
            payload["replyToId"] = replyToId
        }

        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)

        try await ref.setData(payload)

        // Update thread's lastMessageAt and preview.
        let threadRef = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
        try await threadRef.updateData([
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessagePreview": String(trimmed.prefix(120))
        ])
    }

    // MARK: - Soft Delete

    /// Sets `isDeleted = true` if the caller is the author or a space admin.
    /// NEVER calls `.delete()` on a Firestore document.
    func softDeleteMessage(messageId: String, threadId: String, spaceId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChatError.notAuthenticated
        }

        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)

        let snapshot = try await ref.getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw ChatError.messageNotFound
        }

        let authorId = data["authorId"] as? String ?? ""
        let isAuthor = authorId == userId

        // Check space admin/owner role via members subcollection.
        let memberRef = db
            .collection("spaces").document(spaceId)
            .collection("members").document(userId)
        let memberSnap = try await memberRef.getDocument()
        let role = memberSnap.data()?["role"] as? String ?? ""
        let isAdmin = role == "owner" || role == "admin" || role == "moderator"

        guard isAuthor || isAdmin else {
            throw ChatError.notAuthorized
        }

        try await ref.updateData(["isDeleted": true])
    }

    // MARK: - Reactions

    /// Adds `userId` to `reactions[emoji]` via atomic arrayUnion.
    func addReaction(emoji: String, messageId: String, threadId: String, spaceId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChatError.notAuthenticated
        }
        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)

        try await ref.updateData([
            "reactions.\(emoji)": FieldValue.arrayUnion([userId])
        ])
    }

    /// Removes `userId` from `reactions[emoji]` via atomic arrayRemove.
    func removeReaction(emoji: String, messageId: String, threadId: String, spaceId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChatError.notAuthenticated
        }
        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)

        try await ref.updateData([
            "reactions.\(emoji)": FieldValue.arrayRemove([userId])
        ])
    }

    // MARK: - Read State

    /// Writes a SpacesChatReadState document to `spaces/{spaceId}/threads/{threadId}/readStates/{userId}`.
    func markThreadRead(threadId: String, spaceId: String, lastMessageId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let ref = db
            .collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("readStates").document(userId)

        let payload: [String: Any] = [
            "threadId": threadId,
            "userId": userId,
            "lastReadMessageId": lastMessageId,
            "lastReadAt": FieldValue.serverTimestamp()
        ]

        // Non-throwing: UI should not fail if read-state write fails.
        do {
            try await ref.setData(payload, merge: true)
        } catch {
            // Silently log; read-state failure is non-critical.
        }
    }

    // MARK: - Typing Indicators (RTDB)

    /// Writes to RTDB `typing/{spaceId}/{threadId}/{userId}` with current timestamp.
    /// Auto-expires after 5 s: clients that see a node older than 5 s ignore it.
    func startTyping(threadId: String, spaceId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = rtdb
            .child("typing")
            .child(spaceId)
            .child(threadId)
            .child(userId)

        let payload: [String: Any] = [
            "userId": userId,
            "timestamp": ServerValue.timestamp()
        ]
        // Use completion-handler variant to suppress async-overload warnings.
        ref.setValue(payload) { _, _ in }
    }

    /// Removes the user's typing node from RTDB.
    func stopTyping(threadId: String, spaceId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        rtdb
            .child("typing")
            .child(spaceId)
            .child(threadId)
            .child(userId)
            .removeValue { _, _ in }
    }

    /// Subscribes to the RTDB typing node for a thread and updates `typingUsers`.
    /// Call once when ThreadDetailView appears; call `stopObservingTyping` on disappear.
    func observeTyping(threadId: String, spaceId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Remove previous observer if any.
        stopObservingTyping(threadId: threadId, spaceId: spaceId)

        let ref = rtdb
            .child("typing")
            .child(spaceId)
            .child(threadId)

        let staleThreshold: TimeInterval = 5
        let handle = ref.observe(.value) { [weak self] snapshot in
            guard let self else { return }
            var indicators: [SpacesChatTypingIndicator] = []
            let now = Date()

            for child in snapshot.children {
                guard let childSnap = child as? DataSnapshot,
                      let dict = childSnap.value as? [String: Any] else { continue }
                let userId = dict["userId"] as? String ?? childSnap.key
                // Skip self.
                guard userId != currentUserId else { continue }
                // Parse timestamp (RTDB ServerValue.timestamp() is ms since epoch).
                let tsMillis = dict["timestamp"] as? Double ?? 0
                let ts = Date(timeIntervalSince1970: tsMillis / 1000)
                // Ignore stale nodes older than 5 s.
                guard now.timeIntervalSince(ts) < staleThreshold else { continue }

                let displayName = dict["displayName"] as? String ?? "Someone"
                indicators.append(
                    SpacesChatTypingIndicator(userId: userId, displayName: displayName, timestamp: ts)
                )
            }

            Task { @MainActor [weak self] in
                self?.typingUsers = indicators
            }
        }

        typingObserverHandle = handle
        activeThreadId = threadId
        activeSpaceId = spaceId
    }

    /// Removes the RTDB typing observer for a thread.
    func stopObservingTyping(threadId: String, spaceId: String) {
        if let handle = typingObserverHandle {
            rtdb
                .child("typing")
                .child(spaceId)
                .child(threadId)
                .removeObserver(withHandle: handle)
            typingObserverHandle = nil
        }
        typingUsers = []
    }

    // MARK: - Berean @mention

    /// Invokes Berean via `BereanSpaceMemberService.shared.invoke(...)`.
    /// Does NOT write a message client-side — Berean's response is written server-side
    /// and will appear via the existing `messageListener`.
    func invokeBerean(threadId: String, spaceId: String, message: String, spaceType: SpaceV2Type) async throws {
        let amenSpaceType: AmenSpaceType = amenSpaceTypeFrom(spaceV2Type: spaceType)
        _ = try await BereanSpaceMemberService.shared.invoke(
            spaceId: spaceId,
            roomId: threadId,
            trigger: .atMention,
            userMessage: message,
            replyToPostId: nil,
            spaceType: amenSpaceType
        )
    }

    // MARK: - Stop Listening

    /// Cancels all active Firestore listeners. Call on view disappear or deinit.
    func stopListening() {
        threadListener?.remove()
        threadListener = nil
        messageListener?.remove()
        messageListener = nil
        if let handle = typingObserverHandle,
           let spaceId = activeSpaceId,
           let threadId = activeThreadId {
            rtdb.child("typing").child(spaceId).child(threadId)
                .removeObserver(withHandle: handle)
            typingObserverHandle = nil
        }
        typingUsers = []
    }

    // MARK: - Decoding helpers

    private func decodeThread(doc: QueryDocumentSnapshot) -> ThreadSummary? {
        let data = doc.data()
        let id = doc.documentID
        guard
            let spaceId     = data["spaceId"] as? String,
            let title       = data["title"] as? String,
            let createdBy   = data["createdBy"] as? String,
            let createdAtTS = data["createdAt"] as? Timestamp,
            let lastMsgAtTS = data["lastMessageAt"] as? Timestamp
        else { return nil }

        return ThreadSummary(
            id: id,
            spaceId: spaceId,
            title: title,
            createdBy: createdBy,
            createdAt: createdAtTS.dateValue(),
            lastMessageAt: lastMsgAtTS.dateValue(),
            lastMessagePreview: data["lastMessagePreview"] as? String,
            unreadCount: data["unreadCount"] as? Int ?? 0,
            hasExternalMembers: data["hasExternalMembers"] as? Bool ?? false
        )
    }

    private func decodeMessage(doc: QueryDocumentSnapshot) -> SpacesChatMessage? {
        let data = doc.data()
        let id = doc.documentID
        guard
            let threadId    = data["threadId"] as? String,
            let spaceId     = data["spaceId"] as? String,
            let authorId    = data["authorId"] as? String,
            let authorName  = data["authorDisplayName"] as? String,
            let body        = data["body"] as? String,
            let createdAtTS = data["createdAt"] as? Timestamp
        else { return nil }

        let rawReactions = data["reactions"] as? [String: [String]] ?? [:]

        let rawAttachments = data["attachments"] as? [[String: Any]] ?? []
        let attachments: [SpacesChatAttachment] = rawAttachments.compactMap { dict in
            guard
                let attId   = dict["id"] as? String,
                let typeRaw = dict["type"] as? String,
                let attType = SpacesChatAttachmentType(rawValue: typeRaw),
                let url     = dict["url"] as? String
            else { return nil }
            return SpacesChatAttachment(
                id: attId,
                type: attType,
                url: url,
                thumbnailURL: dict["thumbnailURL"] as? String,
                fileName: dict["fileName"] as? String,
                fileSizeBytes: dict["fileSizeBytes"] as? Int
            )
        }

        let editedAt = (data["editedAt"] as? Timestamp)?.dateValue()

        return SpacesChatMessage(
            id: id,
            threadId: threadId,
            spaceId: spaceId,
            authorId: authorId,
            authorDisplayName: authorName,
            authorAvatarURL: data["authorAvatarURL"] as? String,
            authorHomeCommunityId: data["authorHomeCommunityId"] as? String,
            body: body,
            createdAt: createdAtTS.dateValue(),
            editedAt: editedAt,
            reactions: rawReactions,
            attachments: attachments,
            isDeleted: data["isDeleted"] as? Bool ?? false
        )
    }

    // MARK: - Type Bridge

    /// Maps the v2 `SpaceV2Type` to the legacy `AmenSpaceType` required by
    /// `BereanSpaceMemberService`.
    private func amenSpaceTypeFrom(spaceV2Type: SpaceV2Type) -> AmenSpaceType {
        switch spaceV2Type {
        case .chat:         return .churchMinistry
        case .bibleStudy:   return .bibleStudy
        case .group:        return .discipleshipCohort
        case .announcement: return .churchMinistry
        }
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case emptyMessage
    case messageTooLong(limit: Int, actual: Int)
    case notAuthenticated
    case notAuthorized
    case messageNotFound

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Please enter a message before sending."
        case .messageTooLong(let limit, let actual):
            return "Message is too long (\(actual)/\(limit) characters)."
        case .notAuthenticated:
            return "You must be signed in to send messages."
        case .notAuthorized:
            return "You don't have permission to perform this action."
        case .messageNotFound:
            return "Message could not be found."
        }
    }
}
