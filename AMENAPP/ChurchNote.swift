//
//  ChurchNote.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Church Note Model with Firebase integration
//

import Foundation
import FirebaseFirestore

/// A worship song reference saved inside a Church Note.
/// Lightweight — only stores the identifiers needed to reconstruct playback.
struct WorshipSongReference: Codable, Identifiable, Hashable {
    var id: String           // UUID, locally generated
    var title: String
    var artist: String
    var musicKitID: String?  // MusicKit catalog ID for direct playback
    var appleMusicURL: String?
    var albumArtURL: String?
    var addedAt: Date

    init(title: String, artist: String, musicKitID: String? = nil,
         appleMusicURL: String? = nil, albumArtURL: String? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.artist = artist
        self.musicKitID = musicKitID
        self.appleMusicURL = appleMusicURL
        self.albumArtURL = albumArtURL
        self.addedAt = Date()
    }
}

enum NotePermission: String, Codable {
    case privateNote = "private"
    case shared = "shared"
    case publicNote = "public"
}

enum NoteSortOption: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case titleAZ = "Title A-Z"
    case titleZA = "Title Z-A"
    case church = "Church"
}

struct ChurchNote: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var sermonTitle: String?
    var churchName: String?
    var churchId: String?  // Firestore church document ID for querying
    var pastor: String?
    var date: Date
    var content: String
    var scripture: String?
    var keyPoints: [String]
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    
    // P0-2: Optimistic concurrency control
    var version: Int // Version number for conflict detection
    
    // New features
    var folderId: String? // For organizing notes into folders
    var permission: NotePermission // Privacy setting
    var sharedWith: [String] // UserIDs of people note is shared with
    var scriptureReferences: [String] // Array of scripture references
    var shareLinkId: String? // Unique ID for deep linking and sharing
    var worshipSongs: [WorshipSongReference] // Songs linked to this note
    var visitPlanId: String? // Link back to visit plan (bidirectional)

    // Coding keys for Firestore
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case sermonTitle
        case churchName
        case churchId
        case pastor
        case date
        case content
        case scripture
        case keyPoints
        case tags
        case isFavorite
        case createdAt
        case updatedAt
        case version
        case folderId
        case permission
        case sharedWith
        case scriptureReferences
        case shareLinkId
        case worshipSongs
        case visitPlanId
    }
    
    // Initializer with defaults
    init(
        id: String? = nil,
        userId: String,
        title: String,
        sermonTitle: String? = nil,
        churchName: String? = nil,
        churchId: String? = nil,
        pastor: String? = nil,
        date: Date = Date(),
        content: String,
        scripture: String? = nil,
        keyPoints: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        version: Int = 0,
        folderId: String? = nil,
        permission: NotePermission = .privateNote,
        sharedWith: [String] = [],
        scriptureReferences: [String] = [],
        shareLinkId: String? = nil,
        worshipSongs: [WorshipSongReference] = [],
        visitPlanId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.sermonTitle = sermonTitle
        self.churchName = churchName
        self.churchId = churchId
        self.pastor = pastor
        self.date = date
        self.content = content
        self.scripture = scripture
        self.keyPoints = keyPoints
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.folderId = folderId
        self.permission = permission
        self.sharedWith = sharedWith
        self.scriptureReferences = scriptureReferences
        // Generate share link ID if not provided
        self.shareLinkId = shareLinkId ?? UUID().uuidString
        self.worshipSongs = worshipSongs
        self.visitPlanId = visitPlanId
    }
    
    // Custom Decodable init to handle older Firestore documents that were created
    // before newer fields (version, permission, sharedWith, etc.) were added.
    // Using decodeIfPresent with safe defaults prevents "keyNotFound" crashes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(String.self, forKey: .id)
        userId             = try c.decode(String.self, forKey: .userId)
        title              = try c.decode(String.self, forKey: .title)
        sermonTitle        = try c.decodeIfPresent(String.self, forKey: .sermonTitle)
        churchName         = try c.decodeIfPresent(String.self, forKey: .churchName)
        churchId           = try c.decodeIfPresent(String.self, forKey: .churchId)
        pastor             = try c.decodeIfPresent(String.self, forKey: .pastor)
        date               = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        content            = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        scripture          = try c.decodeIfPresent(String.self, forKey: .scripture)
        keyPoints          = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        tags               = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite         = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt          = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt          = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        version            = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        folderId           = try c.decodeIfPresent(String.self, forKey: .folderId)
        permission         = try c.decodeIfPresent(NotePermission.self, forKey: .permission) ?? .privateNote
        sharedWith         = try c.decodeIfPresent([String].self, forKey: .sharedWith) ?? []
        scriptureReferences = try c.decodeIfPresent([String].self, forKey: .scriptureReferences) ?? []
        shareLinkId        = try c.decodeIfPresent(String.self, forKey: .shareLinkId) ?? UUID().uuidString
        worshipSongs       = try c.decodeIfPresent([WorshipSongReference].self, forKey: .worshipSongs) ?? []
        visitPlanId        = try c.decodeIfPresent(String.self, forKey: .visitPlanId)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ChurchNote, rhs: ChurchNote) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Preview Helpers
extension ChurchNote {
    static var preview: ChurchNote {
        ChurchNote(
            userId: "preview-user",
            title: "The Power of Prayer",
            sermonTitle: "Mountain Moving Faith",
            churchName: "Grace Community Church",
            pastor: "Pastor John Smith",
            date: Date(),
            content: "Today's sermon was incredibly powerful. Pastor John spoke about the importance of prayer and how it can move mountains in our lives. Key takeaways:\n\n1. Prayer is not just asking, it's also listening\n2. Faith without works is dead\n3. God's timing is perfect\n\nI was particularly moved by the story about the widow's persistence. It reminded me that I need to be more consistent in my prayer life.",
            scripture: "Matthew 17:20",
            keyPoints: [
                "Prayer is conversation with God",
                "Faith requires action",
                "Persistence in prayer"
            ],
            tags: ["prayer", "faith", "sermon"],
            isFavorite: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    static var previews: [ChurchNote] {
        [
            ChurchNote(
                userId: "preview-user",
                title: "The Power of Prayer",
                sermonTitle: "Mountain Moving Faith",
                churchName: "Grace Community Church",
                pastor: "Pastor John Smith",
                date: Date(),
                content: "Today's sermon was incredibly powerful. Key takeaways about prayer and faith.",
                scripture: "Matthew 17:20",
                keyPoints: ["Prayer", "Faith", "Action"],
                tags: ["prayer", "faith"],
                isFavorite: true
            ),
            ChurchNote(
                userId: "preview-user",
                title: "God's Love Never Fails",
                sermonTitle: "Unconditional Love",
                churchName: "Hope Fellowship",
                pastor: "Pastor Sarah Johnson",
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                content: "Powerful message about God's unfailing love for us.",
                scripture: "Romans 8:38-39",
                keyPoints: ["God's love", "Grace", "Forgiveness"],
                tags: ["love", "grace"],
                isFavorite: false
            ),
            ChurchNote(
                userId: "preview-user",
                title: "Walking by Faith",
                sermonTitle: "Trust in the Lord",
                churchName: "New Life Church",
                pastor: "Pastor Michael Brown",
                date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                content: "Learning to trust God even when we can't see the path ahead.",
                scripture: "2 Corinthians 5:7",
                keyPoints: ["Faith", "Trust", "Obedience"],
                tags: ["faith", "trust"],
                isFavorite: true
            )
        ]
    }
}
