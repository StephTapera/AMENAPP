//
//  ChurchNotesChecklistService.swift
//  AMENAPP
//
//  Feature 3: Spiritual Checklists
//  Manages personal action-oriented checklists attached to church notes.
//  Persists to Firestore: users/{uid}/churchNotes/{noteId}/checklists
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Checklist Item Type

enum ChecklistItemType: String, Codable, CaseIterable, Identifiable {
    case prayAbout       = "prayAbout"
    case followUp        = "followUp"
    case memorizeVerse   = "memorizeVerse"
    case askPastor       = "askPastor"
    case applyBySunday   = "applyBySunday"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prayAbout:     return "Pray About"
        case .followUp:      return "Follow Up"
        case .memorizeVerse: return "Memorize Verse"
        case .askPastor:     return "Ask Pastor"
        case .applyBySunday: return "Apply by Sunday"
        }
    }

    var systemImage: String {
        switch self {
        case .prayAbout:     return "hands.sparkles"
        case .followUp:      return "arrow.uturn.right"
        case .memorizeVerse: return "book.pages"
        case .askPastor:     return "person.wave.2"
        case .applyBySunday: return "calendar.badge.checkmark"
        }
    }
}

// MARK: - ChecklistItem

struct ChecklistItem: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var type: ChecklistItemType
    var isCompleted: Bool
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        text: String,
        type: ChecklistItemType = .followUp,
        isCompleted: Bool = false,
        dueDate: Date? = nil
    ) {
        self.id          = id
        self.text        = text
        self.type        = type
        self.isCompleted = isCompleted
        self.dueDate     = dueDate
        self.createdAt   = Date()
        self.completedAt = nil
    }

    // Custom Codable to handle optional fields gracefully
    enum CodingKeys: String, CodingKey {
        case id, text, type, isCompleted, dueDate, createdAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text           = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        type           = try c.decodeIfPresent(ChecklistItemType.self, forKey: .type) ?? .followUp
        isCompleted    = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        dueDate        = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt      = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt    = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

// MARK: - ChurchNotesChecklist

struct ChurchNotesChecklist: Identifiable, Codable {
    var id: String
    var noteId: String
    var items: [ChecklistItem]
    var createdAt: Date
    var updatedAt: Date

    init(noteId: String, items: [ChecklistItem] = []) {
        self.id        = UUID().uuidString
        self.noteId    = noteId
        self.items     = items
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Checklist Service

@MainActor
final class ChurchNotesChecklistService: ObservableObject {
    static let shared = ChurchNotesChecklistService()

    @Published var checklists: [String: ChurchNotesChecklist] = [:]   // keyed by noteId
    @Published var isLoading = false
    @Published var lastError: Error?

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Firestore Path

    private func checklistRef(noteId: String, userId: String) -> CollectionReference {
        db.collection("users")
          .document(userId)
          .collection("churchNotes")
          .document(noteId)
          .collection("checklists")
    }

    // MARK: - Load Checklist

    func loadChecklist(for noteId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Remove existing listener for this noteId if any
        listeners[noteId]?.remove()

        let ref = checklistRef(noteId: noteId, userId: uid)
        let listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.lastError = error
                    return
                }
                guard let docs = snapshot?.documents else { return }

                var items: [ChecklistItem] = []
                for doc in docs {
                    if let item = try? doc.data(as: ChecklistItem.self) {
                        items.append(item)
                    }
                }
                items.sort { $0.createdAt < $1.createdAt }

                var checklist = self.checklists[noteId] ?? ChurchNotesChecklist(noteId: noteId)
                checklist.items = items
                checklist.updatedAt = Date()
                self.checklists[noteId] = checklist
            }
        }
        listeners[noteId] = listener
    }

    // MARK: - Add Item

    func addItem(
        _ text: String,
        type: ChecklistItemType = .followUp,
        dueDate: Date? = nil,
        to noteId: String
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ChecklistError.notAuthenticated
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChecklistError.emptyText
        }

        let item = ChecklistItem(text: text, type: type, dueDate: dueDate)
        let ref  = checklistRef(noteId: noteId, userId: uid).document(item.id)

        let data = try Firestore.Encoder().encode(item)
        try await ref.setData(data)
    }

    // MARK: - Toggle Complete

    func toggleComplete(itemId: String, in noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ChecklistError.notAuthenticated
        }

        guard var checklist = checklists[noteId],
              let index = checklist.items.firstIndex(where: { $0.id == itemId }) else {
            throw ChecklistError.itemNotFound
        }

        var item = checklist.items[index]
        item.isCompleted = !item.isCompleted
        item.completedAt = item.isCompleted ? Date() : nil

        let ref  = checklistRef(noteId: noteId, userId: uid).document(itemId)
        let data = try Firestore.Encoder().encode(item)
        try await ref.setData(data)

        // Optimistic local update
        checklist.items[index] = item
        checklists[noteId] = checklist
    }

    // MARK: - Delete Item

    func deleteItem(itemId: String, from noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ChecklistError.notAuthenticated
        }

        let ref = checklistRef(noteId: noteId, userId: uid).document(itemId)
        try await ref.delete()

        // Optimistic local remove
        checklists[noteId]?.items.removeAll { $0.id == itemId }
    }

    // MARK: - Update Item Text

    func updateText(_ text: String, itemId: String, in noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ChecklistError.notAuthenticated
        }

        guard var checklist = checklists[noteId],
              let index = checklist.items.firstIndex(where: { $0.id == itemId }) else {
            throw ChecklistError.itemNotFound
        }

        var item = checklist.items[index]
        item.text = text

        let ref  = checklistRef(noteId: noteId, userId: uid).document(itemId)
        try await ref.updateData(["text": text])

        checklist.items[index] = item
        checklists[noteId] = checklist
    }

    // MARK: - Cleanup

    func stopListening(for noteId: String) {
        listeners[noteId]?.remove()
        listeners.removeValue(forKey: noteId)
    }
}

// MARK: - Errors

enum ChecklistError: LocalizedError {
    case notAuthenticated
    case emptyText
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to manage checklists."
        case .emptyText:        return "Checklist item text cannot be empty."
        case .itemNotFound:     return "Checklist item not found."
        }
    }
}
