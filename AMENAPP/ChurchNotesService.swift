//
//  ChurchNotesService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Firebase service for managing church sermon notes
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ChurchNotesService: ObservableObject {
    @Published var notes: [ChurchNote] = []
    @Published var folders: [NoteFolder] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    private var notesListener: ListenerRegistration?
    private var foldersListener: ListenerRegistration?
    
    // P0-3: Cleanup listeners in deinit to prevent memory leaks
    deinit {
        Task { @MainActor in
            self.stopListening()
            print("🧹 ChurchNotesService deallocated, listeners removed")
        }
    }
    
    /// Start real-time listener for notes
    func startListening() {
        guard let userId = firebaseManager.currentUser?.uid else {
            error = "No authenticated user"
            return
        }
        
        print("🔊 Starting real-time listener for church notes...")
        
        notesListener = db.collection("churchNotes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Church notes listener error: \(error)")
                    self.error = error.localizedDescription
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        self.notes = try snapshot.documents.compactMap { document in
                            try document.data(as: ChurchNote.self)
                        }
                        print("✅ Real-time update: \(self.notes.count) church notes")
                    } catch {
                        print("❌ Failed to decode notes: \(error)")
                        self.error = error.localizedDescription
                    }
                }
            }
    }
    
    /// Stop listening to notes
    func stopListening() {
        notesListener?.remove()
        notesListener = nil
        foldersListener?.remove()
        foldersListener = nil
        print("👋 Stopped church notes listener")
    }
    
    // MARK: - Folder Management
    
    /// Start listening to folders
    func startFoldersListening() {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        foldersListener = db.collection("noteFolders")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Folders listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        self.folders = try snapshot.documents.compactMap { document in
                            try document.data(as: NoteFolder.self)
                        }
                        print("✅ Real-time update: \(self.folders.count) folders")
                    } catch {
                        print("❌ Failed to decode folders: \(error)")
                    }
                }
            }
    }
    
    /// Create a new folder
    func createFolder(_ folder: NoteFolder) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var newFolder = folder
        newFolder.userId = userId
        newFolder.createdAt = Date()
        newFolder.updatedAt = Date()
        
        let docRef = db.collection("noteFolders").document()
        newFolder.id = docRef.documentID
        
        try docRef.setData(from: newFolder)
        print("✅ Created folder: \(newFolder.name)")
    }
    
    /// Delete folder
    func deleteFolder(_ folder: NoteFolder) async throws {
        guard let folderId = folder.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Folder ID is missing"])
        }
        
        // Move all notes from this folder to no folder
        let notesInFolder = notes.filter { $0.folderId == folderId }
        for var note in notesInFolder {
            note.folderId = nil
            try await updateNote(note)
        }
        
        try await db.collection("noteFolders").document(folderId).delete()
        print("✅ Deleted folder: \(folder.name)")
    }
    
    /// Move note to folder
    func moveNoteToFolder(_ note: ChurchNote, folderId: String?) async throws {
        var updatedNote = note
        updatedNote.folderId = folderId
        try await updateNote(updatedNote)
    }
    
    /// Get notes in folder
    func getNotesInFolder(_ folderId: String?) -> [ChurchNote] {
        notes.filter { $0.folderId == folderId }
    }
    
    /// Fetch all notes for current user (one-time fetch)
    func fetchNotes() async {
        guard let userId = firebaseManager.currentUser?.uid else {
            error = "No authenticated user"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("churchNotes")
                .whereField("userId", isEqualTo: userId)
                .order(by: "date", descending: true)
                .getDocuments()
            
            notes = try snapshot.documents.compactMap { document in
                try document.data(as: ChurchNote.self)
            }
            
            print("✅ Fetched \(notes.count) church notes")
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to fetch church notes: \(error)")
        }
    }
    
    /// Create a new note
    func createNote(_ note: ChurchNote) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        var newNote = note
        newNote.userId = userId
        newNote.createdAt = Date()
        newNote.updatedAt = Date()
        
        let docRef = db.collection("churchNotes").document()
        newNote.id = docRef.documentID
        
        print("📝 Creating church note: \(newNote.title)")
        print("   User ID: \(userId)")
        print("   Document ID: \(docRef.documentID)")
        
        try docRef.setData(from: newNote)
        
        print("✅ Created church note successfully!")
        
        // Real-time listener will automatically update the notes array
    }
    
    /// Update an existing note with optimistic concurrency control
    func updateNote(_ note: ChurchNote) async throws {
        guard let noteId = note.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Note ID is missing"])
        }
        
        // P0-2: Use transaction for optimistic concurrency control
        try await db.runTransaction { transaction, errorPointer in
            let ref = self.db.collection("churchNotes").document(noteId)
            
            do {
                let snapshot = try transaction.getDocument(ref)
                
                guard snapshot.exists else {
                    let error = NSError(
                        domain: "ChurchNotesService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Note not found"]
                    )
                    errorPointer?.pointee = error
                    return nil
                }
                
                // Check version for conflict detection
                let currentVersion = snapshot.data()?["version"] as? Int ?? 0
                
                if currentVersion != note.version {
                    let error = NSError(
                        domain: "ChurchNotesService",
                        code: 409,
                        userInfo: [
                            NSLocalizedDescriptionKey: "This note was updated by someone else. Please refresh and try again.",
                            "isConflict": true
                        ]
                    )
                    errorPointer?.pointee = error
                    print("⚠️ Version conflict detected: current=\(currentVersion), expected=\(note.version)")
                    return nil
                }
                
                // Update with incremented version
                var updatedNote = note
                updatedNote.version = currentVersion + 1
                updatedNote.updatedAt = Date()
                
                try transaction.setData(from: updatedNote, forDocument: ref)
                
                print("✅ Updated church note: \(note.title) (version: \(updatedNote.version))")
                
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        
        // Real-time listener will automatically update
    }
    
    /// Delete a note
    func deleteNote(_ note: ChurchNote) async throws {
        guard let noteId = note.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Note ID is missing"])
        }
        
        try await db.collection("churchNotes").document(noteId).delete()
        
        print("✅ Deleted church note: \(note.title)")
        
        // Real-time listener will automatically update
    }
    
    /// Toggle favorite status
    func toggleFavorite(_ note: ChurchNote) async throws {
        guard let noteId = note.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Note ID is missing"])
        }
        
        var updatedNote = note
        updatedNote.isFavorite.toggle()
        updatedNote.updatedAt = Date()
        
        try db.collection("churchNotes").document(noteId).setData(from: updatedNote, merge: true)
        
        print("✅ Toggled favorite for note: \(note.title)")
        
        // Real-time listener will automatically update
    }
    
    /// Search notes by query
    func searchNotes(query: String) -> [ChurchNote] {
        guard !query.isEmpty else { return notes }
        
        let lowercased = query.lowercased()
        return notes.filter { note in
            note.title.lowercased().contains(lowercased) ||
            note.content.lowercased().contains(lowercased) ||
            note.sermonTitle?.lowercased().contains(lowercased) ?? false ||
            note.pastor?.lowercased().contains(lowercased) ?? false ||
            note.churchName?.lowercased().contains(lowercased) ?? false ||
            note.tags.contains { $0.lowercased().contains(lowercased) }
        }
    }
    
    /// Filter notes by tag
    func filterByTag(_ tag: String) -> [ChurchNote] {
        notes.filter { $0.tags.contains(tag) }
    }
    
    /// Get favorite notes
    func getFavorites() -> [ChurchNote] {
        notes.filter { $0.isFavorite }
    }
    
    // MARK: - Sorting
    
    /// Sort notes by option
    func sortNotes(_ notes: [ChurchNote], by sortOption: NoteSortOption) -> [ChurchNote] {
        switch sortOption {
        case .dateNewest:
            return notes.sorted { $0.date > $1.date }
        case .dateOldest:
            return notes.sorted { $0.date < $1.date }
        case .titleAZ:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .church:
            return notes.sorted { ($0.churchName ?? "") < ($1.churchName ?? "") }
        }
    }
    
    // MARK: - Bulk Actions
    
    /// Bulk delete notes
    func bulkDelete(_ notes: [ChurchNote]) async throws {
        for note in notes {
            try await deleteNote(note)
        }
        print("✅ Bulk deleted \(notes.count) notes")
    }
    
    /// Bulk favorite/unfavorite notes
    func bulkToggleFavorite(_ notes: [ChurchNote], favorite: Bool) async throws {
        for var note in notes {
            if note.isFavorite != favorite {
                note.isFavorite = favorite
                try await updateNote(note)
            }
        }
        print("✅ Bulk updated \(notes.count) notes")
    }
    
    /// Bulk move to folder
    func bulkMoveToFolder(_ notes: [ChurchNote], folderId: String?) async throws {
        for note in notes {
            try await moveNoteToFolder(note, folderId: folderId)
        }
        print("✅ Bulk moved \(notes.count) notes to folder")
    }
    
    /// Bulk export notes
    func bulkExport(_ notes: [ChurchNote]) -> String {
        var exportText = "🙏 Selected Church Notes from AMEN\n"
        exportText += "Exported: \(Date().formatted(date: .long, time: .shortened))\n"
        exportText += "Total Notes: \(notes.count)\n\n"
        exportText += String(repeating: "=", count: 50)
        exportText += "\n\n"
        
        for (index, note) in notes.enumerated() {
            exportText += "[\(index + 1)] \(generateShareText(for: note))\n\n"
            exportText += String(repeating: "-", count: 50)
            exportText += "\n\n"
        }
        
        return exportText
    }
    
    // MARK: - Share & Export
    
    /// Generate shareable text from note
    func generateShareText(for note: ChurchNote) -> String {
        var text = "📖 \(note.title)\n\n"
        
        if let sermonTitle = note.sermonTitle {
            text += "Sermon: \(sermonTitle)\n"
        }
        if let pastor = note.pastor {
            text += "Pastor: \(pastor)\n"
        }
        if let churchName = note.churchName {
            text += "Church: \(churchName)\n"
        }
        
        text += "Date: \(note.date.formatted(date: .long, time: .omitted))\n"
        
        if !note.scriptureReferences.isEmpty {
            text += "Scripture: \(note.scriptureReferences.joined(separator: ", "))\n"
        }
        
        text += "\n---\n\n"
        text += note.content
        
        if !note.tags.isEmpty {
            text += "\n\n🏷️ Tags: \(note.tags.joined(separator: ", "))"
        }
        
        text += "\n\n✨ Shared from AMEN App"
        
        return text
    }
    
    /// Bulk export all notes
    func exportAllNotes() -> String {
        var exportText = "🙏 My Church Notes from AMEN\n"
        exportText += "Exported: \(Date().formatted(date: .long, time: .shortened))\n"
        exportText += "Total Notes: \(notes.count)\n\n"
        exportText += String(repeating: "=", count: 50)
        exportText += "\n\n"
        
        for (index, note) in notes.enumerated() {
            exportText += "[\(index + 1)] \(generateShareText(for: note))\n\n"
            exportText += String(repeating: "-", count: 50)
            exportText += "\n\n"
        }
        
        return exportText
    }
    
    // MARK: - Permissions & Sharing
    
    /// Update note permission
    func updatePermission(_ note: ChurchNote, permission: NotePermission) async throws {
        var updatedNote = note
        updatedNote.permission = permission
        updatedNote.updatedAt = Date()
        try await updateNote(updatedNote)
        print("✅ Updated permission for note: \(note.title) to \(permission.rawValue)")
    }
    
    /// Share note with specific users (replaces existing shared list)
    func shareNoteWith(_ note: ChurchNote, userIds: [String]) async throws {
        var updatedNote = note
        updatedNote.sharedWith = userIds
        updatedNote.permission = .shared
        updatedNote.updatedAt = Date()
        try await updateNote(updatedNote)
        print("✅ Shared note with \(userIds.count) users")
    }
    
    /// Share note with additional users (adds to existing shared list)
    func shareWithUsers(note: ChurchNote, userIds: [String]) async throws {
        guard let currentUser = firebaseManager.currentUser else {
            throw FirebaseError.unauthorized
        }
        
        var updatedNote = note
        // Merge with existing sharedWith array, avoiding duplicates
        let existingShared = Set(updatedNote.sharedWith)
        let newShared = Set(userIds)
        let newlySharedUsers = Array(newShared.subtracting(existingShared))
        
        updatedNote.sharedWith = Array(existingShared.union(newShared))
        updatedNote.permission = .shared
        updatedNote.updatedAt = Date()
        try await updateNote(updatedNote)
        print("✅ Shared note with \(userIds.count) additional users (total: \(updatedNote.sharedWith.count))")
        
        // Send notifications to newly shared users
        if !newlySharedUsers.isEmpty {
            await NotificationService.shared.sendChurchNoteSharedNotifications(
                noteId: updatedNote.id ?? "",
                noteTitle: updatedNote.title,
                recipientIds: newlySharedUsers,
                sharerId: currentUser.uid,
                sharerName: currentUser.displayName ?? "Someone",
                sharerUsername: nil  // Username will be fetched from user profile if needed
            )
        }
    }
    
    /// Get shared notes (notes shared with current user)
    func getSharedNotes() async throws -> [ChurchNote] {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let snapshot = try await db.collection("churchNotes")
            .whereField("sharedWith", arrayContains: userId)
            .getDocuments()
        
        let sharedNotes = try snapshot.documents.compactMap { document in
            try document.data(as: ChurchNote.self)
        }
        
        print("✅ Found \(sharedNotes.count) notes shared with you")
        return sharedNotes
    }
    
    /// Get public notes from community
    func getPublicNotes(limit: Int = 20) async throws -> [ChurchNote] {
        let snapshot = try await db.collection("churchNotes")
            .whereField("permission", isEqualTo: NotePermission.publicNote.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let publicNotes = try snapshot.documents.compactMap { document in
            try document.data(as: ChurchNote.self)
        }
        
        print("✅ Found \(publicNotes.count) public notes")
        return publicNotes
    }
}
