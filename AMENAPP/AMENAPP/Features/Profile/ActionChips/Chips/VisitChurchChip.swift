import Foundation

// MARK: - VisitChurchChip

/// Deep-links to the church profile page.
/// Visible whenever the target user's role flags contain a `churchId`,
/// regardless of whether the viewer owns the profile.
/// Priority 50.
public struct VisitChurchChip: ActionChip {
    public let id = "visitChurch"
    public let label = "Visit Church"
    public let systemImage = "building.columns.fill"
    public let priority = 50

    public init() {}

    public func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        roleFlags.churchId != nil
    }

    public func routeAction(for targetUserId: String) -> ActionChipRoute {
        // The route carries the churchId when available; callers should
        // retrieve it from roleFlags before calling into navigation.
        // Using targetUserId as a safe fallback so the type stays non-optional.
        .visitChurch(churchId: targetUserId)
    }
}

// MARK: - VisitChurchChip + churchId helper

extension VisitChurchChip {
    /// Preferred route builder that passes the actual church ID when known.
    public func routeAction(churchId: String) -> ActionChipRoute {
        .visitChurch(churchId: churchId)
    }
}
