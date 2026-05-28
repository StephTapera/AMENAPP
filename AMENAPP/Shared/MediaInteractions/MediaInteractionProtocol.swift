import Foundation

/// Common interface for any record that represents a user interaction with a media item.
/// Conform new interaction types here; feature agents import this protocol for generic handling.
protocol MediaInteraction: Identifiable, Codable {
    var id: String? { get }
    var mediaId: String { get }
    var userId: String { get }
    var createdAt: Date { get }
}
