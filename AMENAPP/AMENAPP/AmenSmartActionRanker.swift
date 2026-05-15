import Foundation

// MARK: - Ranked Action Set

struct AmenRankedActionSet: Equatable {
    let compactActions: [AmenSmartAttachmentAction]    // 1-3 for feed/card
    let expandedActions: [AmenSmartAttachmentAction]   // all for sheet/detail
    let primaryAction: AmenSmartAttachmentAction?
    let surfaceLabel: String
}

// MARK: - AmenSmartActionRanker

/// Converts a context decision into a surface-appropriate ranked action set.
/// Compact surfaces (feed) get at most 2 actions. Expanded surfaces get all.
enum AmenSmartActionRanker {
    static func rank(
        decision: AmenContextDecision,
        surface: AmenSmartAttachmentSurface
    ) -> AmenRankedActionSet {
        if decision.safetyTreatment == .blocked {
            return AmenRankedActionSet(
                compactActions: [],
                expandedActions: [],
                primaryAction: nil,
                surfaceLabel: "Restricted"
            )
        }

        if decision.safetyTreatment == .limited {
            return AmenRankedActionSet(
                compactActions: [.open],
                expandedActions: [.open, .report],
                primaryAction: .open,
                surfaceLabel: "Limited Preview"
            )
        }

        let primary = decision.primaryAction
        var all: [AmenSmartAttachmentAction] = []
        if let p = primary { all.append(p) }
        for a in decision.secondaryActions where !all.contains(a) {
            all.append(a)
        }

        // Always offer share in expanded surfaces
        if (surface == .expandedSheet || surface == .detail), !all.contains(.share) {
            all.append(.share)
        }

        // Feed/composer: max 2 actions
        let compact: [AmenSmartAttachmentAction]
        switch surface {
        case .feed, .composer:
            compact = Array(all.prefix(2))
        case .selah, .churchNotes:
            compact = Array(all.prefix(1))
        case .detail, .expandedSheet:
            compact = all
        }

        return AmenRankedActionSet(
            compactActions: compact,
            expandedActions: all,
            primaryAction: primary,
            surfaceLabel: decision.smartLabel
        )
    }

    // MARK: - Display Helpers

    static func displayTitle(for action: AmenSmartAttachmentAction) -> String {
        switch action {
        case .open: return "Open"
        case .listen: return "Listen"
        case .watch: return "Watch"
        case .saveToSelah: return "Save to Selah"
        case .addToChurchNotes: return "Add to Notes"
        case .saveForLater: return "Save for Later"
        case .share: return "Share"
        case .startGroupDiscussion: return "Discuss"
        case .report: return "Report"
        case .hide: return "Hide"
        }
    }

    static func systemIcon(for action: AmenSmartAttachmentAction) -> String {
        switch action {
        case .open: return "arrow.up.right.square"
        case .listen: return "headphones"
        case .watch: return "play.circle"
        case .saveToSelah: return "sparkles"
        case .addToChurchNotes: return "note.text.badge.plus"
        case .saveForLater: return "bookmark"
        case .share: return "square.and.arrow.up"
        case .startGroupDiscussion: return "bubble.left.and.bubble.right"
        case .report: return "flag"
        case .hide: return "eye.slash"
        }
    }
}
