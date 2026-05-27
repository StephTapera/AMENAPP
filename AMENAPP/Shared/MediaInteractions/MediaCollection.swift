import Foundation
import FirebaseFirestore

/// A named bucket that groups saved media items (e.g. "Devotionals", "Sermons", "Worship").
/// Named `MediaCollection` rather than `Collection` to avoid shadowing Swift's `Collection` protocol.
struct MediaCollection: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var name: String
    /// SF Symbol name used as the collection icon.
    var icon: String
    /// Hex color string for the collection accent (e.g. "#F0C96E").
    var color: String
    var itemCount: Int
    var createdAt: Date

    init(
        id: String? = nil,
        userId: String,
        name: String,
        icon: String = "folder.fill",
        color: String = "#F0C96E",
        itemCount: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.icon = icon
        self.color = color
        self.itemCount = itemCount
        self.createdAt = createdAt
    }
}
