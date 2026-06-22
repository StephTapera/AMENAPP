#if canImport(Testing)
import Foundation
import Testing
@testable import AMENAPP

@Suite("Berean Camera Media Gate contracts")
struct BereanCameraMediaGateContractsTests {

    @Test("I1 required stage failure fails closed to non-publish")
    func requiredStageFailureFailsClosed() {
        let decision = MediaGateInvariants.decisionAfterRequiredStageFailure()
        #expect(decision != .publish)
        #expect(decision == .review || decision == .block)
    }

    @Test("I2 audit record stores decisions only")
    func auditRecordHasNoRawData() {
        let audit = MediaGateSafetyAuditRecord(
            auditId: UUID(),
            postId: "post_123",
            createdAt: Date(),
            providerVersion: "managed-provider-unconfigured",
            modelVersion: "policy-v0",
            findingCategories: [.faceCandidate, .plateCandidate],
            actionsTaken: ["blurRegion", "stripEXIF", "removeLocation"],
            policyDecision: .review,
            appealStatus: .none,
            reviewerDecision: nil,
            retentionExpiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30),
            openAppealMediaReference: nil
        )

        #expect(audit.containsRawMediaOrPrivateText == false)
    }

    @Test("I3 CSAM hash path is interface-only and default off")
    func csamRouteStaysOffByDefault() {
        #expect(MediaGateInvariants.csamProviderGated)
        #expect(MediaGateInvariants.csamHashScanDefaultEnabled == false)
        #expect(MediaGateInvariants.shouldRouteToCSAMProvider(csamHashScanEnabled: false) == false)
    }

    @Test("PolicyDecision fail-closed default does not publish")
    func policyDecisionDefaultIsReview() {
        #expect(MediaGatePolicyDecision.failClosedDefault == .review)
        #expect(MediaGatePolicyDecision.failClosedDefault.allowsPublishWithoutReview == false)
    }
}
#endif
