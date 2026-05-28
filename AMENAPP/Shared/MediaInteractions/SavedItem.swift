import Foundation
import FirebaseFirestore

/// A record that a user has bookmarked a media item, optionally into a named collection.
struct SavedItem: Identifiable, Codable, MediaInteraction {
    @DocumentID var id: String?
    var mediaId: String
    var userId: String
    /// Firestore ID of the parent `MediaCollection`; nil places the item in the root saved list.
    var collectionId: String?
    var savedAt: Date
    /// Optional annotation the user wrote when saving.
    var note: String?

    var createdAt: Date { savedAt }

    init(
        id: String? = nil,
        mediaId: String,
        userId: String,
        collectionId: String? = nil,
        savedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.userId = userId
        self.collectionId = collectionId
        self.savedAt = savedAt
        self.note = note
    }
}
