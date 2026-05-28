// SpacesChatViewModel.swift
// AMENAPP — Spaces Chat Core (Agent B)
//
// @MainActor view-model that drives SpacesChatView and exposes filter signals
// for Agent C's Spaces navigation shell.
//
// Architecture rules:
//   - ALL @Published mutations are on @MainActor. No off-main state writes.
//   - Firestore listeners are nonisolated; callbacks always dispatch via
//     Task { @MainActor in self.x = ... }.
//   - No Combine. AsyncStream + async/await only.
//   - No hard-deletes — all deletions call SpacesChatService.softDeleteMessage.
//   - Does NOT implement the paywall; caller must check entitlement before
//     presenting this view model.
//
// Delegates all Firestore/RTDB I/O to SpacesChatService (Chat/ layer).
// Computes SpaceFilterSignals via SpacesFilterService.
//
// Types:
//   SpacesChatMessage   — AMENAPP/Spaces/Chat/SpacesChatModels.swift
//   ThreadSummary       — AMENAPP/Spaces/Chat/SpacesChatModels.swift
//   ThreadFilter        — AMENAPP/Spaces/Chat/SpacesChatModels.swift

import Foundation
import FirebaseAuth

// MARK: - SpacesChatViewModel

@MainActor
final class SpacesChatViewModel: ObservableObject {

    // MARK: - Published State

    /// All messages for the active thread (soft-deleted entries included).
    @Published var messages: [SpacesChatMessage] = []

    /// Threads for the active space, ordered by lastMessageAt desc.
    @Published var threads: [ThreadSummary] = []

    /// The thread the user is currently viewing. nil = showing thread list.
    @Published var activeThreadId: String? = nil

    /// Current text in the composer input bar.
    @Published var draftBody: String = ""

    /// True while an async operation is in flight.
    @Published var isLoading: Bool = false

    /// Non-nil when the last operation failed; bind to an alert or toast.
    @Published var error: Error? = nil

    /// User IDs currently typing in the active thread.
    @Published var typingUserIds: [String] = []

    // MARK: - Private Services

    // SpacesChatService is @MainActor — use lazy var so the init runs on MainActor.
    private lazy var chatService: SpacesChatService = SpacesChatService()
    // SpacesFilterService.shared is safe to access from nonisolated contexts —
    // use lazy to defer creation to when it's first needed on MainActor.
    private lazy var filterService: SpacesFilterService = SpacesFilterService.shared
    private var spaceId: String = ""

    // MARK: - Init

    init() {}

    // MARK: - Filter Signals (for Agent C)

    /// Pre-computed filter signals that drive the Spaces list badge / sort in Agent C.
    /// Derived from local thread state; no extra Firestore read required.
    var filterSignals: SpaceFilterSignals {
        filterService.signals(for: spaceId, threads: threads)
    }

    /// Messages authored by members whose `authorHomeCommunityId` is non-nil
    /// (i.e., authors from a linked external community).
    var externalMemberMessages: [SpacesChatMessage] {
        messages.filter { $0.authorHomeCommunityId != nil }
    }

    // MARK: - Load

    /// Loads the space's thread list and starts real-time listeners.
    /// Must be called before any other method.
    func loadSpace(spaceId: String) async {
        self.spaceId = spaceId
        isLoading = true
        defer { isLoading = false }

        await chatService.loadThreads(spaceId: spaceId, filter: .all)
        // SpacesChatService is @MainActor — safe to read @Published directly here.
        threads = chatService.threads
        startListening()
    }

    // MARK: - Thread Selection

    /// Selects a thread and loads its messages + typing observers.
    func selectThread(_ threadId: String) async {
        // Tear down previous typing observer before switching.
        if let prev = activeThreadId {
            chatService.stopObservingTyping(threadId: prev, spaceId: spaceId)
        }
        activeThreadId = threadId
        isLoading = true
        defer { isLoading = false }

        await chatService.loadMessages(threadId: threadId, spaceId: spaceId)
        chatService.observeTyping(threadId: threadId, spaceId: spaceId)

        // Both this VM and SpacesChatService are @MainActor — safe direct read.
        messages = chatService.messages
        typingUserIds = chatService.typingUsers.map(\.userId)
    }

    // MARK: - Send

    /// Sends the provided body as a new message. Clears `draftBody` on success.
    func sendMessage(body: String) async {
        guard let threadId = activeThreadId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await chatService.sendMessage(
                threadId: threadId,
                spaceId: spaceId,
                body: trimmed,
                replyToId: nil
            )
            draftBody = ""
        } catch {
            self.error = error
        }
    }

    // MARK: - Soft Delete

    /// Soft-deletes a message by setting `isDeleted = true`.
    /// NEVER calls a hard Firestore `.delete()`.
    func softDeleteMessage(id: String) async {
        guard let threadId = activeThreadId else { return }
        do {
            try await chatService.softDeleteMessage(
                messageId: id,
                threadId: threadId,
                spaceId: spaceId
            )
        } catch {
            self.error = error
        }
    }

    // MARK: - Reactions

    /// Toggles the current user's reaction on a message.
    /// Adds if not present; removes if already reacted.
    func toggleReaction(emoji: String, messageId: String) async {
        guard let threadId = activeThreadId,
              let userId = Auth.auth().currentUser?.uid else { return }

        let message = messages.first { $0.id == messageId }
        let hasReacted = message?.reactions[emoji]?.contains(userId) == true

        do {
            if hasReacted {
                try await chatService.removeReaction(
                    emoji: emoji,
                    messageId: messageId,
                    threadId: threadId,
                    spaceId: spaceId
                )
            } else {
                try await chatService.addReaction(
                    emoji: emoji,
                    messageId: messageId,
                    threadId: threadId,
                    spaceId: spaceId
                )
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Typing

    /// Call when the user begins typing in the composer.
    func startTyping() {
        guard let threadId = activeThreadId else { return }
        Task { await chatService.startTyping(threadId: threadId, spaceId: spaceId) }
    }

    /// Call when the user stops typing (on send or idle).
    func stopTyping() {
        guard let threadId = activeThreadId else { return }
        Task { await chatService.stopTyping(threadId: threadId, spaceId: spaceId) }
    }

    // MARK: - Listeners

    /// Starts Firestore + RTDB listeners and bridges updates to @Published properties.
    /// Thread-list listener is already attached by loadThreads().
    /// Message + typing listeners are attached by selectThread().
    func startListening() {
        // Hook provided for future AsyncStream migration.
    }

    /// Removes all listeners and clears ephemeral state.
    func stopListening() {
        chatService.stopListening()
        typingUserIds = []
    }

    // MARK: - Filter

    /// Updates the thread filter and re-applies it over the loaded thread list.
    func setFilter(_ filter: ThreadFilter) {
        chatService.setFilter(filter)
        threads = chatService.threads
    }

    /// Toggles the VIP (starred) status for the current space.
    func toggleVIP() {
        filterService.toggleVIP(spaceId: spaceId)
    }

    /// Marks the active thread as read (updates lastSeenAt + Firestore readState).
    func markActiveThreadRead() {
        guard let threadId = activeThreadId,
              let lastMsg = messages.last else { return }
        let lastId = lastMsg.id
        Task {
            await chatService.markThreadRead(
                threadId: threadId,
                spaceId: spaceId,
                lastMessageId: lastId
            )
            filterService.markSeen(spaceId: spaceId)
        }
    }
}
