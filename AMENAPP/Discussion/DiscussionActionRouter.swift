// DiscussionActionRouter.swift — AMEN App
import Foundation
import FirebaseRemoteConfig

enum DiscussionAction: String, CaseIterable, Sendable {
    case markHelpful, share, shareToSpaces, report, reply, copyText, pin, delete

    var label: String {
        switch self {
        case .markHelpful:   return "Mark Helpful"
        case .share:         return "Share"
        case .shareToSpaces: return "Share to Spaces"
        case .report:        return "Report"
        case .reply:         return "Reply"
        case .copyText:      return "Copy Text"
        case .pin:           return "Pin"
        case .delete:        return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .markHelpful:   return "hand.thumbsup"
        case .share:         return "square.and.arrow.up"
        case .shareToSpaces: return "person.3"
        case .report:        return "exclamationmark.triangle"
        case .reply:         return "arrowshape.turn.up.left"
        case .copyText:      return "doc.on.doc"
        case .pin:           return "pin"
        case .delete:        return "trash"
        }
    }

    var isDestructive: Bool { self == .delete || self == .report }
}

@MainActor
final class DiscussionActionRouter {
    static let shared = DiscussionActionRouter()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_actions_enabled").boolValue
    }

    func availableActions(isOwnComment: Bool, isElder: Bool) -> [DiscussionAction] {
        guard isEnabled else { return [.markHelpful, .share] }
        var actions: [DiscussionAction] = [.markHelpful, .reply, .share, .copyText]
        if isElder        { actions.append(.pin) }
        if isOwnComment   { actions.append(.delete) }
        else              { actions.append(.report) }
        return actions
    }
}
