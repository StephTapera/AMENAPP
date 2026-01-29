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
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let db = Firestore.firestore()
    
    /// Fetch all notes for current user
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
        
        try docRef.setData(from: newNote)
        
        print("✅ Created church note: \(newNote.title)")
        
        await fetchNotes()
    }
    
    /// Update an existing note
    func updateNote(_ note: ChurchNote) async throws {
        guard let noteId = note.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Note ID is missing"])
        }
        
        var updatedNote = note
        updatedNote.updatedAt = Date()
        
        try db.collection("churchNotes").document(noteId).setData(from: updatedNote, merge: true)
        
        print("✅ Updated church note: \(note.title)")
        
        await fetchNotes()
    }
    
    /// Delete a note
    func deleteNote(_ note: ChurchNote) async throws {
        guard let noteId = note.id else {
            throw NSError(domain: "ChurchNotesService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Note ID is missing"])
        }
        
        try await db.collection("churchNotes").document(noteId).delete()
        
        print("✅ Deleted church note: \(note.title)")
        
        await fetchNotes()
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
        
        await fetchNotes()
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
}
