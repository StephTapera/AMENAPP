import XCTest
@testable import AMENAPP

final class ContextOSContractTests: XCTestCase {

    func testConsentDefaultsOnlyEnableOnDeviceRhythm() {
        let defaults = ConsentState.defaults(now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(defaults.count, ConsentEdge.allCases.count)
        XCTAssertEqual(defaults.filter(\.isEnabled).map(\.edge), [.activityToRhythm])
    }

    func testContextSignalRoundTripsThroughJSON() throws {
        let signal = ContextSignal(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            type: .noteSaved,
            tierCeiling: .c,
            subjectRefs: [GraphRef(nodeType: .note, nodeID: "note_123")],
            payload: [
                "wordCount": .int(128),
                "source": .string("church_notes"),
                "isDraft": .bool(false),
                "themes": .array([.string("missions"), .string("generosity")])
            ],
            occurredAt: Date(timeIntervalSince1970: 1_735_689_600),
            decayHalfLifeDays: 30,
            consentEdgeRequired: .notesToMatching
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(signal)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ContextSignal.self, from: data)

        XCTAssertEqual(decoded, signal)
    }

    func testConsentEdgeSerializesAsFrozenWireValue() throws {
        let state = ConsentState(
            edge: .crossDeviceContinuity,
            isEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = String(data: try encoder.encode(state), encoding: .utf8)

        XCTAssertTrue(json?.contains("\"crossDeviceContinuity\"") == true)
    }

    func testGateDecisionCrisisSuppressionIsDenied() throws {
        let decision = GateDecision.crisisSuppressed

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.reason, .crisisSuppressed)

        let data = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(GateDecision.self, from: data)
        XCTAssertEqual(decoded, decision)
    }
}
