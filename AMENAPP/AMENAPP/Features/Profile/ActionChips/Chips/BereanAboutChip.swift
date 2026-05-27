import Foundation

// MARK: - BereanAboutChip

/// Shows an AI-powered "Berean About" summary for the target user.
/// Only visible when the target user has opted in to the feature
/// and the viewer is not on their own profile.
/// Priority 40.
public struct BereanAboutChip: ActionChip {
    public let id = "bereanAbout"
    public let label = "Berean About"
    public let systemImage = "person.crop.circle.badge.questionmark"
    public let priority = 40

    public init() {}

    public func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        bereanAboutOptIn && !isOwnProfile
    }

    public func routeAction(for targetUserId: String) -> ActionChipRoute {
        .bereanAbout(targetUserId: targetUserId)
    }
}
