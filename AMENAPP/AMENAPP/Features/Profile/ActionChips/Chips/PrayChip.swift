import Foundation

// MARK: - PrayChip

/// Shown on every profile that is NOT the viewer's own.
/// Priority 10 — appears first in the chip bar.
public struct PrayChip: ActionChip {
    public let id = "pray"
    public let label = "Pray"
    public let systemImage = "hands.sparkles.fill"
    public let priority = 10

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
        .pray(targetUserId: targetUserId)
    }
}
