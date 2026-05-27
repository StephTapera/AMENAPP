import Foundation

// MARK: - MessageChip

/// Opens a direct-message thread with the target user.
/// Priority 20 — appears after Pray in the chip bar.
public struct MessageChip: ActionChip {
    public let id = "message"
    public let label = "Message"
    public let systemImage = "bubble.left.fill"
    public let priority = 20

    public init() {}

    public func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        !isOwnProfile
    }

    public func routeAction(for targetUserId: String) -> ActionChipRoute {
        .message(targetUserId: targetUserId)
    }
}
