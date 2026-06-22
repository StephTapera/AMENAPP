//
//  ChurchNotesFolderService.swift
//  AMENAPP
//
//  Personal journal folder system for Church Notes.
//  Stored in Firestore: users/{uid}/churchNoteFolders/
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Color Theme

/// Color theme for a folder — each color carries spiritual meaning
enum NoteColorTheme: String, Codable, CaseIterable {
    case gold       // revelation / key truth
    case blue       // peace / prayer / reflection
    case green      // growth / obedience / habits
    case red        // conviction / warning / repentance
    case purple     // calling / identity / spiritual authority
    case gray       // archive / old season
    case teal       // church visits / new churches
    case amber      // questions / things to study later

    var displayName: String { rawValue.capitalized }

    var meaning: String {
        switch self {
        case .gold:   return "Revelation & key truth"
        case .blue:   return "Peace, prayer & reflection"
        case .green:  return "Growth & obedience"
        case .red:    return "Conviction & repentance"
        case .purple: return "Calling & identity"
        case .gray:   return "Archive"
        case .teal:   return "Church visits"
        case .amber:  return "Questions to study"
        }
    }

    var swiftUIColor: String {
        switch self {
        case .gold:   return "#D4A017"
        case .blue:   return "#4A90D9"
        case .green:  return "#5BA85A"
        case .red:    return "#C0392B"
        case .purple: return "#7D3C98"
        case .gray:   return "#95A5A6"
        case .teal:   return "#1ABC9C"
        case .amber:  return "#F39C12"
        }
    }
}

// MARK: - Note Type

/// Note type — defines the format and purpose
enum NoteType: String, Codable, CaseIterable {
    case sermonNote          = "Sermon Note"
    case personalReflection  = "Personal Reflection"
    case bibleStudy          = "Bible Study"
    case prayerEntry         = "Prayer Entry"
    case bereanConversation  = "Berean Conversation"
    case churchVisit         = "Church Visit"
    case worshipReflection   = "Worship Reflection"

    var icon: String {
        switch self {
        case .sermonNote:         return "mic.fill"
        case .personalReflection: return "heart.text.square.fill"
        case .bibleStudy:         return "book.fill"
        case .prayerEntry:        return "hands.sparkles.fill"
        case .bereanConversation: return "sparkles"
        case .churchVisit:        return "mappin.circle.fill"
        case .worshipReflection:  return "music.note"
        }
    }
}

// MARK: - ChurchNoteFolder Model

struct ChurchNoteFolder: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var colorTheme: NoteColorTheme
    var icon: String = "folder.fill"
    var noteCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isDefault: Bool = false

    static let defaultFolders: [ChurchNoteFolder] = [
        ChurchNoteFolder(
            id: "sunday_sermons",
            name: "Sunday Sermons",
            colorTheme: .gold,
            icon: "sun.max.fill",
            isDefault: true
        ),
        ChurchNoteFolder(
            id: "prayer_journal",
            name: "Prayer Journal",
            colorTheme: .blue,
            icon: "hands.sparkles.fill",
            isDefault: true
        ),
        ChurchNoteFolder(
            id: "bible_study",
            name: "Bible Study",
            colorTheme: .green,
            icon: "book.fill",
            isDefault: true
        ),
        ChurchNoteFolder(
            id: "things_god_teaching",
            name: "Things God Is Teaching Me",
            colorTheme: .purple,
            icon: "sparkles",
            isDefault: true
        ),
    ]
}

// MARK: - ChurchNotesFolderService

@MainActor
final class ChurchNotesFolderService: ObservableObject {
    static let shared = ChurchNotesFolderService()

    @Published var folders: [ChurchNoteFolder] = []
    @Published var isLoaded: Bool = false

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    deinit {
        listener?.remove()
    }

    // MARK: - Firestore Path

    private func foldersCollection(for uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("churchNoteFolders")
    }

    // MARK: - Listening

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("ChurchNotesFolderService: no authenticated user")
            return
        }

        listener?.remove()

        listener = foldersCollection(for: uid)
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("ChurchNotesFolderService listener error: \(error)")
                    return
                }
                guard let snapshot else { return }

                let decoded: [ChurchNoteFolder] = snapshot.documents.compactMap { doc in
                    try? doc.data(as: ChurchNoteFolder.self)
                }
                self.folders = decoded
                self.isLoaded = true
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - CRUD

    func createFolder(_ folder: ChurchNoteFolder) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try foldersCollection(for: uid)
                .document(folder.id)
                .setData(from: folder)
        } catch {
            dlog("ChurchNotesFolderService createFolder error: \(error)")
        }
    }

    func updateFolder(_ folder: ChurchNoteFolder) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var updated = folder
        updated.updatedAt = Date()
        do {
            try foldersCollection(for: uid)
                .document(folder.id)
                .setData(from: updated, merge: true)
        } catch {
            dlog("ChurchNotesFolderService updateFolder error: \(error)")
        }
    }

    func deleteFolder(_ id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await foldersCollection(for: uid).document(id).delete()
        } catch {
            dlog("ChurchNotesFolderService deleteFolder error: \(error)")
        }
    }

    func reorderFolders(_ ordered: [ChurchNoteFolder]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let batch = db.batch()
        for (index, folder) in ordered.enumerated() {
            let ref = foldersCollection(for: uid).document(folder.id)
            batch.updateData(["sortOrder": index], forDocument: ref)
        }
        do {
            try await batch.commit()
        } catch {
            dlog("ChurchNotesFolderService reorderFolders error: \(error)")
        }
    }

    // MARK: - Default Folder Bootstrap

    /// Ensure default folders exist for new users.
    /// Only creates defaults if the folder count is 0.
    func ensureDefaultFolders() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await foldersCollection(for: uid).getDocuments()
            guard snapshot.documents.isEmpty else { return }

            for (index, var folder) in ChurchNoteFolder.defaultFolders.enumerated() {
                folder.sortOrder = index
                await createFolder(folder)
            }
            dlog("ChurchNotesFolderService: default folders created")
        } catch {
            dlog("ChurchNotesFolderService ensureDefaultFolders error: \(error)")
        }
    }

    // MARK: - Note Count

    /// Count notes in a folder by querying churchNotes where folderId matches.
    func noteCount(for folderId: String) async -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }
        do {
            let snapshot = try await db.collection("churchNotes")
                .whereField("userId", isEqualTo: uid)
                .whereField("folderId", isEqualTo: folderId)
                .getDocuments()
            return snapshot.documents.count
        } catch {
            dlog("ChurchNotesFolderService noteCount error: \(error)")
            return 0
        }
    }
}
