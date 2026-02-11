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

struct ChurchNote: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let userId: String
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
    
    // Coding keys for Firestore
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
    
    // Initializer with defaults
    init(
        id: String? = nil,
        userId: String,
        title: String,
        sermonTitle: String? = nil,
        churchName: String? = nil,
        pastor: String? = nil,
        date: Date = Date(),
        content: String,
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
            id: UUID().uuidString,
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
                id: "1",
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
                id: "2",
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
                id: "3",
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
