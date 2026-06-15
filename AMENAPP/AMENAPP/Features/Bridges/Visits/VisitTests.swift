import Testing
import Foundation
@testable import AMENAPP

// MARK: - VisitVerificationService Tests

@Suite("VisitVerificationService")
struct VisitVerificationServiceTests {

    // MARK: testServiceWindowDetection

    @Test("Saturday 10am is within service window; Tuesday 10am is not")
    func testServiceWindowDetection() {
        let service = VisitVerificationService.shared

        // Build a Saturday at 10:00
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 20   // 2026-06-20 is a Saturday (weekday == 7)
        comps.hour = 10
        comps.minute = 30
        let saturday10am = Calendar.current.date(from: comps)!

        // Build a Tuesday at 10:00
        var tuesdayComps = DateComponents()
        tuesdayComps.year = 2026
        tuesdayComps.month = 6
        tuesdayComps.day = 16   // 2026-06-16 is a Tuesday (weekday == 3)
        tuesdayComps.hour = 10
        tuesdayComps.minute = 30
        let tuesday10am = Calendar.current.date(from: tuesdayComps)!

        #expect(service.isWithinServiceWindow(for: saturday10am) == true)
        #expect(service.isWithinServiceWindow(for: tuesday10am) == false)
    }

    // MARK: testServiceWindowSunday

    @Test("Sunday 9am is within service window")
    func testServiceWindowSunday() {
        let service = VisitVerificationService.shared

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 21   // 2026-06-21 is a Sunday (weekday == 1)
        comps.hour = 9
        comps.minute = 0
        let sunday9am = Calendar.current.date(from: comps)!

        #expect(service.isWithinServiceWindow(for: sunday9am) == true)
    }

    // MARK: testServiceWindowOutsideHours

    @Test("Saturday 2pm is outside all service windows")
    func testServiceWindowOutsideHours() {
        let service = VisitVerificationService.shared

        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 20   // Saturday
        comps.hour = 14
        comps.minute = 0
        let saturday2pm = Calendar.current.date(from: comps)!

        #expect(service.isWithinServiceWindow(for: saturday2pm) == false)
    }

    // MARK: testConsentOffSkipsRegistration

    @MainActor
    @Test("registerChurch no-ops when locationToVisits consent is OFF")
    func testConsentOffSkipsRegistration() async {
        // Ensure consent is explicitly OFF
        ConsentStore.shared.setEnabled(.locationToVisits, false)

        let service = VisitVerificationService.shared
        let preCount = service.registeredChurchCount

        service.registerChurch(id: "test-church-consent", lat: 37.7749, lng: -122.4194)

        // No new region should have been registered
        #expect(service.registeredChurchCount == preCount)

        // Restore to avoid polluting other tests
        ConsentStore.shared.setEnabled(.locationToVisits, false)
    }
}

// MARK: - ConstellationModel Tests

@Suite("ConstellationModel")
struct ConstellationModelTests {

    // MARK: testConstellationDefaultsToExploring

    @Test("Unknown churchID defaults to .exploring relationship")
    func testConstellationDefaultsToExploring() async {
        // A brand-new churchID with no Firestore record (no auth uid) defaults to .exploring
        let rel = await ConstellationService.shared.relationship(for: "unknown-church-\(UUID().uuidString)")
        #expect(rel == .exploring)
    }

    // MARK: testConstellationWeights

    @Test("Signal weights: primary == 1.0, former == 0.1")
    func testConstellationWeights() {
        #expect(ConstellationRelationship.primary.signalWeight == 1.0)
        #expect(ConstellationRelationship.visiting.signalWeight == 0.6)
        #expect(ConstellationRelationship.family.signalWeight == 0.4)
        #expect(ConstellationRelationship.exploring.signalWeight == 0.3)
        #expect(ConstellationRelationship.former.signalWeight == 0.1)
    }

    // MARK: testConstellationWeightsOrdered

    @Test("Signal weights are strictly decreasing from primary to former")
    func testConstellationWeightsOrdered() {
        let ordered = ConstellationRelationship.allCases.map(\.signalWeight)
        for i in 0..<(ordered.count - 1) {
            #expect(ordered[i] > ordered[i + 1])
        }
    }

    // MARK: testMigrationAssignsExploring

    @Test("migrateExistingSaves assigns .exploring to all provided church IDs")
    func testMigrationAssignsExploring() async {
        let c1 = "migrate-church-\(UUID().uuidString)"
        let c2 = "migrate-church-\(UUID().uuidString)"

        // Neither church has been seen before — migration should ensure .exploring
        await ConstellationService.shared.migrateExistingSaves(churchIDs: [c1, c2])

        let r1 = await ConstellationService.shared.relationship(for: c1)
        let r2 = await ConstellationService.shared.relationship(for: c2)

        #expect(r1 == .exploring)
        #expect(r2 == .exploring)
    }

    // MARK: testMigrationIsIdempotent

    @Test("migrateExistingSaves does not overwrite an already-labeled primary church")
    func testMigrationIsIdempotent() async {
        let churchID = "primary-church-\(UUID().uuidString)"

        // Pre-label as primary (in-memory only — no auth uid available in tests)
        await ConstellationService.shared.setRelationship(.primary, for: churchID)

        // Migration should skip it since it's already in the cache
        await ConstellationService.shared.migrateExistingSaves(churchIDs: [churchID])

        let rel = await ConstellationService.shared.relationship(for: churchID)
        #expect(rel == .primary)
    }
}

// MARK: - VisitVerificationService Testability Extension

extension VisitVerificationService {
    /// Exposes the count of currently registered church regions for test assertions.
    var registeredChurchCount: Int { registeredChurches.count }
}
