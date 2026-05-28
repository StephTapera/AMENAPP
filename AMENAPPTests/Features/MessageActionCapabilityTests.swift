import Testing
import Foundation
@testable import AMENAPP

// MARK: - MessageActionCapabilityTests

/// Verifies the capability matrix across surfaces × roles × ownership.
/// All tests are pure: no network, no Firebase, no async.
@Suite("MessageActionCapability")
struct MessageActionCapabilityTests {

    // MARK: - Helpers

    private func message(
        senderId: String = "alice",
        isPinned: Bool = false,
        tags: [String] = [],
        secondsAgo: TimeInterval = 30
    ) -> AppMessage {
        AppMessage(
            id: UUID().uuidString,
            text: "Hello AMEN",
            isFromCurrentUser: false,
            timestamp: Date().addingTimeInterval(-secondsAgo),
            senderId: senderId,
            isPinned: isPinned,
            tags: tags
        )
    }

    private func context(
        message: AppMessage,
        surface: MessageSurface,
        userId: String = "bob",
        role: MessageUserRole = .member,
        isSaved: Bool = false,
        hasPrayed: Bool = false,
        isMutedThread: Bool = false
    ) -> MessageActionContext {
        var ctx = MessageActionContext(
            message: message,
            surface: surface,
            currentUserId: userId,
            currentUserRole: role
        )
        ctx.isSaved = isSaved
        ctx.hasPrayed = hasPrayed
        ctx.isMutedThread = isMutedThread
        return ctx
    }

    // MARK: - Test 1: Member viewing others' message in a group

