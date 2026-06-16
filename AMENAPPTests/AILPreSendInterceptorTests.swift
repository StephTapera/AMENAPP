// AILPreSendInterceptorTests.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// Contract tests for the C10/C11 pre-send interception decision logic.
// Verifies the four load-bearing safety properties:
//   1. zero interference when the flag is OFF (default),
//   2. crisis context routes to care and NEVER to cooldown,
//   3. at most one interception per message draft (dismiss-respected),
//   4. fail-open → proceed.
// The transform runner is injected so no network/Firebase is touched.

import Testing
import Foundation
@testable import AMENAPP

@MainActor
struct AILPreSendInterceptorTests {

    private func success(_ text: String, task: A11yTask) -> A11yTransformResult {
        A11yTransformResult(
            task: task, output: .text(text), provenance: .aiGenerated,
            sourceLang: nil, targetLang: nil, cultureNotes: nil,
            confidence: .medium, originalRef: "k", failOpen: false, crisisBypass: false
        )
    }

    @Test func zeroInterferenceWhenDisabled() async {
        let interceptor = AILPreSendInterceptor(isEnabled: false)
        var runnerCalled = false
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, _, _, _ in
            runnerCalled = true
            return self.success("should not be used", task: task)
        }
        let decision = await interceptor.evaluate(
            draft: "you are completely wrong",
            isCrisisContext: false, messageKey: "m1", using: runner
        )
        #expect(decision == .proceed)
        #expect(runnerCalled == false)   // disabled ⇒ transform never invoked
    }

    @Test func crisisRoutesToCareNeverCooldown() async {
        let interceptor = AILPreSendInterceptor(isEnabled: true)
        var taskSeen: A11yTask?
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, _, _, _ in
            taskSeen = task
            return self.success("Take a breath before you send this.", task: task)
        }
        let decision = await interceptor.evaluate(
            draft: "I can't do this anymore",
            isCrisisContext: true, messageKey: "m2", using: runner
        )
        #expect(decision == .care(suggestion: "Take a breath before you send this."))
        #expect(taskSeen == .replyCareCheck)            // crisis ⇒ care task
        if case .cooldown = decision {
            Issue.record("crisis context must NEVER route to cooldown")
        }
    }

    @Test func nonCrisisRoutesToCooldown() async {
        let interceptor = AILPreSendInterceptor(isEnabled: true)
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, _, _, _ in
            self.success("Here's a calmer way to say that.", task: task)
        }
        let decision = await interceptor.evaluate(
            draft: "this is so stupid",
            isCrisisContext: false, messageKey: "m3", using: runner
        )
        #expect(decision == .cooldown(rewrite: "Here's a calmer way to say that."))
    }

    @Test func interceptsOncePerMessageThenProceeds() async {
        let interceptor = AILPreSendInterceptor(isEnabled: true)
        var calls = 0
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, _, _, _ in
            calls += 1
            return self.success("a calmer version", task: task)
        }
        let first = await interceptor.evaluate(
            draft: "ugh whatever", isCrisisContext: false, messageKey: "m4", using: runner
        )
        let second = await interceptor.evaluate(
            draft: "ugh whatever", isCrisisContext: false, messageKey: "m4", using: runner
        )
        #expect(first == .cooldown(rewrite: "a calmer version"))
        #expect(second == .proceed)   // dismiss-respected: same draft never prompts twice
        #expect(calls == 1)           // the second call short-circuits before the transform
    }

    @Test func failOpenProceeds() async {
        let interceptor = AILPreSendInterceptor(isEnabled: true)
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, ref, _, _ in
            A11yTransformResult.failedOpen(task: task, originalRef: ref)
        }
        let decision = await interceptor.evaluate(
            draft: "anything at all",
            isCrisisContext: false, messageKey: "m5", using: runner
        )
        #expect(decision == .proceed)
    }

    @Test func forgetReenablesInterception() async {
        let interceptor = AILPreSendInterceptor(isEnabled: true)
        let runner: AILPreSendInterceptor.TransformRunner = { task, _, _, _, _ in
            self.success("calmer", task: task)
        }
        _ = await interceptor.evaluate(draft: "x", isCrisisContext: false, messageKey: "m6", using: runner)
        interceptor.forget(messageKey: "m6")
        let again = await interceptor.evaluate(draft: "x", isCrisisContext: false, messageKey: "m6", using: runner)
        #expect(again == .cooldown(rewrite: "calmer"))   // after forget, a fresh prompt is allowed
    }
}
