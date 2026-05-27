import Foundation

// MARK: - GiveChip

/// Opens the giving flow for the target user / church.
/// Available when NOT on own profile AND:
///   - the user has at least one `.giving` link slot, OR
///   - the user's role flags mark them as a church account.
/// Priority 60.
public struct GiveChip: ActionChip {
    public let id = "give"
    public let label = "Give"
    public let systemImage = "heart.fill"
    public let priority = 60

    public init() {}

    public func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        guard !isOwnProfile else { return false }
        let hasGivingLink = linksStore?.linksByType(.giving).isEmpty == false
        return hasGivingLink || roleFlags.isChurchAccount
    }

    public func routeAction(for targetUserId: String) -> ActionChipRoute {
        .give(targetUserId: targetUserId)
    }
}
