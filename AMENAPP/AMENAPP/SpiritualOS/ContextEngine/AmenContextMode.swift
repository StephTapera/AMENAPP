import Foundation

// MARK: - AmenContextMode
// Five-state mode enum used by AmenContextOrchestrator and HomeView banners.
// Distinct from SOContextMode (which has different, fewer states).

enum AmenContextMode: String, CaseIterable, Codable {
    case standard
    case driving
    case church
    case travel
    case event
}

// MARK: - Notification.Name

extension Notification.Name {
    /// Posted whenever AmenContextOrchestrator detects a mode change.
    /// The `object` parameter contains the new `AmenContextMode` value.
    static let amenContextModeChanged = Notification.Name("AmenContextModeChanged")
}
