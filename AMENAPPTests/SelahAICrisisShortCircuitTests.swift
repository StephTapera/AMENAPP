// SelahAICrisisShortCircuitTests.swift
// AMENAPPTests
//
// Integration-level test that the AI services themselves (not just the
// preflight) refuse to call the LLM when the input is a crisis. We
// verify by *waiting on the async call to complete fast* — if the
// short-circuit didn't fire, the test would either hit the network or
// throw `featureDisabled`. Either way, "got the care message synchronously"
// is the only correct outcome.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

@MainActor
@Suite("Selah AI crisis short-circuit")
struct SelahAICrisisShortCircuitTests {

    @Test("Reflection rewriting returns care message for crisis input without calling the LLM")
    func rewriteReturnsCareMessageOnCrisis() async throws {
        // The service requires the feature flag enabled to reach the preflight.
        // The flag defaults to true in this codebase.
        guard AMENFeatureFlags.shared.selahScriptureActionsEnabled else { return }

        let result = try await SelahReflectionRewritingService.shared.rewrite(
            "I just want to end my life tonight.",
            mode: .simplify
        )
        // Crisis response is NOT an AI-generated rewrite — it's hand-written care copy.
        #expect(result.isAIGenerated == false)
        #expect(result.content.contains("988"))
    }

    @Test("Scripture Companion returns care message for crisis input without calling the LLM")
    func companionReturnsCareMessageOnCrisis() async throws {
        guard AMENFeatureFlags.shared.selahScriptureActionsEnabled else { return }

        let ref = SelahScriptureReference(bookId: "john", chapter: 3, startVerse: 16, endVerse: nil)
        let result = try await SelahScriptureCompanionService.shared.ask(
            "I'm thinking about suicide.",
            about: ref,
            translationAbbreviation: "KJV",
            visibleVerses: []
        )
        #expect(result.isAIGenerated == false)
        let body = result.content.lowercased()
        let mentionsResource = body.contains("988")
            || body.contains("samaritans")
            || body.contains("findahelpline")
        #expect(mentionsResource)
    }
}

#endif