    @Test func memberOthersGroupBaseline() {
        let msg = message(senderId: "alice")
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .member)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.replyInThread))
        #expect(actions.contains(.copyText))
        #expect(actions.contains(.prayForThis))
        #expect(actions.contains(.report))
        #expect(actions.contains(.blockUser))
        // Members cannot pin, announce, or remove
        #expect(!actions.contains(.pinToChannel))
        #expect(!actions.contains(.makeAnnouncement))
        #expect(!actions.contains(.removeAsAdmin))
        // Cannot edit/delete others' messages
        #expect(!actions.contains(.edit))
        #expect(!actions.contains(.delete))
    }

    // MARK: - Test 2: Member viewing own message in a group (within edit window)

    @Test func memberOwnMessageWithinEditWindow() {
        let msg = message(senderId: "bob", secondsAgo: 60) // 1 min ago — within 15 min window
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .member)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.edit))
        #expect(actions.contains(.delete))
        // Own message: no report/block
        #expect(!actions.contains(.report))
        #expect(!actions.contains(.blockUser))
        // Members still can't pin own messages
        #expect(!actions.contains(.pinToChannel))
    }

    // MARK: - Test 3: Own message outside the 15-minute edit window

    @Test func memberOwnMessageEditWindowExpired() {
        let msg = message(senderId: "bob", secondsAgo: 1200) // 20 min ago — expired
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .member)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(!actions.contains(.edit))   // Window expired
        #expect(actions.contains(.delete))  // Delete always available on own message
    }

    // MARK: - Test 4: Leader viewing others' message in a group

    @Test func leaderOthersGroupHasPin() {
        let msg = message(senderId: "alice")
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .leader)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.pinToChannel))
        #expect(actions.contains(.removeAsAdmin))
        // Leaders cannot make announcements
        #expect(!actions.contains(.makeAnnouncement))
    }

    // MARK: - Test 5: Admin viewing others' message in a group

    @Test func adminOthersGroupHasAnnounce() {
        let msg = message(senderId: "alice")
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .admin)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.pinToChannel))
        #expect(actions.contains(.makeAnnouncement))
        #expect(actions.contains(.removeAsAdmin))
    }

    // MARK: - Test 6: Admin on own message — no removeAsAdmin on self

    @Test func adminOwnMessageNoSelfRemove() {
        let msg = message(senderId: "bob")
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .admin)
        let actions = MessageActionCapability.actions(for: ctx)

        // Admin can pin their own message
        #expect(actions.contains(.pinToChannel))
        // But cannot remove their own message as admin
        #expect(!actions.contains(.removeAsAdmin))
        // Can announce (admin ability on the surface, not message-ownership gated)
        #expect(actions.contains(.makeAnnouncement))
    }

    // MARK: - Test 7: AmenConnect DM — no group-only actions even for leader

    @Test func leaderAmenConnectNoGroupActions() {
        let msg = message(senderId: "alice")
        let ctx = context(message: msg, surface: .amenConnect(dmId: "dm1"), userId: "bob", role: .leader)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(!actions.contains(.pinToChannel))
        #expect(!actions.contains(.unpin))
        #expect(!actions.contains(.makeAnnouncement))
        #expect(!actions.contains(.removeAsAdmin))
        // Core actions still present
        #expect(actions.contains(.replyInThread))
        #expect(actions.contains(.prayForThis))
        #expect(actions.contains(.sendToBerean))
    }

    // MARK: - Test 8: Prayer-tagged message in group shows shareToPrayerWall

    @Test func prayerTaggedMessageShowsShareAction() {
        let msg = message(senderId: "alice", tags: ["prayerRequest"])
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .member)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.shareToPrayerWall))
    }

    // MARK: - Test 9: Non-prayer message does not show shareToPrayerWall

    @Test func nonPrayerMessageNoShareAction() {
        let msg = message(senderId: "alice", tags: [])
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .member)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(!actions.contains(.shareToPrayerWall))
    }

    // MARK: - Test 10: System message returns reduced action set

    @Test func systemMessageReducedActions() {
        let msg = message(senderId: "system", tags: ["system"])
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .admin)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.copyText))
        #expect(actions.contains(.report))
        // No AMEN-specific or moderation actions
        #expect(!actions.contains(.prayForThis))
        #expect(!actions.contains(.replyInThread))
        #expect(!actions.contains(.pinToChannel))
        #expect(!actions.contains(.makeAnnouncement))
    }

    // MARK: - Test 11: State-dependent save toggle

    @Test func savedStateSwitchesAction() {
        let msg = message(senderId: "alice")
        let savedCtx = context(message: msg, surface: .discussion(discussionId: "d1"), userId: "bob", isSaved: true)
        let unsavedCtx = context(message: msg, surface: .discussion(discussionId: "d1"), userId: "bob", isSaved: false)

        #expect(MessageActionCapability.actions(for: savedCtx).contains(.unsave))
        #expect(!MessageActionCapability.actions(for: savedCtx).contains(.save))
        #expect(MessageActionCapability.actions(for: unsavedCtx).contains(.save))
        #expect(!MessageActionCapability.actions(for: unsavedCtx).contains(.unsave))
    }

    // MARK: - Test 12: Muted thread switches muteThread / unmuteThread

    @Test func mutedStateTogglesMuteAction() {
        let msg = message(senderId: "alice")
        let mutedCtx = context(message: msg, surface: .group(groupId: "g1"), isMutedThread: true)
        let unmutedCtx = context(message: msg, surface: .group(groupId: "g1"), isMutedThread: false)

        #expect(MessageActionCapability.actions(for: mutedCtx).contains(.unmuteThread))
        #expect(!MessageActionCapability.actions(for: mutedCtx).contains(.muteThread))
        #expect(MessageActionCapability.actions(for: unmutedCtx).contains(.muteThread))
        #expect(!MessageActionCapability.actions(for: unmutedCtx).contains(.unmuteThread))
    }

    // MARK: - Test 13: Pinned message shows unpin instead of pin

    @Test func pinnedMessageShowsUnpin() {
        let msg = message(senderId: "alice", isPinned: true)
        let ctx = context(message: msg, surface: .group(groupId: "g1"), userId: "bob", role: .leader)
        let actions = MessageActionCapability.actions(for: ctx)

        #expect(actions.contains(.unpin))
        #expect(!actions.contains(.pinToChannel))
    }

    // MARK: - Test 14: MessageUserRole.from ChurchRole mapping

    @Test func churchRoleMappingIsCorrect() {
        #expect(MessageUserRole.from(.owner) == .owner)
        #expect(MessageUserRole.from(.admin) == .admin)
        #expect(MessageUserRole.from(.mediaManager) == .admin)
        #expect(MessageUserRole.from(.eventsManager) == .admin)
        #expect(MessageUserRole.from(.pastor) == .leader)
        #expect(MessageUserRole.from(.moderator) == .leader)
        #expect(MessageUserRole.from(nil) == .member)
    }
}
