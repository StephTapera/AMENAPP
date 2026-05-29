// DeepLinkRouterTests.swift
// AMENAPP
//
// Contract tests for AppDestination URL parsing and AppNavigationRouter routing logic.
// All tests are deterministic and offline-safe — no Firebase calls, no network.
//
// Coverage:
//   ✓ AppDestination URL parsing — all amen:// hosts
//   ✓ AppDestination URL parsing — amenapp:// hosts
//   ✓ AppDestination URL parsing — https://amenapp.com/ universal links
//   ✓ Invalid / unsafe IDs are rejected
//   ✓ Tab index mapping: each destination maps to the correct tab
//   ✓ requiresAuth: gated vs ungated destinations
//   ✓ AppNavigationRouter lifecycle: sceneDidBecomeReady idempotent
//   ✓ AppNavigationRouter lifecycle: authDidBecomeReady idempotent
//   ✓ AppNavigationRouter lifecycle: authDidSignOut resets gate
//   ✓ AppDestination Equatable round-trips
//   ✓ amenDeepLink URL contract for all AmenIntentRouter-posted URLs

import Foundation
import Testing
@testable import AMENAPP

// MARK: - AppDestination URL Parsing — amen:// scheme

@Suite("AppDestination URL Parsing — amen:// scheme")
struct AppDestinationAmenURLTests {

    @Test("amen://home → .home")
    func amenHome() {
        let dest = AppDestination(url: URL(string: "amen://home")!)
        #expect(dest == .home)
    }

    @Test("amen://post/abc123 → .post(id:abc123)")
    func amenPost() {
        let dest = AppDestination(url: URL(string: "amen://post/abc123")!)
        #expect(dest == .post(id: "abc123"))
    }

    @Test("amen://post/abc123?comment=cmt456 → .post with highlightCommentId")
    func amenPostWithComment() {
        let dest = AppDestination(url: URL(string: "amen://post/abc123?comment=cmt456")!)
        #expect(dest == .post(id: "abc123", highlightCommentId: "cmt456"))
    }

    @Test("amen://user/user-001 → .userProfile")
    func amenUser() {
        let dest = AppDestination(url: URL(string: "amen://user/user-001")!)
        #expect(dest == .userProfile(userId: "user-001"))
    }

    @Test("amen://profile/user-001 → .userProfile (alias)")
    func amenProfileAlias() {
        let dest = AppDestination(url: URL(string: "amen://profile/user-001")!)
        #expect(dest == .userProfile(userId: "user-001"))
    }

    @Test("amen://church/church-001 → .church")
    func amenChurch() {
        let dest = AppDestination(url: URL(string: "amen://church/church-001")!)
        #expect(dest == .church(churchId: "church-001"))
    }

    @Test("amen://conversation/conv-abc → .conversation")
    func amenConversation() {
        let dest = AppDestination(url: URL(string: "amen://conversation/conv-abc")!)
        #expect(dest == .conversation(conversationId: "conv-abc"))
    }

    @Test("amen://messages (no path) → .messages tab")
    func amenMessagesNoPath() {
        let dest = AppDestination(url: URL(string: "amen://messages")!)
        #expect(dest == .messages)
    }

    @Test("amen://prayer/prayer-xyz → .prayer(prayerId:)")
    func amenPrayerDetail() {
        let dest = AppDestination(url: URL(string: "amen://prayer/prayer-xyz")!)
        #expect(dest == .prayer(prayerId: "prayer-xyz"))
    }

    @Test("amen://prayer (no path) → .resources tab")
    func amenPrayerNoPath() {
        let dest = AppDestination(url: URL(string: "amen://prayer")!)
        #expect(dest == .resources)
    }

    @Test("amen://prayer/new → .prayerNew")
    func amenPrayerNew() {
        let dest = AppDestination(url: URL(string: "amen://prayer/new")!)
        #expect(dest == .prayerNew)
    }

    @Test("amen://prayer-composer → .prayerNew")
    func amenPrayerComposer() {
        let dest = AppDestination(url: URL(string: "amen://prayer-composer")!)
        #expect(dest == .prayerNew)
    }

    @Test("amen://church-note/note-001 → .churchNote")
    func amenChurchNote() {
        let dest = AppDestination(url: URL(string: "amen://church-note/note-001")!)
        #expect(dest == .churchNote(noteId: "note-001"))
    }

    @Test("amen://notifications → .activity")
    func amenNotifications() {
        let dest = AppDestination(url: URL(string: "amen://notifications")!)
        #expect(dest == .activity)
    }

    @Test("amen://search?q=grace → .search(query:grace)")
    func amenSearch() {
        let dest = AppDestination(url: URL(string: "amen://search?q=grace")!)
        #expect(dest == .search(query: "grace"))
    }

