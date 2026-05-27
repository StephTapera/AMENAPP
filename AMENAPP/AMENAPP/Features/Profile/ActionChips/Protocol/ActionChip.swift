import Foundation

// MARK: - ActionChipRoute

/// Navigation destinations emitted by the chip bar.
/// Consumed by Agent G (Profile Header integration) to drive navigation.
public enum ActionChipRoute {
    case pray(targetUserId: String)
    case message(targetUserId: String)
    case verse(targetUserId: String)
    case bereanAbout(targetUserId: String)
    case visitChurch(churchId: String)
    case give(targetUserId: String)
    case subscribe(targetUserId: String)
}

// MARK: - ActionChip Protocol

/// A single chip displayed in the profile header chip bar.
/// Each concrete chip type encapsulates its own availability logic,
/// keeping `ActionChipResolver` free of conditional branching.
public protocol ActionChip: Identifiable {
    /// Stable identifier used by `ForEach` and diffing.
    var id: String { get }

    /// Short button label shown below the icon.
    var label: String { get }

    /// SF Symbol name for the chip icon.
    var systemImage: String { get }

    /// Lower numbers appear first in the chip bar.
    var priority: Int { get }

    /// Async availability check. Called once per resolver pass.
    /// - Parameters:
    ///   - roleFlags:         Role badges from Firestore for the *target* profile.
    ///   - bereanAboutOptIn:  Whether the target user opted into Berean About visibility.
    ///   - linksStore:        Optional store of the target user's link slots.
    ///   - isOwnProfile:      `true` when the viewer is looking at their own profile.
    func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool

    /// Maps the chip to the `ActionChipRoute` it should fire when tapped.
    func routeAction(for targetUserId: String) -> ActionChipRoute
}
