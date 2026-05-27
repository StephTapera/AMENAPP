import Foundation

// MARK: - ActionChipResolver

/// Instantiates all registered chips, runs their async availability checks
/// concurrently, filters to those that are available, then sorts by priority.
///
/// Add new chip types to `allChips` — no other changes needed.
@MainActor
public final class ActionChipResolver {

    // MARK: Init

    public init() {}

    // MARK: Resolve

    /// Returns the ordered, filtered list of chips to display in the chip bar.
    /// - Parameters:
    ///   - targetUserId:      Firestore UID of the profile being viewed.
    ///   - roleFlags:         Role metadata for the target user.
    ///   - bereanAboutOptIn:  Whether the target user opted into Berean About.
    ///   - linksStore:        Target user's link slots (may be `nil` if not loaded).
    ///   - viewerIsOwner:     `true` when the current user is viewing their own profile.
    /// - Returns: Chips sorted ascending by `priority`, all guaranteed available.
    public func resolve(
        targetUserId: String,
        roleFlags: ProfileRoleFlags,
        bereanAboutOptIn: Bool,
        linksStore: ProfileLinksStore?,
        viewerIsOwner: Bool
    ) async -> [any ActionChip] {
        let chips: [any ActionChip] = [
            PrayChip(),
            MessageChip(),
            SendVerseChip(),
            BereanAboutChip(),
            VisitChurchChip(),
            GiveChip(),
            SubscribeChip()
        ]

        // Run availability checks concurrently using a task group.
        return await withTaskGroup(of: (chip: any ActionChip, available: Bool).self) { group in
            for chip in chips {
                group.addTask {
                    let available = await chip.isAvailable(
                        roleFlags: roleFlags,
                        bereanAboutOptIn: bereanAboutOptIn,
                        linksStore: linksStore,
                        isOwnProfile: viewerIsOwner
                    )
                    return (chip: chip, available: available)
                }
            }

            var results: [any ActionChip] = []
            for await result in group where result.available {
                results.append(result.chip)
            }

            return results.sorted { $0.priority < $1.priority }
        }
    }
}
