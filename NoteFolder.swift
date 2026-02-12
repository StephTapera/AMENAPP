//
//  NoteFolder.swift
//  AMENAPP
//
//  Folder/Collection model for organizing church notes
//

import Foundation
import FirebaseFirestore

struct NoteFolder: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var userId: String
    var name: String
    var icon: String // SF Symbol name
    var color: String // Hex color code
    var noteCount: Int
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case name
        case icon
        case color
        case noteCount
        case createdAt
        case updatedAt
    }
    
    init(
        id: String? = nil,
        userId: String,
        name: String,
        icon: String = "folder.fill",
        color: String = "#007AFF",
        noteCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.icon = icon
        self.color = color
        self.noteCount = noteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: NoteFolder, rhs: NoteFolder) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Default Folders
extension NoteFolder {
    static func defaultFolders(for userId: String) -> [NoteFolder] {
        [
            NoteFolder(userId: userId, name: "Sermons", icon: "mic.fill", color: "#FF9500"),
            NoteFolder(userId: userId, name: "Bible Study", icon: "book.fill", color: "#5856D6"),
            NoteFolder(userId: userId, name: "Prayer Meeting", icon: "hands.sparkles.fill", color: "#34C759"),
            NoteFolder(userId: userId, name: "Small Group", icon: "person.3.fill", color: "#007AFF")
        ]
    }
}
