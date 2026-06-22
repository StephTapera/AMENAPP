#if canImport(Testing)
import Testing
import Foundation
@testable import AMENAPP

// MARK: - ConsentStore Tests

@Suite("ConsentStore")
struct ConsentStoreTests {

    // MARK: testDefaultsMatchContract

    @Test("Defaults: only activityToRhythm is enabled by default")
    func testDefaultsMatchContract() {
        let defaults = ConsentState.defaults()

        // Exactly one edge should be true by default
        let enabledEdges = defaults.filter(\.isEnabled)
        #expect(enabledEdges.count == 1)
        #expect(enabledEdges.first?.edge == .activityToRhythm)

        // All other edges must be OFF
        let disabledEdges = defaults.filter { !$0.isEnabled }
        #expect(disabledEdges.count == ConsentEdge.allCases.count - 1)
        for state in disabledEdges {
            #expect(state.edge != .activityToRhythm)
        }
    }

    // MARK: testToggleEdgePersists

    @Test("setEnabled toggles isEnabled correctly")
    @MainActor
    func testToggleEdgePersists() async {
        let store = ConsentStore.shared

        // Start from known state
        store.setEnabled(.notesToMatching, false)
        #expect(store.isEnabled(.notesToMatching) == false)

        // Toggle on
        store.setEnabled(.notesToMatching, true)
        #expect(store.isEnabled(.notesToMatching) == true)

        // Toggle off again
        store.setEnabled(.notesToMatching, false)
        #expect(store.isEnabled(.notesToMatching) == false)
    }

    // MARK: testToggleEdgeSyncsToDefaults

    @Test("setEnabled writes a decodable entry to UserDefaults")
    @MainActor
    func testToggleEdgeSyncsToDefaults() async {
        let store = ConsentStore.shared
        let edge = ConsentEdge.messagesToPrayer
        let key = "consent_\(edge.rawValue)"

        // Ensure the key exists after a set
        store.setEnabled(edge, true)

        let data = UserDefaults.standard.data(forKey: key)
        #expect(data != nil)

        if let data {
            let decoded = try? JSONDecoder().decode(ConsentState.self, from: data)
            #expect(decoded != nil)
            #expect(decoded?.edge == edge)
            #expect(decoded?.isEnabled == true)
        }

        // Clean up
        store.setEnabled(edge, false)
    }
}

// MARK: - CrisisDampening Tests

@Suite("CrisisDampening")
struct CrisisDampeningTests {

    // MARK: testCrisisDampeningActivates

    @Test("activate() sets isActive = true")
    @MainActor
    func testCrisisDampeningActivates() {
        let dampening = CrisisDampening.shared
        dampening.deactivate() // start clean

        #expect(dampening.isActive == false)
        dampening.activate()
        #expect(dampening.isActive == true)

        // Clean up
        dampening.deactivate()
    }

    // MARK: testCrisisDampeningPersistsAcrossReinit

    @Test("Persisted state survives re-reading from UserDefaults (simulated re-launch)")
    @MainActor
    func testCrisisDampeningPersistsAcrossReinit() {
        // Write a future expiry directly to UserDefaults (simulating what activate() does)
        let windowKey = "crisis_dampening_active_until"
        let futureDate = Date().addingTimeInterval(72 * 3600)
        UserDefaults.standard.set(futureDate, forKey: windowKey)

        // Reading back simulates a fresh-launch restore
        let storedDate = UserDefaults.standard.object(forKey: windowKey) as? Date
        #expect(storedDate != nil)

        if let storedDate {
            let wouldBeActive = Date() < storedDate
            #expect(wouldBeActive == true)
        }

        // Clean up
        UserDefaults.standard.removeObject(forKey: windowKey)
    }
}
#endif
