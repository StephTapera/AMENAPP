import Foundation

struct AmenSmartAttachmentActionDecision: Equatable {
    let actions: [AmenSmartAttachmentAction]
    let maxVisibleCompactActions: Int
    let debugReason: String
}

enum AmenSmartAttachmentSurface {
    case composer
    case feed
    case detail
    case expandedSheet
    case selah
    case churchNotes
}

enum AmenSmartAttachmentActionEngine {
    static func decide(
        attachment: AmenSmartAttachment,
        postText: String,
        surface: AmenSmartAttachmentSurface
    ) -> AmenSmartAttachmentActionDecision {
        let text = "\(attachment.title) \(attachment.description ?? "") \(postText)".lowercased()

        if attachment.safetyStatus == .blocked {
            return AmenSmartAttachmentActionDecision(actions: [], maxVisibleCompactActions: 0, debugReason: "blocked")
        }

        if attachment.safetyStatus == .limited {
            return AmenSmartAttachmentActionDecision(actions: [.open, .report], maxVisibleCompactActions: 1, debugReason: "limited")
        }

        var actions = attachment.smartActions

        if attachment.provider == .youtube,
           text.contains("sermon") || text.contains("teaching") || text.contains("bible study") || text.contains("devotional") {
            actions.insert(.addToChurchNotes, at: 0)
        }

        if attachment.type == .song,
           text.contains("prayer") || text.contains("worship") || text.contains("reflection") || text.contains("quiet time") {
            actions.insert(.saveToSelah, at: 0)
        }

        if attachment.type == .article || attachment.type == .podcast || attachment.type == .video {
            actions.insert(.saveForLater, at: 0)
        }

        return AmenSmartAttachmentActionDecision(
            actions: Array(NSOrderedSet(array: actions)) as? [AmenSmartAttachmentAction] ?? actions,
            maxVisibleCompactActions: surface == .feed ? 1 : 3,
            debugReason: "rule_based"
        )
    }
}
