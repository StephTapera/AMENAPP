import Foundation

// MARK: - SubscribeChip

/// Subscribes the viewer to a Creator's content.
/// Only shown when the target user is a creator AND the viewer is not
/// looking at their own profile.
/// Priority 70 — appears last in the default chip order.
public struct SubscribeChip: ActionChip {
    public let id = "subscribe"
    public let label = "Subscribe"
    public let systemImage = "star.fill"
    public let priority = 70

    public init() {}

    public func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        roleFlags.isCreator && !isOwnProfile
    }

    public func routeAction(for targetUserId: String) -> ActionChipRoute {
        .subscribe(targetUserId: targetUserId)
    }
}
