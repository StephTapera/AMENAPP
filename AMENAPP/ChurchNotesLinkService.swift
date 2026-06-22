//
//  ChurchNotesLinkService.swift
//  AMENAPP
//
//  Feature 6: Inter-Note Linking
//  Allows users to create typed links between church notes.
//  Persists to Firestore: users/{uid}/noteLinks
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

// MARK: - Link Type

enum NoteLinkType: String, Codable, CaseIterable, Identifiable {
    case sermon     = "sermon"
    case prayer     = "prayer"
    case testimony  = "testimony"
    case series     = "series"
    case study      = "study"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sermon:    return "Sermon Connection"
        case .prayer:    return "Prayer Link"
        case .testimony: return "Testimony"
        case .series:    return "Part of Series"
        case .study:     return "Bible Study"
        }
    }

    var systemImage: String {
        switch self {
        case .sermon:    return "text.book.closed.fill"
        case .prayer:    return "hands.sparkles"
        case .testimony: return "person.fill.checkmark"
        case .series:    return "link.circle.fill"
        case .study:     return "magnifyingglass.circle"
        }
    }
}

// MARK: - Note Link

struct NoteLink: Identifiable, Codable, Hashable {
    var id: String
    var sourceNoteId: String
    var targetNoteId: String
    var targetTitle: String
    var linkType: NoteLinkType
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        sourceNoteId: String,
        targetNoteId: String,
        targetTitle: String,
        linkType: NoteLinkType = .sermon
    ) {
        self.id           = id
        self.sourceNoteId = sourceNoteId
        self.targetNoteId = targetNoteId
        self.targetTitle  = targetTitle
        self.linkType     = linkType
        self.createdAt    = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, sourceNoteId, targetNoteId, targetTitle, linkType, createdAt
    }

    init(from decoder: Decoder) throws {
        let c         = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceNoteId  = try c.decodeIfPresent(String.self, forKey: .sourceNoteId) ?? ""
        targetNoteId  = try c.decodeIfPresent(String.self, forKey: .targetNoteId) ?? ""
        targetTitle   = try c.decodeIfPresent(String.self, forKey: .targetTitle) ?? ""
        linkType      = try c.decodeIfPresent(NoteLinkType.self, forKey: .linkType) ?? .sermon
        createdAt     = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - Note Link Service

@MainActor
final class ChurchNotesLinkService: ObservableObject {
    static let shared = ChurchNotesLinkService()

    @Published var links: [NoteLink] = []
    @Published var isLoading = false
    @Published var lastError: Error?

    private let db       = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Firestore Path

    private func linksCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("noteLinks")
    }

    // MARK: - Start Listening

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()

        listener = linksCollection(userId: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.lastError = error
                        return
                    }
                    self.links = snapshot?.documents.compactMap { doc in
                        try? doc.data(as: NoteLink.self)
                    } ?? []
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Link Notes

    func linkNotes(
        from sourceNoteId: String,
        to targetNote: ChurchNote,
        type: NoteLinkType
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NoteLinkError.notAuthenticated
        }
        guard let targetId = targetNote.id else {
            throw NoteLinkError.invalidNote
        }
        guard sourceNoteId != targetId else {
            throw NoteLinkError.selfLink
        }
        // Prevent duplicate links of same type between same notes
        let duplicate = links.first {
            $0.sourceNoteId == sourceNoteId &&
            $0.targetNoteId == targetId &&
            $0.linkType == type
        }
        if duplicate != nil { throw NoteLinkError.duplicateLink }

        let link = NoteLink(
            sourceNoteId: sourceNoteId,
            targetNoteId: targetId,
            targetTitle:  targetNote.title,
            linkType:     type
        )

        let ref  = linksCollection(userId: uid).document(link.id)
        let data = try Firestore.Encoder().encode(link)
        try await ref.setData(data)
    }

    // MARK: - Get Links For Note

    /// Returns all links where this note is either source or target.
    func getLinksFor(noteId: String) -> [NoteLink] {
        links.filter { $0.sourceNoteId == noteId || $0.targetNoteId == noteId }
    }

    // MARK: - Remove Link

    func removeLink(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NoteLinkError.notAuthenticated
        }
        let ref = linksCollection(userId: uid).document(id)
        try await ref.delete()

        links.removeAll { $0.id == id }
    }
}

// MARK: - Note Link Picker ViewModel

@MainActor
final class NoteLinkPickerViewModel: ObservableObject {
    @Published var searchText       = ""
    @Published var selectedLinkType: NoteLinkType = .sermon
    @Published var filteredNotes: [ChurchNote] = []

    private var allNotes: [ChurchNote] = []

    func load(notes: [ChurchNote], excluding noteId: String?) {
        allNotes = notes.filter { $0.id != noteId }
        filterNotes()
    }

    func filterNotes() {
        if searchText.isEmpty {
            filteredNotes = allNotes.sorted { $0.date > $1.date }
        } else {
            let q = searchText.lowercased()
            filteredNotes = allNotes.filter {
                $0.title.lowercased().contains(q) ||
                ($0.sermonTitle ?? "").lowercased().contains(q) ||
                ($0.churchName ?? "").lowercased().contains(q)
            }.sorted { $0.date > $1.date }
        }
    }
}

// MARK: - Errors

enum NoteLinkError: LocalizedError {
    case notAuthenticated
    case invalidNote
    case selfLink
    case duplicateLink

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to link notes."
        case .invalidNote:      return "The target note has not been saved yet."
        case .selfLink:         return "A note cannot be linked to itself."
        case .duplicateLink:    return "These notes are already linked with this type."
        }
    }
}
