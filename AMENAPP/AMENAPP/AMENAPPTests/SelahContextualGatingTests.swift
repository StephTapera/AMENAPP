#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - Selah Contextual gating contract
// Tests the deterministic evaluator's restraint contract directly (no UI tree, no flags):
// a suggestion must clear feature-enablement, permission, Sabbath, cooldown, and confidence
// gates before it may surface. Each test isolates one gate.

@MainActor
struct SelahContextualGatingTests {

    private let service = SelahContextualIntelligenceService.shared

    /// A date inside Lent (March) so the liturgical-layer candidate always exists.
    private func lentDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 15; c.hour = 10
        return Calendar.current.date(from: c)!
    }

    @Test("Disabled feature is suppressed as featureDisabled")
    func disabledFeatureSuppressed() {
        var settings = SelahContextualSettings()
        settings.enabledFeatures = []  // nothing enabled
        let input = SelahContextualInput(
            now: lentDate(),
            signalConfidenceByFeature: [.crossReferenceWeb: 0.95]
        )
        let result = service.evaluate(input: input, settings: settings)
        #expect(result.suppressedFeatures[.crossReferenceWeb] == .featureDisabled)
        #expect(result.surfacedSuggestions.isEmpty)
    }

    @Test("Missing permission suppresses a camera feature")
    func missingPermissionSuppressed() {
        var settings = SelahContextualSettings()
        settings.enabledFeatures = [.bulletinSlideCapture]
        settings.grantedPermissions = []  // no camera
        let input = SelahContextualInput(
            now: lentDate(),
            signalConfidenceByFeature: [.bulletinSlideCapture: 0.95]
        )
        let result = service.evaluate(input: input, settings: settings)
        #expect(result.suppressedFeatures[.bulletinSlideCapture] == .permissionMissing)
    }

    @Test("Low confidence keeps Selah silent")
    func lowConfidenceSuppressed() {
        var settings = SelahContextualSettings()
        settings.enabledFeatures = [.crossReferenceWeb]
        settings.interruptTolerance = 0.5
        let input = SelahContextualInput(
            now: lentDate(),
            signalConfidenceByFeature: [.crossReferenceWeb: 0.10]
        )
        let result = service.evaluate(input: input, settings: settings)
        #expect(result.suppressedFeatures[.crossReferenceWeb] == .confidenceTooLow)
    }

    @Test("Sabbath silences non-rest features")
    func sabbathSilencesNonRest() {
        let now = lentDate()
        var settings = SelahContextualSettings()
        settings.enabledFeatures = [.liturgicalLayer]
        settings.chosenSabbathWeekday = Calendar.current.component(.weekday, from: now)
        let input = SelahContextualInput(now: now)
        let result = service.evaluate(input: input, settings: settings)
        #expect(result.suppressedFeatures[.liturgicalLayer] == .sabbathSilence)
    }

    @Test("Cooldown blocks a re-surface within the window")
    func cooldownBlocksResurface() {
        let now = lentDate()
        var settings = SelahContextualSettings()
        settings.enabledFeatures = [.liturgicalLayer]
        settings.minimumMinutesBetweenSurfaces = 240
        settings.lastSurfaceAtByFeature = [.liturgicalLayer: now.addingTimeInterval(-60)]  // 1 min ago
        let input = SelahContextualInput(now: now)
        let result = service.evaluate(input: input, settings: settings)
        #expect(result.suppressedFeatures[.liturgicalLayer] == .cooldownActive)
    }

    @Test("A clean liturgical signal surfaces")
    func liturgicalSurfacesWhenClean() {
        let now = lentDate()
        var settings = SelahContextualSettings()
        settings.enabledFeatures = [.liturgicalLayer]
        settings.interruptTolerance = 0.5
        let input = SelahContextualInput(now: now)
        let result = service.evaluate(input: input, settings: settings)
        let surfaced = result.surfacedSuggestions.first { $0.feature == .liturgicalLayer }
        #expect(surfaced != nil)
        #expect(surfaced?.scriptureRefs.isEmpty == false)
    }
}
#endif
