import Foundation
import FirebaseFirestore

/// A canonical scripture reference pinned to a reaction, comment, or post.
/// The Cloud Function `attachVerse` validates and populates `text` from the KJV index.
struct VerseAttachment: Identifiable, Codable {
    @DocumentID var id: String?
    /// Human-readable reference, e.g. "John 3:16".
    var reference: String
    /// Bible translation used (e.g. "KJV", "NIV").
    var translation: String
    /// Full verse text returned by the server.
    var text: String
    /// Firestore ID of the parent document (reaction, comment, or post).
    var attachedToId: String
    var attachedToType: VerseAttachmentTarget
    var createdAt: Date

    init(
        id: String? = nil,
        reference: String,
        translation: String = "KJV",
        text: String = "",
        attachedToId: String,
        attachedToType: VerseAttachmentTarget,
        createdAt: Date = .now
    ) {
        self.id = id
        self.reference = reference
        self.translation = translation
        self.text = text
        self.attachedToId = attachedToId
        self.attachedToType = attachedToType
        self.createdAt = createdAt
    }
}

enum VerseAttachmentTarget: String, Codable, CaseIterable {
    case reaction, comment, post
}
