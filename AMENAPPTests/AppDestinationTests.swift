// AppDestinationTests.swift
// AMENAPPTests
//
// Unit tests for AppDestination URL round-trips and auth requirements.
// Uses Swift Testing — no XCTest, no mocking, no UI.
//
// NOTE: Comprehensive URL parsing and auth gate tests also live in
// AMENAPPTests/Navigation/DeepLinkRouterTests.swift. This file covers the
// specific cases called out in the navigation-layer audit, in particular the
// Fix 4 `amen://post/new` → .newPost mapping that was added as part of the
// UI consolidation work on branch berean/ui-consolidation-v1.

import Testing
import Foundation
@testable import AMENAPP

// MARK: - AppDestination Canonical URL Round-trips (Audit Spec)

@Suite("AppDestination — Audit spec round-trips")
struct AppDestinationAuditRoundTripTests {

    // 1. Parameterless tab destinations

    @Test("amen://home → .home")
    func auditHome() {
        #expect(AppDestination(url: URL(string: "amen://home")!) == .home)
    }

    @Test("amen://discover → .discovery")
    func auditDiscovery() {
        #expect(AppDestination(url: URL(string: "amen://discover")!) == .discovery)
    }

    @Test("amen://messages → .messages")
    func auditMessages() {
        #expect(AppDestination(url: URL(string: "amen://messages")!) == .messages)
    }

    @Test("amen://category → .resources")
    func auditResources() {
        // "category" host maps to .resources in the switch statement
        #expect(AppDestination(url: URL(string: "amen://category")!) == .resources)
    }

    @Test("amen://notifications → .activity")
    func auditActivity() {
        #expect(AppDestination(url: URL(string: "amen://notifications")!) == .activity)
    }

    // 2. .post(id:) with a known ID

    @Test("amen://post/abc123 → .post(id: abc123)")
    func auditPostWithId() {
        #expect(AppDestination(url: URL(string: "amen://post/abc123")!) == .post(id: "abc123"))
    }

    // 3. .askBerean(question:) — with question

    @Test("amen://berean?q=sin → .askBerean(question: sin)")
    func auditBereanWithQuestion() {
        #expect(AppDestination(url: URL(string: "amen://berean?q=sin")!) == .askBerean(question: "sin"))
    }

    // 4. .askBerean(question:) — without question

    @Test("amen://berean → .askBerean(question: nil)")
    func auditBereanNoQuestion() {
        #expect(AppDestination(url: URL(string: "amen://berean")!) == .askBerean(question: nil))
    }

    // 5. Unknown URL → nil

    @Test("amen://totally-unknown → nil")
    func auditUnknownReturnsNil() {
        #expect(AppDestination(url: URL(string: "amen://totally-unknown")!) == nil)
    }

    // 6. Fix 4: amen://post/new → .newPost

    @Test("amen://post/new → .newPost (Fix 4)")
    func auditNewPostURL() {
        #expect(AppDestination(url: URL(string: "amen://post/new")!) == .newPost)
    }
}

// MARK: - AppDestination requiresAuth Spot-checks (Audit Spec)

@Suite("AppDestination — requiresAuth spot-checks")
struct AppDestinationRequiresAuthSpotTests {

    // 7. Auth-required destinations

    @Test("messages requiresAuth = true")
    func auditMessagesAuth() {
        #expect(AppDestination.messages.requiresAuth == true)
    }

    @Test("newPost requiresAuth = true")
    func auditNewPostAuth() {
        #expect(AppDestination.newPost.requiresAuth == true)
    }

    @Test("conversation requiresAuth = true")
    func auditConversationAuth() {
        #expect(AppDestination.conversation(conversationId: "x").requiresAuth == true)
    }

    // 8. Non-auth destinations

    @Test("home requiresAuth = false")
    func auditHomeAuth() {
        #expect(AppDestination.home.requiresAuth == false)
    }

    @Test("discovery requiresAuth = false")
    func auditDiscoveryAuth() {
        #expect(AppDestination.discovery.requiresAuth == false)
    }

    @Test("search(query: nil) requiresAuth = false")
    func auditSearchAuth() {
        #expect(AppDestination.search(query: nil).requiresAuth == false)
    }
}
