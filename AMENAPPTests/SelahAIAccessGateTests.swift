// SelahAIAccessGateTests.swift
// AMENAPPTests
//
// Tests the user-facing opt-out persistence and the State semantics of
// the AI access gate. The age + remote-flag inputs are read from app
// singletons and exercised by other suites; here we focus on the parts
// that are deterministic across test runs.

import Foundation

#if canImport(Testing)
import Testing
@testable import AMENAPP

private func freshDefaults() -> UserDefaults {
    let suiteName = "SelahAIAccessGateTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
@Suite("SelahAIAccessGate")
struct SelahAIAccessGateTests {

    @Test("Opt-out defaults to false on a fresh store")
    func defaultsToOptedIn() {
        let gate = SelahAIAccessGate(defaults: freshDefaults())
        #expect(gate.userHasOptedOut == false)
    }

    @Test("setUserOptOut(true) persists and is reflected in state")
    func optingOutPersists() {
        let defaults = freshDefaults()
        let a = SelahAIAccessGate(defaults: defaults)
        a.setUserOptOut(true)
        #expect(a.userHasOptedOut == true)

        let b = SelahAIAccessGate(defaults: defaults)
        #expect(b.userHasOptedOut == true)
    }

    @Test("setUserOptOut(false) restores access (when no other block applies)")
    func optingBackIn() {
        let gate = SelahAIAccessGate(defaults: freshDefaults())
        gate.setUserOptOut(true)
        gate.setUserOptOut(false)
        #expect(gate.userHasOptedOut == false)
    }

    @Test("State.available has nil human explanation")
    func availableStateHasNoExplanation() {
        let state = SelahAIAccessGate.State.available
        #expect(state.humanExplanation == nil)
        #expect(state.isAvailable == true)
    }

    @Test("State.disabled cases each have a non-empty human explanation")
    func disabledStatesHaveExplanations() {
        let cases: [SelahAIAccessGate.State] = [
            .disabled(.featureDisabledRemotely),
            .disabled(.minorUserAgeRestricted),
            .disabled(.userOptedOut)
        ]
        for state in cases {
            let explanation = state.humanExplanation ?? ""
            #expect(!explanation.isEmpty)
            #expect(state.isAvailable == false)
        }
    }

    @Test("Blocks are pairwise distinct (no two cases collide)")
    func blockCasesDistinct() {
        let blocks: [SelahAIAccessGate.Block] = [
            .featureDisabledRemotely, .minorUserAgeRestricted, .userOptedOut
        ]
        let unique = Set(blocks.map { String(describing: $0) })
        #expect(unique.count == blocks.count)
    }
}

#endif
