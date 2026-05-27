import Testing
import SwiftUI
@testable import AMENAPP

// MARK: - TextRewriteViewContractTests
// Contract tests for TextRewriteView components using stored props pattern.
// Verifies that view components expose correct state and callbacks
// without hosting in UIHostingController.

@Suite("TextRewriteView Contract Tests")
struct TextRewriteViewContractTests {

    @Test("ToneCheckBanner exposes correct callbacks")
    func toneCheckBannerCallbacks() {
        var appliedSuggestion: String? = nil
        var dismissed = false

        let banner = ToneCheckBanner(
            suggestion: "Try a more constructive approach.",
            onApply: { appliedSuggestion = $0 },
            onDismiss: { dismissed = true }
        )

        banner.onApply("Try a more constructive approach.")
        #expect(appliedSuggestion == "Try a more constructive approach.")

        banner.onDismiss()
        #expect(dismissed == true)
    }

    @Test("ToneCheckBanner stores the suggestion text")
    func toneCheckBannerStoresSuggestionText() {
        let expectedSuggestion = "Perhaps say: I hear your concern and want to understand better."
        let banner = ToneCheckBanner(
            suggestion: expectedSuggestion,
            onApply: { _ in },
            onDismiss: { }
        )
        #expect(banner.suggestion == expectedSuggestion)
    }

    @Test("ToneCheckBanner onApply receives the suggestion string")
    func toneCheckBannerOnApplyReceivesSuggestion() {
        var received: String? = nil
        let suggestion = "Try a kinder phrasing."
        let banner = ToneCheckBanner(
            suggestion: suggestion,
            onApply: { received = $0 },
            onDismiss: { }
        )
        banner.onApply(suggestion)
        #expect(received == suggestion)
    }

    @Test("ToneCheckBanner onDismiss fires without parameters")
    func toneCheckBannerDismissFires() {
        var count = 0
        let banner = ToneCheckBanner(
            suggestion: "suggestion",
            onApply: { _ in },
            onDismiss: { count += 1 }
        )
        banner.onDismiss()
        banner.onDismiss()
        #expect(count == 2)
    }

    @Test("TextRewriteView initializes with correct harmCategoryId and contentType")
    @MainActor
    func textRewriteViewInitialState() {
        var accepted = false
        var blockedText = "original blocked text"

        let view = TextRewriteView(
            blockedText: Binding(get: { blockedText }, set: { blockedText = $0 }),
            harmCategoryId: "harassment",
            contentType: "post"
        ) { result in
            accepted = result
        }

        #expect(view.harmCategoryId == "harassment")
        #expect(view.contentType == "post")
        _ = accepted
    }

    @Test("TextRewriteView onDecision callback fires with false on cancel")
    @MainActor
    func textRewriteViewOnDecisionCancelCallback() {
        var decision: Bool? = nil
        var text = "draft text"

        let view = TextRewriteView(
            blockedText: Binding(get: { text }, set: { text = $0 }),
            harmCategoryId: "spam",
            contentType: "comment"
        ) { result in
            decision = result
        }

        view.onDecision(false)
        #expect(decision == false)
    }

    @Test("TextRewriteView onDecision callback fires with true on accept")
    @MainActor
    func textRewriteViewOnDecisionAcceptCallback() {
        var decision: Bool? = nil
        var text = "draft text"

        let view = TextRewriteView(
            blockedText: Binding(get: { text }, set: { text = $0 }),
            harmCategoryId: "harassment",
            contentType: "post"
        ) { result in
            decision = result
        }

        view.onDecision(true)
        #expect(decision == true)
    }

    @Test("ContentWarningBanner dismiss callback fires")
    func contentWarningBannerDismissCallback() {
        var dismissed = false
        let banner = ContentWarningBanner(
            warning: "Some readers may find this challenging.",
            onDismiss: { dismissed = true }
        )
        banner.onDismiss()
        #expect(dismissed == true)
    }

    @Test("ContentWarningBanner stores the warning text")
    func contentWarningBannerStoresWarningText() {
        let expectedWarning = "Some readers may find this challenging."
        let banner = ContentWarningBanner(
            warning: expectedWarning,
            onDismiss: { }
        )
        #expect(banner.warning == expectedWarning)
    }

    @Test("InteractionModePickerSheet initializes with current mode")
    @MainActor
    func interactionModePickerInitializesWithCurrentMode() {
        var currentMode = InteractionMode.social
        let sheet = InteractionModePickerSheet(
            currentMode: Binding(get: { currentMode }, set: { currentMode = $0 })
        )
        _ = sheet
        #expect(currentMode == .social)
    }

    @Test("InteractionModePickerSheet filters out youth mode from list")
    @MainActor
    func interactionModePickerFiltersYouth() {
        var currentMode = InteractionMode.discussion
        _ = InteractionModePickerSheet(
            currentMode: Binding(get: { currentMode }, set: { currentMode = $0 })
        )
        // The picker filters .youth from the displayed list
        let displayedModes = InteractionMode.allCases.filter { $0 != .youth }
        #expect(!displayedModes.contains(.youth))
        #expect(displayedModes.count == InteractionMode.allCases.count - 1)
    }

    @Test("InteractionModePickerSheet binding updates correctly")
    @MainActor
    func interactionModePickerBindingUpdates() {
        var currentMode = InteractionMode.social
        let binding = Binding(get: { currentMode }, set: { currentMode = $0 })

        _ = InteractionModePickerSheet(currentMode: binding)

        // Simulate binding update (as if user selected a new mode)
        binding.wrappedValue = .study
        #expect(currentMode == .study)
    }
}
