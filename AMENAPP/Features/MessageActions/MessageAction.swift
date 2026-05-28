import SwiftUI

// MARK: - Placement

/// Where an action is rendered in the action sheet hierarchy.
enum MessageActionPlacement {
    /// Horizontal emoji scroll strip at the top of the sheet.
    case quickReaction
    /// Large cards in the 2-column grid below the reaction strip.
    case primaryCard
    /// Standard icon-label rows, visible without expanding.
    case standard
    /// Rows hidden behind "More Actions" expander.
    case more
}

// MARK: - MessageAction

/// Every possible action a user can take on a message.
/// The capability matrix decides which subset appears for any given context.
enum MessageAction: String, CaseIterable, Identifiable {
    case react
    case replyInThread
    case save
    case unsave
    case forward
    case copyText
    case copyLink
    case markUnread
    case remindMe
    case muteThread
    case unmuteThread
    case dontGetReplyNotifications
    case prayForThis
    case unprayForThis
    case sendToBerean
    case saveToNotes
    case shareToPrayerWall
    case pinToChannel
    case unpin
    case makeAnnouncement
    case edit
    case delete
    case removeAsAdmin
    case report
    case blockUser
    case selectText
    case translate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .react:                      return "Add Reaction"
        case .replyInThread:              return "Reply in Thread"
        case .save:                       return "Save Message"
        case .unsave:                     return "Unsave"
        case .forward:                    return "Forward"
        case .copyText:                   return "Copy Text"
        case .copyLink:                   return "Copy Link"
        case .markUnread:                 return "Mark as Unread"
        case .remindMe:                   return "Remind Me"
        case .muteThread:                 return "Mute Thread"
        case .unmuteThread:               return "Unmute Thread"
        case .dontGetReplyNotifications:  return "Don't Notify for Replies"
        case .prayForThis:                return "Pray for This"
        case .unprayForThis:              return "Remove Prayer"
        case .sendToBerean:               return "Send to Berean"
        case .saveToNotes:                return "Save to Notes"
        case .shareToPrayerWall:          return "Share to Prayer Wall"
        case .pinToChannel:               return "Pin to Channel"
        case .unpin:                      return "Unpin"
        case .makeAnnouncement:           return "Make Announcement"
        case .edit:                       return "Edit Message"
        case .delete:                     return "Delete Message"
        case .removeAsAdmin:              return "Remove Message"
        case .report:                     return "Report Message"
        case .blockUser:                  return "Block User"
        case .selectText:                 return "Select Text"
        case .translate:                  return "Translate"
        }
    }

    var systemImage: String {
        switch self {
        case .react:                      return "face.smiling"
        case .replyInThread:              return "bubble.left.and.bubble.right"
        case .save:                       return "bookmark"
        case .unsave:                     return "bookmark.slash"
        case .forward:                    return "arrowshape.turn.up.right"
        case .copyText:                   return "doc.on.doc"
        case .copyLink:                   return "link"
        case .markUnread:                 return "circle"
        case .remindMe:                   return "alarm"
        case .muteThread:                 return "bell.slash"
        case .unmuteThread:               return "bell"
        case .dontGetReplyNotifications:  return "bell.badge.slash"
        case .prayForThis:                return "hands.sparkles"
        case .unprayForThis:              return "hands.sparkles.fill"
        case .sendToBerean:               return "text.book.closed"
        case .saveToNotes:                return "note.text"
        case .shareToPrayerWall:          return "heart.text.square"
        case .pinToChannel:               return "pin"
        case .unpin:                      return "pin.slash"
        case .makeAnnouncement:           return "megaphone"
        case .edit:                       return "pencil"
        case .delete:                     return "trash"
        case .removeAsAdmin:              return "person.badge.minus"
        case .report:                     return "flag"
        case .blockUser:                  return "hand.raised"
        case .selectText:                 return "text.cursor"
        case .translate:                  return "character.bubble"
        }
    }

    var tintColor: Color {
        switch self {
        case .delete, .blockUser, .removeAsAdmin:
            return .red
        case .report:
            return .orange
        case .prayForThis, .unprayForThis, .makeAnnouncement:
            return Color("amenGold")
        case .sendToBerean:
            return Color("amenPurple")
        case .shareToPrayerWall:
            return Color("amenBlue")
        default:
            return .primary
        }
    }

    var isDestructive: Bool {
        switch self {
        case .delete, .blockUser, .removeAsAdmin: return true
        default: return false
        }
    }

    /// Whether to show a "NEW" badge next to this action label.
    var isNew: Bool {
        switch self {
        case .prayForThis, .sendToBerean, .saveToNotes, .shareToPrayerWall: return true
        default: return false
        }
    }

    var placement: MessageActionPlacement {
        switch self {
        case .react:
            return .quickReaction
        case .replyInThread, .save, .unsave, .edit, .delete:
            return .primaryCard
        case .copyText, .copyLink, .prayForThis, .unprayForThis,
             .sendToBerean, .saveToNotes, .markUnread, .forward, .translate:
            return .standard
        case .remindMe, .muteThread, .unmuteThread, .dontGetReplyNotifications,
             .selectText, .pinToChannel, .unpin, .makeAnnouncement,
             .report, .blockUser, .removeAsAdmin, .shareToPrayerWall:
            return .more
        }
    }
}
