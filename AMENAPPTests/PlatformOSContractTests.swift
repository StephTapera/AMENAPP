import Foundation
import Testing
@testable import AMENAPP

@Suite("Platform OS Contracts")
struct PlatformOSContractTests {
    @Test("all operating-system layers are represented")
    func allLayersAreRepresented() {
        #expect(PlatformOSLayer.allCases.count == 26)
        #expect(PlatformOSLayer.allCases.contains(.identity))
        #expect(PlatformOSLayer.allCases.contains(.recovery))
        #expect(PlatformOSLayer.allCases.contains(.governance))
    }

    @Test("platform OS rollout defaults off")
    func rolloutDefaultsOff() {
        let rollout = PlatformOSRollout.allOff

        for layer in PlatformOSLayer.allCases {
            #expect(rollout.isEnabled(layer) == false)
        }
    }

    @Test("disabled gate fails closed")
    func disabledGateFailsClosed() async {
        let gate = DisabledPlatformOSGate()

        let featureAllowed = await gate.can("user-1", perform: "creator_payouts")
        let permissionAllowed = await gate.can("actor-1", perform: "transfer_owner", on: "church-1")

        #expect(featureAllowed == false)
        #expect(permissionAllowed == false)
    }

    @Test("foundational dependency order is stable")
    func foundationalDependencyOrderIsStable() {
        #expect(PlatformOSDependencyOrder.foundational == [
            .identity,
            .rolePermission,
            .entitlement,
            .subscription,
            .recovery,
            .audit
        ])
    }

    @Test("gap records preserve severity, references, and deferral reason")
    func gapRecordsAreReviewable() {
        let gap = PlatformOSGap(
            id: "POS-ROLE-001",
            layer: .rolePermission,
            severity: .p0,
            summary: "Role mutation must pass through one authorization gate.",
            fileReferences: ["AMENAPP/AMENAPP/RolePermissionService.swift:17"],
            deferredReason: "Requires Firestore rules and callable review."
        )

        #expect(gap.id == "POS-ROLE-001")
        #expect(gap.severity == .p0)
        #expect(gap.fileReferences.count == 1)
        #expect(gap.deferredReason == "Requires Firestore rules and callable review.")
    }
}
