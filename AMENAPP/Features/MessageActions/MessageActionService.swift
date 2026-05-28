import Foundation
import FirebaseFirestore

// MARK: - Errors

enum MessageActionError: Error, LocalizedError {
    case notImplemented
    case unauthorized
    case messageNotFound
    case editWindowExpired
    case pinLimitReached(current: Int, max: Int)
    case networkError(Error)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "This action is not yet available."
        case .unauthorized:
            return "You don't have permission to do that."
        case .messageNotFound:
            return "This message could not be found."
        case .editWindowExpired:
            return "Messages can only be edited within 15 minutes of sending."
        case .pinLimitReached(let current, let max):
            return "This channel already has \(current) of \(max) pinned messages. Unpin one first."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        }
    }
}

// MARK: - Prayer Wall Visibility

enum PrayerWallVisibility: String, CaseIterable {
    case `public`  = "public"
    case friends   = "friends"
    case `private` = "private"
}

// MARK: - Protocol

/// All possible async operations the action sheet can trigger.
/// Each operation corresponds to one or more `MessageAction` cases.
/// Conformers handle Firestore writes; the UI only calls into this surface.
protocol MessageActionService: AnyObject {

    // MARK: Reactions
    func react(emoji: String, to message: AppMessage, in context: MessageActionContext) async throws
    func removeReaction(emoji: String, from message: AppMessage, in context: MessageActionContext) async throws

    // MARK: Thread
    func replyInThread(to message: AppMessage, in context: MessageActionContext) async throws

    // MARK: Clipboard
    func copyText(of message: AppMessage) async throws
    func copyLink(to message: AppMessage, in context: MessageActionContext) async throws

    // MARK: Save
    func save(message: AppMessage, in context: MessageActionContext) async throws
    func unsave(message: AppMessage, in context: MessageActionContext) async throws
    func isSaved(messageId: String, userId: String) async -> Bool

    // MARK: Status
    func markUnread(message: AppMessage, in context: MessageActionContext) async throws
    func forward(message: AppMessage, in context: MessageActionContext) async throws

    // MARK: AMEN-native
    func prayForThis(message: AppMessage, in context: MessageActionContext) async throws
    func unprayForThis(message: AppMessage, in context: MessageActionContext) async throws
    func hasPrayed(for messageId: String, userId: String) async -> Bool
    func sendToBerean(message: AppMessage, in context: MessageActionContext) async throws
    func saveToNotes(message: AppMessage, in context: MessageActionContext) async throws
    func shareToPrayerWall(message: AppMessage, in context: MessageActionContext, visibility: PrayerWallVisibility) async throws

    // MARK: Personal
    func setReminder(for message: AppMessage, in context: MessageActionContext, fireAt: Date) async throws
    func muteThread(message: AppMessage, in context: MessageActionContext) async throws
    func unmuteThread(message: AppMessage, in context: MessageActionContext) async throws
    func isThreadMuted(messageId: String, userId: String) async -> Bool

    // MARK: Own-message moderation
    func edit(message: AppMessage, newText: String, in context: MessageActionContext) async throws
    func deleteOwn(message: AppMessage, in context: MessageActionContext) async throws

    // MARK: Admin moderation
    func removeAsAdmin(message: AppMessage, reason: String, in context: MessageActionContext) async throws
    func report(message: AppMessage, reason: ModerationReportReason, note: String?, in context: MessageActionContext) async throws
    func blockUser(userId: String, from context: MessageActionContext) async throws
    func pinToChannel(message: AppMessage, in context: MessageActionContext) async throws
    func unpin(message: AppMessage, in context: MessageActionContext) async throws
    func makeAnnouncement(message: AppMessage, in context: MessageActionContext) async throws
}

// MARK: - Stub Implementation

/// Stub implementation — all methods log and throw `.notImplemented`.
/// Replaced method-by-method in Agents 3–6.
@MainActor
final class FirebaseMessageActionService: MessageActionService {

    static let shared = FirebaseMessageActionService()
    private let db = Firestore.firestore()
    private init() {}

    func react(emoji: String, to message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] react \(emoji) on \(message.id)"); throw MessageActionError.notImplemented
    }
    func removeReaction(emoji: String, from message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] removeReaction \(emoji) on \(message.id)"); throw MessageActionError.notImplemented
    }
    func replyInThread(to message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] replyInThread \(message.id)"); throw MessageActionError.notImplemented
    }
    func copyText(of message: AppMessage) async throws {
        dlog("📋 [STUB] copyText \(message.id)"); throw MessageActionError.notImplemented
    }
    func copyLink(to message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] copyLink \(message.id)"); throw MessageActionError.notImplemented
    }
    func save(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] save \(message.id)"); throw MessageActionError.notImplemented
    }
    func unsave(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] unsave \(message.id)"); throw MessageActionError.notImplemented
    }
    func isSaved(messageId: String, userId: String) async -> Bool { false }

    func markUnread(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] markUnread \(message.id)"); throw MessageActionError.notImplemented
    }
    func forward(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] forward \(message.id)"); throw MessageActionError.notImplemented
    }
    func prayForThis(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] prayForThis \(message.id)"); throw MessageActionError.notImplemented
    }
    func unprayForThis(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] unprayForThis \(message.id)"); throw MessageActionError.notImplemented
    }
    func hasPrayed(for messageId: String, userId: String) async -> Bool { false }

    func sendToBerean(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] sendToBerean \(message.id)"); throw MessageActionError.notImplemented
    }
    func saveToNotes(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] saveToNotes \(message.id)"); throw MessageActionError.notImplemented
    }
    func shareToPrayerWall(message: AppMessage, in context: MessageActionContext, visibility: PrayerWallVisibility) async throws {
        dlog("📋 [STUB] shareToPrayerWall \(message.id)"); throw MessageActionError.notImplemented
    }
    func setReminder(for message: AppMessage, in context: MessageActionContext, fireAt: Date) async throws {
        dlog("📋 [STUB] setReminder \(message.id) at \(fireAt)"); throw MessageActionError.notImplemented
    }
    func muteThread(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] muteThread \(message.id)"); throw MessageActionError.notImplemented
    }
    func unmuteThread(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] unmuteThread \(message.id)"); throw MessageActionError.notImplemented
    }
    func isThreadMuted(messageId: String, userId: String) async -> Bool { false }

    func edit(message: AppMessage, newText: String, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] edit \(message.id)"); throw MessageActionError.notImplemented
    }
    func deleteOwn(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] deleteOwn \(message.id)"); throw MessageActionError.notImplemented
    }
    func removeAsAdmin(message: AppMessage, reason: String, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] removeAsAdmin \(message.id)"); throw MessageActionError.notImplemented
    }
    func report(message: AppMessage, reason: ModerationReportReason, note: String?, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] report \(message.id)"); throw MessageActionError.notImplemented
    }
    func blockUser(userId: String, from context: MessageActionContext) async throws {
        dlog("📋 [STUB] blockUser \(userId)"); throw MessageActionError.notImplemented
    }
    func pinToChannel(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] pin \(message.id)"); throw MessageActionError.notImplemented
    }
    func unpin(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] unpin \(message.id)"); throw MessageActionError.notImplemented
    }
    func makeAnnouncement(message: AppMessage, in context: MessageActionContext) async throws {
        dlog("📋 [STUB] makeAnnouncement \(message.id)"); throw MessageActionError.notImplemented
    }
}
