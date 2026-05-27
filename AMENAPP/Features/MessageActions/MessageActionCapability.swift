import Foundation

// MARK: - MessageActionCapability

/// Pure function: given a context, return the ordered action list.
/// No side effects, no I/O — safe to call on any thread.
enum MessageActionCapability {

    /// Returns actions in the order they should be displayed.
    /// Call sites may further filter for display purposes, but must not re-order.
    static func actions(for context: MessageActionContext) -> [MessageAction] {

        // System messages (join/leave/pin notices) get a minimal set.
        if context.isSystemMessage {
            return [.react, .copyText, context.isSaved ? .unsave : .save, .report]
        }

        var result: [MessageAction] = []

        // ── Quick-reaction row ────────────────────────────────────────────────
        result.append(.react)

        // ── Primary cards (max 4; first two are universal) ───────────────────
        result.append(.replyInThread)
        result.append(context.isSaved ? .unsave : .save)

        // Own message primary cards
        if context.isOwnMessage {
            if context.isWithinEditWindow {
                result.append(.edit)
            }
            result.append(.delete)
        }

        // ── Standard rows ────────────────────────────────────────────────────
        result.append(.copyText)
        result.append(.copyLink)
        result.append(context.hasPrayed ? .unprayForThis : .prayForThis)
        result.append(.sendToBerean)
        result.append(.saveToNotes)
        result.append(.markUnread)
        result.append(.forward)
        result.append(.translate)

        // Others' message standard actions
        if !context.isOwnMessage {
            result.append(.report)
            result.append(.blockUser)
        }

        // ── Group / Discussion-only rows ─────────────────────────────────────
        if context.surface.isGroupLike {
            if context.isPrayerTagged {
                result.append(.shareToPrayerWall)
            }
            if context.currentUserRole.canPin {
                result.append(context.message.isPinned ? .unpin : .pinToChannel)
            }
            if context.currentUserRole.canAnnounce {
                result.append(.makeAnnouncement)
            }
            // Admins/leaders can remove any message that isn't their own.
            if context.currentUserRole.canRemoveOthers && !context.isOwnMessage {
                result.append(.removeAsAdmin)
            }
        }

        // ── More drawer ───────────────────────────────────────────────────────
        result.append(.remindMe)
        result.append(context.isMutedThread ? .unmuteThread : .muteThread)
        result.append(.dontGetReplyNotifications)
        result.append(.selectText)

        return result
    }
}
