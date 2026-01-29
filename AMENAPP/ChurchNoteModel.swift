//
//  ChurchNoteModel.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Model for church sermon notes with Firebase integration
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Represents a note taken during a church service or sermon
struct ChurchNote: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var sermonTitle: String?
    var churchName: String?
    var pastor: String?
    var date: Date
    var content: String
    var scripture: String?
    var keyPoints: [String]
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case sermonTitle
        case churchName
        case pastor
        case date
        case content
        case scripture
        case keyPoints
        case tags
        case isFavorite
        case createdAt
        case updatedAt
    }
    
    init(
        id: String? = nil,
        userId: String,
        title: String,
        sermonTitle: String? = nil,
        churchName: String? = nil,
        pastor: String? = nil,
        date: Date = Date(),
        content: String = "",
        scripture: String? = nil,
        keyPoints: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.sermonTitle = sermonTitle
        self.churchName = churchName
        self.pastor = pastor
        self.date = date
        self.content = content
        self.scripture = scripture
        self.keyPoints = keyPoints
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

