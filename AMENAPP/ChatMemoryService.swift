import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Chat Memory Service
/// Persistence and state management for chat memory items.
/// Firestore path: users/{uid}/chatMemory/{chatId}/items/{itemId}

@MainActor
final class ChatMemoryService: ObservableObject {
    static let shared = ChatMemoryService()

    @Published private(set) var memoryItems: [ChatMemoryItem] = []
    @Published private(set) var suggestions: [ChatMemorySuggestion] = []
    @Published private(set) var settings: ChatMemorySettings = .default
    @Published private(set) var isLoading = false

    var activeCount: Int {
        memoryItems.filter { $0.consentState == .accepted || $0.consentState == .pending }.count
    }

    var calendarSuggestionCount: Int {
        memoryItems.filter { $0.calendarState == .pending }.count
    }

    private var currentChatId: String?
    private var listener: ListenerRegistration?
    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Lifecycle

    /// Load memory items for a specific chat conversation.
    func loadItems(for chatId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        currentChatId = chatId
        isLoading = true

        // Remove any existing listener
        listener?.remove()

        // Set up real-time listener
        let ref = db.collection("users").document(uid)
            .collection("chatMemory").document(chatId)
            .collection("items")
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                dlog("⚠️ [ChatMemory] Listener error: \(error.localizedDescription)")
                self.isLoading = false
                return
            }

            guard let documents = snapshot?.documents else {
                self.isLoading = false
                return
            }

            let items = documents.compactMap { doc -> ChatMemoryItem? in
                try? doc.data(as: ChatMemoryItem.self)
            }

            self.memoryItems = items
            self.isLoading = false
        }
    }

    /// Load settings for the current user.
    func loadSettings() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid)
                .collection("preferences").document("chatMemory")
                .getDocument()
            if doc.exists, let data = try? doc.data(as: ChatMemorySettings.self) {
                settings = data
            }
        } catch {
            dlog("⚠️ [ChatMemory] Failed to load settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Save / Accept Suggestion

    /// Convert a suggestion into a persisted memory item.
    func saveSuggestion(_ suggestion: ChatMemorySuggestion, chatId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let item = ChatMemoryItem(
            id: suggestion.id,
            chatId: chatId,
            sourceMessageIds: suggestion.sourceMessageIds,
            type: suggestion.type,
            title: suggestion.title,
            summary: suggestion.summary,
            confidence: suggestion.confidence,
            consentState: .accepted,
            visibility: .personal,
            dueDate: suggestion.extractedDate,
            calendarState: suggestion.extractedDate != nil ? .pending : .none,
            calendarEventId: nil,
            participants: [uid],
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try db.collection("users").document(uid)
                .collection("chatMemory").document(chatId)
                .collection("items").document(item.id)
                .setData(from: item)
            dlog("✅ [ChatMemory] Saved item: \(item.title)")
        } catch {
            dlog("⚠️ [ChatMemory] Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - Dismiss

    /// Dismiss a memory item (mark as dismissed, won't resurface).
    func dismiss(_ item: ChatMemoryItem) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db.collection("users").document(uid)
                .collection("chatMemory").document(item.chatId)
                .collection("items").document(item.id)
                .updateData([
                    "consentState": MemoryConsentState.dismissed.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            dlog("⚠️ [ChatMemory] Failed to dismiss: \(error.localizedDescription)")
        }
    }

    // MARK: - Resolve

    /// Mark a memory item as resolved/completed.
    func resolve(_ item: ChatMemoryItem) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db.collection("users").document(uid)
                .collection("chatMemory").document(item.chatId)
                .collection("items").document(item.id)
                .updateData([
                    "consentState": MemoryConsentState.archived.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            dlog("⚠️ [ChatMemory] Failed to resolve: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    /// Permanently delete a memory item.
    func delete(_ item: ChatMemoryItem) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await db.collection("users").document(uid)
                .collection("chatMemory").document(item.chatId)
                .collection("items").document(item.id)
                .delete()
        } catch {
            dlog("⚠️ [ChatMemory] Failed to delete: \(error.localizedDescription)")
        }
    }

    // MARK: - Calendar State

    /// Update the calendar state for a memory item.
    func updateCalendarState(_ item: ChatMemoryItem, state: CalendarSuggestionState, eventId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var updates: [String: Any] = [
            "calendarState": state.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let eventId {
            updates["calendarEventId"] = eventId
        }

        do {
            try await db.collection("users").document(uid)
                .collection("chatMemory").document(item.chatId)
                .collection("items").document(item.id)
                .updateData(updates)
        } catch {
            dlog("⚠️ [ChatMemory] Failed to update calendar state: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    /// Save updated settings.
    func saveSettings(_ newSettings: ChatMemorySettings) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        settings = newSettings

        do {
            try db.collection("users").document(uid)
                .collection("preferences").document("chatMemory")
                .setData(from: newSettings)
        } catch {
            dlog("⚠️ [ChatMemory] Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup

    /// Remove Firestore listener and clear local state.
    func cleanup() {
        listener?.remove()
        listener = nil
        currentChatId = nil
        memoryItems.removeAll()
        suggestions.removeAll()
    }

    /// Items filtered for a specific tab.
    func items(for tab: ChatMemoryTab) -> [ChatMemoryItem] {
        let validTypes = Set(tab.matchingTypes)
        return memoryItems.filter { item in
            validTypes.contains(item.type) &&
            (item.consentState == .accepted || item.consentState == .pending)
        }
    }
}