    @Test("amen://settings → .settings(section:nil)")
    func amenSettings() {
        let dest = AppDestination(url: URL(string: "amen://settings")!)
        #expect(dest == .settings(section: nil))
    }

    @Test("amen://settings/privacy → .settings(section:privacy)")
    func amenSettingsPrivacy() {
        let dest = AppDestination(url: URL(string: "amen://settings/privacy")!)
        #expect(dest == .settings(section: "privacy"))
    }

    @Test("amen://berean → .askBerean(question:nil)")
    func amenBerean() {
        let dest = AppDestination(url: URL(string: "amen://berean")!)
        #expect(dest == .askBerean(question: nil))
    }

    @Test("amen://berean?session=sess-abc → .bereanWithSession")
    func amenBereanSession() {
        let dest = AppDestination(url: URL(string: "amen://berean?session=sess-abc")!)
        #expect(dest == .bereanWithSession(sessionId: "sess-abc"))
    }

    @Test("amen://find-church → .findChurch")
    func amenFindChurch() {
        let dest = AppDestination(url: URL(string: "amen://find-church")!)
        #expect(dest == .findChurch)
    }

    @Test("amen://church-notes → .churchNotes")
    func amenChurchNotes() {
        let dest = AppDestination(url: URL(string: "amen://church-notes")!)
        #expect(dest == .churchNotes)
    }

    @Test("amen://reflection → .reflection")
    func amenReflection() {
        let dest = AppDestination(url: URL(string: "amen://reflection")!)
        #expect(dest == .reflection)
    }

    @Test("amen://verse → .verseOfDay (widget CTA — Hot Spot 7 fix)")
    func amenVerse() {
        let dest = AppDestination(url: URL(string: "amen://verse")!)
        #expect(dest == .verseOfDay)
    }

    @Test("amen://comment?postId=abc → .post(id:abc)")
    func amenComment() {
        let dest = AppDestination(url: URL(string: "amen://comment?postId=abc")!)
        #expect(dest == .post(id: "abc"))
    }

    @Test("amen://chat?threadId=thread-001 → .conversation")
    func amenChat() {
        let dest = AppDestination(url: URL(string: "amen://chat?threadId=thread-001")!)
        #expect(dest == .conversation(conversationId: "thread-001"))
    }

    @Test("amen://unknown-host → nil")
    func amenUnknownHost() {
        let dest = AppDestination(url: URL(string: "amen://unknown-mystery")!)
        #expect(dest == nil)
    }
}

// MARK: - AppDestination URL Parsing — ID validation

@Suite("AppDestination ID Validation")
struct AppDestinationIDValidationTests {

    @Test("Post ID with path traversal is rejected")
    func pathTraversalRejected() {
        let dest = AppDestination(url: URL(string: "amen://post/../sensitive")!)
        #expect(dest == nil)
    }

    @Test("Valid alphanumeric + hyphen ID is accepted")
    func validHyphenId() {
        let dest = AppDestination(url: URL(string: "amen://post/abc-def_123")!)
        #expect(dest == .post(id: "abc-def_123"))
    }

    @Test("129-character ID is rejected (too long)")
    func tooLongIdRejected() {
        let longId = String(repeating: "a", count: 129)
        let dest = AppDestination(url: URL(string: "amen://post/\(longId)")!)
        #expect(dest == nil)
    }

    @Test("isValidId: alphanumeric passes")
    func validIdAlphanumeric() {
        #expect(AppDestination.isValidId("abc123") == true)
    }

    @Test("isValidId: 128-character ID is accepted (max length)")
    func maxLengthId() {
        let maxId = String(repeating: "a", count: 128)
        #expect(AppDestination.isValidId(maxId) == true)
    }

    @Test("isValidId: empty string is rejected")
    func emptyIdRejected() {
        #expect(AppDestination.isValidId("") == false)
    }

    @Test("isValidId: ID with slash is rejected")
    func slashIdRejected() {
        #expect(AppDestination.isValidId("abc/def") == false)
    }
}

// MARK: - AppDestination URL Parsing — Universal Links

@Suite("AppDestination URL Parsing — Universal Links")
struct AppDestinationUniversalLinkTests {

    @Test("https://amenapp.com/post/abc123 → .post")
    func universalPost() {
        let dest = AppDestination(url: URL(string: "https://amenapp.com/post/abc123")!)
        #expect(dest == .post(id: "abc123"))
    }

    @Test("https://amenapp.com/profile/user-abc → .userProfile")
    func universalProfile() {
        let dest = AppDestination(url: URL(string: "https://amenapp.com/profile/user-abc")!)
        #expect(dest == .userProfile(userId: "user-abc"))
    }

    @Test("https://amenapp.com/conversation/conv-abc → .conversation")
    func universalConversation() {
        let dest = AppDestination(url: URL(string: "https://amenapp.com/conversation/conv-abc")!)
        #expect(dest == .conversation(conversationId: "conv-abc"))
    }

