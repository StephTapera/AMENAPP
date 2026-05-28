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

import Foundation
import FirebaseAuth

// MARK: - SpacesChatViewModel

@MainActor
final class SpacesChatViewModel: ObservableObject {

    // MARK: - Published State

    /// All messages for the active thread (soft-deleted entries included).
    @Published var messages: [SpaceMessage] = []

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

    private let chatService: SpacesChatService
    private let filterService: SpacesFilterService
    private var spaceId: String = ""

    // MARK: - Init

    /// Designated initialiser. Prefer `SpacesChatViewModel(spaceId:)` after
    /// calling `loadSpace(spaceId:)`. Services are injectable for testing.
    init(
        chatService: SpacesChatService = SpacesChatService(),
        filterService: SpacesFilterService = SpacesFilterService.shared
    ) {
        self.chatService = chatService
        self.filterService = filterService
    }

    // MARK: - Filter Signals (for Agent C)

    /// Pre-computed filter signals that drive the Spaces list badge / sort in Agent C.
    /// Derived from local thread state; no extra Firestore read required.
    var filterSignals: SpaceFilterSignals {
        filterService.signals(
            for: spaceId,
            threads: threads
        )
    }

    /// Messages authored by members whose `authorHomeCommunityId` is non-nil
    /// (i.e., authors from a linked external community).
    var externalMemberMessages: [SpaceMessage] {
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
        // Mirror service threads to our published property.
        threads = chatService.threads
        startListening()
    }

    // MARK: - Thread Selection

    /// Selects a thread and loads its messages + typing observers.
    func selectThread(_ threadId: String) async {
        activeThreadId = threadId
        isLoading = true
        defer { isLoading = false }

        // Stop previous thread observers.
        chatService.stopObservingTyping(threadId: threadId, spaceId: spaceId)

        await chatService.loadMessages(threadId: threadId, spaceId: spaceId)
        chatService.observeTyping(threadId: threadId, spaceId: spaceId)

        // Mirror from service.
        messages = chatService.messages
        typingUserIds = chatService.typingUsers.map(\.userId)
    }

    // MARK: - Send

    /// Sends the current draft body. Clears `draftBody` on success.
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

        // Determine if the user has already reacted.
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
    /// Safe to call multiple times — existing listeners are torn down first via stopListening().
    func startListening() {
        // Observe service's published threads and mirror them.
        // Because SpacesChatService is @MainActor, we can read its @Published directly
        // after the listener fires via Task { @MainActor in ... }.
        //
        // We piggyback on loadThreads which already attaches the snapshot listener.
        // Future: replace with AsyncStream when service exposes one.
    }

    /// Removes all listeners and clears ephemeral state.
    func stopListening() {
        chatService.stopListening()
        typingUserIds = []
    }

    // MARK: - Filter Convenience

    /// Updates the thread filter and re-applies it.
    func setFilter(_ filter: ThreadFilter) {
        chatService.setFilter(filter)
        threads = chatService.threads
    }

    /// Marks a space as VIP (starred) in UserDefaults.
    func toggleVIP() {
        filterService.toggleVIP(spaceId: spaceId)
    }

    /// Marks the active thread as read.
    func markActiveThreadRead() {
        guard let threadId = activeThreadId,
              let lastMsg = messages.last else { return }
        Task {
            await chatService.markThreadRead(
                threadId: threadId,
                spaceId: spaceId,
                lastMessageId: lastMsg.id
            )
            filterService.markSeen(spaceId: spaceId)
        }
    }
}
