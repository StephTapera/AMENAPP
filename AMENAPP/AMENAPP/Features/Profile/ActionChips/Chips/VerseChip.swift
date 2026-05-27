import Foundation

// MARK: - SendVerseChip

/// Sends a Bible verse to the target user.
/// Priority 30 — appears after Message in the chip bar.
/// Renamed from VerseChip to avoid conflict with the search-UI VerseChip in AISearchEnhancements.swift.
struct SendVerseChip: ActionChip {
    let id = "verse"
    let label = "Verse"
    let systemImage = "book.fill"
    let priority = 30

    init() {}

    func isAvailable(
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        isOwnProfile: Bool
    ) async -> Bool {
        !isOwnProfile
    }

    func routeAction(for targetUserId: String) -> ActionChipRoute {
        .verse(targetUserId: targetUserId)
    }
}