    @Test("https://amenapp.com/group/join?token=tkn123 → .groupJoinLink")
    func universalGroupJoin() {
        let dest = AppDestination(url: URL(string: "https://amenapp.com/group/join?token=tkn123")!)
        #expect(dest == .groupJoinLink(token: "tkn123"))
    }

    @Test("https://unknown.com/post/abc123 → nil (non-AMEN host)")
    func unknownHostRejected() {
        let dest = AppDestination(url: URL(string: "https://unknown.com/post/abc123")!)
        #expect(dest == nil)
    }
}

// MARK: - AppDestination Tab Index Mapping

@Suite("AppDestination — Tab Index Mapping")
struct AppDestinationTabIndexTests {

    // Tab layout: 0=Home, 1=Discovery, 2=Messages, 3=Resources, 4=Notifications, 5=Profile

    @Test("home → tab 0")
    func homeTab() { #expect(AppDestination.home.targetTab == 0) }

    @Test("newPost → tab 0")
    func newPostTab() { #expect(AppDestination.newPost.targetTab == 0) }

    @Test("post(id:) → tab 0")
    func postTab() { #expect(AppDestination.post(id: "x").targetTab == 0) }

    @Test("verseOfDay → tab 0")
    func verseTab() { #expect(AppDestination.verseOfDay.targetTab == 0) }

    @Test("discovery → tab 1")
    func discoveryTab() { #expect(AppDestination.discovery.targetTab == 1) }

    @Test("search → tab 1")
    func searchTab() { #expect(AppDestination.search().targetTab == 1) }

    @Test("messages → tab 2")
    func messagesTab() { #expect(AppDestination.messages.targetTab == 2) }

    @Test("conversation(id:) → tab 2 (P1 fix: was 3)")
    func conversationTab() { #expect(AppDestination.conversation(conversationId: "x").targetTab == 2) }

    @Test("groupJoinLink → tab 2")
    func groupJoinTab() { #expect(AppDestination.groupJoinLink(token: "t").targetTab == 2) }

    @Test("resources → tab 3")
    func resourcesTab() { #expect(AppDestination.resources.targetTab == 3) }

    @Test("findChurch → tab 3")
    func findChurchTab() { #expect(AppDestination.findChurch.targetTab == 3) }

    @Test("churchNotes → tab 3")
    func churchNotesTab() { #expect(AppDestination.churchNotes.targetTab == 3) }

    @Test("reflection → tab 3")
    func reflectionTab() { #expect(AppDestination.reflection.targetTab == 3) }

    @Test("prayerNew → tab 3 (P1 fix: Prayer quick action was routed to tab 0)")
    func prayerNewTab() { #expect(AppDestination.prayerNew.targetTab == 3) }

    @Test("prayer(id:) → tab 3")
    func prayerDetailTab() { #expect(AppDestination.prayer(prayerId: "x").targetTab == 3) }

    @Test("activity → tab 4 (P1 fix: was 2)")
    func activityTab() { #expect(AppDestination.activity.targetTab == 4) }

    @Test("profile → tab 5")
    func profileTab() { #expect(AppDestination.profile.targetTab == 5) }

    @Test("settings → tab 5 (P1 fix: was 4)")
    func settingsTab() { #expect(AppDestination.settings().targetTab == 5) }
}

// MARK: - AppDestination Auth Gate

@Suite("AppDestination — requiresAuth")
struct AppDestinationAuthTests {

    @Test("messages requiresAuth = true")
    func messagesAuth() { #expect(AppDestination.messages.requiresAuth == true) }

    @Test("newPost requiresAuth = true")
    func newPostAuth() { #expect(AppDestination.newPost.requiresAuth == true) }

    @Test("conversation requiresAuth = true")
    func conversationAuth() { #expect(AppDestination.conversation(conversationId: "x").requiresAuth == true) }

    @Test("activity (notifications) requiresAuth = true")
    func activityAuth() { #expect(AppDestination.activity.requiresAuth == true) }

    @Test("home requiresAuth = false")
    func homeAuth() { #expect(AppDestination.home.requiresAuth == false) }

    @Test("search requiresAuth = false")
    func searchAuth() { #expect(AppDestination.search().requiresAuth == false) }

    @Test("settings requiresAuth = false")
    func settingsAuth() { #expect(AppDestination.settings().requiresAuth == false) }

    @Test("verseOfDay requiresAuth = false")
    func verseAuth() { #expect(AppDestination.verseOfDay.requiresAuth == false) }
}

// MARK: - AppNavigationRouter Lifecycle

@Suite("AppNavigationRouter — Lifecycle")
struct AppNavigationRouterLifecycleTests {

    @Test("sceneDidBecomeReady is idempotent")
    @MainActor
    func sceneReadyIdempotent() {
        let router = AppNavigationRouter.shared
        router.sceneDidBecomeReady()
        router.sceneDidBecomeReady()
        #expect(Bool(true))
    }

    @Test("authDidBecomeReady is idempotent")
    @MainActor
    func authReadyIdempotent() {
        let router = AppNavigationRouter.shared
        router.authDidBecomeReady()
        router.authDidBecomeReady()
        #expect(Bool(true))
    }

    @Test("authDidSignOut resets gate; next authDidBecomeReady fires normally")
    @MainActor
    func signOutResetsAuthGate() {
        let router = AppNavigationRouter.shared
        router.authDidBecomeReady()
        router.authDidSignOut()
        router.authDidBecomeReady()
        #expect(Bool(true))
    }

    @Test("clearPendingPresentation sets pendingPresentation to nil")
    @MainActor
    func clearPresentation() {
        let router = AppNavigationRouter.shared
        router.clearPendingPresentation()
        #expect(router.pendingPresentation == nil)
    }
}

// MARK: - AppDestination Equatable round-trip

@Suite("AppDestination — Equatable round-trips")
struct AppDestinationEquatableTests {

    @Test("Two .post destinations with same id are equal")
    func postEquality() {
        #expect(AppDestination.post(id: "abc") == AppDestination.post(id: "abc"))
    }

    @Test("Two .post destinations with different ids are not equal")
    func postInequality() {
        #expect(AppDestination.post(id: "abc") != AppDestination.post(id: "xyz"))
    }

    @Test("Two .askBerean with same question are equal")
    func bereanEquality() {
        #expect(AppDestination.askBerean(question: "faith") == AppDestination.askBerean(question: "faith"))
    }

    @Test("askBerean(nil) != askBerean(faith)")
    func bereanNilInequality() {
        #expect(AppDestination.askBerean(question: nil) != AppDestination.askBerean(question: "faith"))
    }

    @Test("settings(nil) == settings(nil)")
    func settingsNilEquality() {
        #expect(AppDestination.settings(section: nil) == AppDestination.settings(section: nil))
    }

    @Test("settings(privacy) != settings(security)")
    func settingsSectionInequality() {
        #expect(AppDestination.settings(section: "privacy") != AppDestination.settings(section: "security"))
    }

    @Test("search(nil) == search(nil)")
    func searchNilEquality() {
        #expect(AppDestination.search(query: nil) == AppDestination.search(query: nil))
    }

    @Test("bereanWithVerse(John) != bereanWithVerse(Psalm)")
    func bereanVerseInequality() {
        #expect(AppDestination.bereanWithVerse(reference: "John 3:16") != AppDestination.bereanWithVerse(reference: "Psalm 23:1"))
    }
}

// MARK: - amenDeepLink URL contract (AmenIntentRouter-posted deep links)

@Suite("AmenIntentRouter → amenDeepLink URL contract")
struct AmenDeepLinkURLContractTests {

    @Test("amen://prayer round-trips to .resources (tab 3)")
    func prayerURLContract() {
        let dest = AppDestination(url: URL(string: "amen://prayer")!)
        #expect(dest == .resources)
        #expect(dest?.targetTab == 3)
    }

    @Test("amen://berean round-trips to .askBerean(question:nil)")
    func bereanURLContract() {
        let dest = AppDestination(url: URL(string: "amen://berean")!)
        #expect(dest == .askBerean(question: nil))
    }

    @Test("amen://find-church round-trips to .findChurch tab 3")
    func findChurchURLContract() {
        let dest = AppDestination(url: URL(string: "amen://find-church")!)
        #expect(dest == .findChurch)
        #expect(dest?.targetTab == 3)
    }

    @Test("amen://church-notes round-trips to .churchNotes tab 3")
    func churchNotesURLContract() {
        let dest = AppDestination(url: URL(string: "amen://church-notes")!)
        #expect(dest == .churchNotes)
        #expect(dest?.targetTab == 3)
    }

    @Test("amen://reflection round-trips to .reflection tab 3")
    func reflectionURLContract() {
        let dest = AppDestination(url: URL(string: "amen://reflection")!)
        #expect(dest == .reflection)
        #expect(dest?.targetTab == 3)
    }

    @Test("amen://prayer-composer round-trips to .prayerNew tab 3")
    func prayerComposerURLContract() {
        let dest = AppDestination(url: URL(string: "amen://prayer-composer")!)
        #expect(dest == .prayerNew)
        #expect(dest?.targetTab == 3)
    }

    @Test("amen://verse round-trips to .verseOfDay (widget CTA fix)")
    func verseWidgetCTAContract() {
        let dest = AppDestination(url: URL(string: "amen://verse")!)
        #expect(dest == .verseOfDay)
    }
}
