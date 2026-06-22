// SelahAISafetyPreflightTests.swift
// AMENAPPTests
//
// Pin the crisis-input gate that wraps the user-typed AI services.
// We want false positives over false negatives here — these tests
// exist so the gate keeps catching the high-signal phrases even as
// the prompt surface evolves.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("SelahAISafetyPreflight")
struct SelahAISafetyPreflightTests {

    @Test("Empty input is allowed")
    func emptyAllowed() {
        #expect(SelahAISafetyPreflight.evaluate("") == .allow)
        #expect(SelahAISafetyPreflight.evaluate("   ") == .allow)
    }

    @Test("Ordinary reflection text is allowed")
    func benignAllowed() {
        let inputs = [
            "I'm grateful for God's grace today.",
            "Reflecting on Romans 5 about suffering.",
            "Help me write a journal entry about peace."
        ]
        for input in inputs {
            #expect(SelahAISafetyPreflight.evaluate(input) == .allow,
                    "\(input.prefix(40)) should be allowed")
        }
    }

    @Test("\"want to die\" is blocked")
    func wantToDieBlocked() {
        let decision = SelahAISafetyPreflight.evaluate("I just want to die.")
        if case .blockedCrisis = decision { /* good */ } else {
            Issue.record("Expected crisis block")
        }
    }

    @Test("\"kill myself\" is blocked")
    func killMyselfBlocked() {
        let decision = SelahAISafetyPreflight.evaluate("Sometimes I think about how to kill myself.")
        if case .blockedCrisis = decision { /* good */ } else {
            Issue.record("Expected crisis block")
        }
    }

    @Test("\"self-harm\" (hyphenated) is blocked")
    func selfHarmHyphenBlocked() {
        let decision = SelahAISafetyPreflight.evaluate("I'm struggling with self-harm.")
        if case .blockedCrisis = decision { /* good */ } else {
            Issue.record("Expected crisis block")
        }
    }

    @Test("\"self harm\" (spaced) is blocked")
    func selfHarmSpaceBlocked() {
        let decision = SelahAISafetyPreflight.evaluate("I'm struggling with self harm.")
        if case .blockedCrisis = decision { /* good */ } else {
            Issue.record("Expected crisis block")
        }
    }

    @Test("\"end my life\" is blocked")
    func endMyLifeBlocked() {
        let decision = SelahAISafetyPreflight.evaluate("I want to end my life tonight.")
        if case .blockedCrisis = decision { /* good */ } else {
            Issue.record("Expected crisis block")
        }
    }

    @Test("Care message contains real crisis line guidance")
    func careMessageMentionsResources() {
        let msg = SelahAISafetyPreflight.careMessage
        #expect(msg.contains("988"))
        #expect(msg.contains("Samaritans") || msg.contains("116 123"))
        #expect(!msg.isEmpty)
    }
}

#endif
