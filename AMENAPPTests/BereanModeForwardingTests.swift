import Testing
@testable import AMENAPP

// MARK: - BereanModeAuthorityResult tests

@Suite("BereanModeAuthorityResult — downgrade semantics")
struct BereanModeAuthorityResultTests {

    @Test("wasDowngraded is false when fallbackMode is nil")
    func notDowngradedWhenFallbackModeAbsent() {
        let result = BereanModeAuthorityResult(
            acceptedMode: "core",
            fallbackMode: nil,
            entitlementRequired: nil,
            quotaExceeded: nil,
            deepCreditsRemaining: nil,
            fallbackReason: nil
        )
        #expect(!result.wasDowngraded)
    }

    @Test("wasDowngraded is true when fallbackMode is set")
    func downgradeDetectedFromFallbackMode() {
        let result = BereanModeAuthorityResult(
            acceptedMode: "core",
            fallbackMode: "deep",
            entitlementRequired: true,
            quotaExceeded: nil,
            deepCreditsRemaining: nil,
            fallbackReason: nil
        )
        #expect(result.wasDowngraded)
    }

    @Test("acceptedMode is accessible and not nil when backend provides it")
    func acceptedModePassthrough() {
        let result = BereanModeAuthorityResult(
            acceptedMode: "deep",
            fallbackMode: nil,
            entitlementRequired: nil,
            quotaExceeded: nil,
            deepCreditsRemaining: 8,
            fallbackReason: nil
        )
        #expect(result.acceptedMode == "deep")
        #expect(result.deepCreditsRemaining == 8)
    }

    @Test("All fields nil is a valid no-op result — backend chose not to return metadata")
    func allNilIsValidNoOp() {
        let result = BereanModeAuthorityResult(
            acceptedMode: nil,
            fallbackMode: nil,
            entitlementRequired: nil,
            quotaExceeded: nil,
            deepCreditsRemaining: nil,
            fallbackReason: nil
        )
        #expect(!result.wasDowngraded)
        #expect(result.acceptedMode == nil)
    }

    @Test("quotaExceeded and deepCreditsRemaining are independent of wasDowngraded")
    func quotaFieldsAreIndependent() {
        let result = BereanModeAuthorityResult(
            acceptedMode: "core",
            fallbackMode: nil,
            entitlementRequired: nil,
            quotaExceeded: true,
            deepCreditsRemaining: 0,
            fallbackReason: nil
        )
        // quotaExceeded can be true even when mode wasn't downgraded this turn
        #expect(!result.wasDowngraded)
        #expect(result.quotaExceeded == true)
        #expect(result.deepCreditsRemaining == 0)
    }
}

// MARK: - BereanModelStore update-usage tests

@Suite("BereanModelStore — updateUsageState")
@MainActor
struct BereanModelStoreUsageStateTests {

    @Test("updateUsageState sets deepCreditsRemaining when provided")
    func creditsAreUpdatedWhenProvided() async {
        let store = BereanModelStore.shared
        store.updateUsageState(deepCreditsRemaining: 42, quotaExceeded: false)
        #expect(store.deepCreditsRemaining == 42)
        #expect(store.quotaExceeded == false)
    }

    @Test("updateUsageState skips fields that are nil — no partial override")
    func nilFieldsAreIgnored() async {
        let store = BereanModelStore.shared
        // Seed known values
        store.updateUsageState(deepCreditsRemaining: 10, quotaExceeded: false)
        // Update only quotaExceeded; credits should be unchanged
        store.updateUsageState(deepCreditsRemaining: nil, quotaExceeded: true)
        #expect(store.deepCreditsRemaining == 10)
        #expect(store.quotaExceeded == true)
    }

    @Test("fallbackToCore resets selectedMode to .core")
    func fallbackToCoreResetsMode() async {
        let store = BereanModelStore.shared
        store.selectedMode = .deep
        store.fallbackToCore()
        #expect(store.selectedMode == .core)
    }
}

// MARK: - BereanModelMode tier gating tests

@Suite("BereanModelMode — tier access gating")
struct BereanModelModeTierTests {

    @Test("Core is accessible to free users")
    func coreIsNotPro() {
        #expect(!BereanModelMode.core.requiresPro)
    }

    @Test("Deep requires Pro")
    func deepRequiresPro() {
        #expect(BereanModelMode.deep.requiresPro)
    }

    @Test("Adaptive requires Pro")
    func adaptiveRequiresPro() {
        #expect(BereanModelMode.adaptive.requiresPro)
    }

    @Test("backendValue matches raw value — forwarded correctly in request body")
    func backendValueMatchesRawValue() {
        #expect(BereanModelMode.core.backendValue == "core")
        #expect(BereanModelMode.deep.backendValue == "deep")
        #expect(BereanModelMode.adaptive.backendValue == "adaptive")
    }

    @Test("Free tier locks Deep via BereanUserTier.access")
    func freeTierLocksDeep() {
        #expect(BereanUserTier.free.access(for: .deep) == .locked)
    }

    @Test("Free tier permits Core via BereanUserTier.access")
    func freeTierPermitsCore() {
        #expect(BereanUserTier.free.access(for: .core) == .full)
    }

    @Test("Pro/Founder tier allows full Deep access")
    func proTierGrantsDeep() {
        #expect(BereanUserTier.pro.access(for: .deep) == .full)
        #expect(BereanUserTier.founder.access(for: .deep) == .full)
    }
}

// MARK: - BereanModesSheet ID safety tests

@Suite("BereanModesSheet — style ID safety")
struct BereanModesSheetIDTests {

    @Test("No style option uses id 'deep' — prevents collision with BereanModelMode.deep")
    func noStyleOptionUsesDeepID() {
        let hasDeepID = BereanModeOption.catalog.contains { $0.id == "deep" }
        #expect(!hasDeepID)
    }

    @Test("Analytical option exists with correct id")
    func analyticalOptionExists() {
        let analytical = BereanModeOption.catalog.first { $0.id == "analytical" }
        #expect(analytical != nil)
        #expect(analytical?.name == "Analytical")
    }

    @Test("All catalog IDs are unique — no duplicate routing risk")
    func catalogIDsAreUnique() {
        let ids = BereanModeOption.catalog.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test("BereanModelMode raw values never match any style option ID")
    func modelModeRawValuesDoNotCollideWithStyleIDs() {
        let modelModeRawValues = Set(BereanModelMode.allCases.map(\.rawValue))
        let styleIDs = Set(BereanModeOption.catalog.map(\.id))
        let intersection = modelModeRawValues.intersection(styleIDs)
        #expect(intersection.isEmpty,
                "Collision found: \(intersection). Style IDs must not reuse BereanModelMode raw values.")
    }
}
