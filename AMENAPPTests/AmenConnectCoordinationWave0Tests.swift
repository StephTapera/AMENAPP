import Foundation
import Testing
@testable import AMENAPP

@Suite("AMEN Connect Coordination Wave 0")
struct AmenConnectCoordinationWave0Tests {
    @Test("Organization stays polymorphic with church as one orgType")
    func organizationIsPolymorphic() {
        let church = AmenConnectOrganization(id: "org-church", name: "Grace", orgType: .church)
        let school = AmenConnectOrganization(id: "org-school", name: "Hope School", orgType: .school)

        #expect(AmenConnectOrgType.allCases.contains(.church))
        #expect(church.orgType != school.orgType)
        #expect(AmenConnectCoordinationBehavior.behavior(for: church).safetyCertificationTypes == AmenConnectCoordinationBehavior.behavior(for: school).safetyCertificationTypes)
    }

    @Test("Certification tracking returns expiry alerts for background-check and child-safety certs")
    func certificationExpiryAlerts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = AmenConnectCertificationAlertService(alertWindow: 30 * 24 * 60 * 60)
        let alerts = service.alerts(for: [
            AmenConnectCertification(id: "cert-bg", personId: "p1", type: .backgroundCheck, expiresAt: now.addingTimeInterval(10 * 24 * 60 * 60)),
            AmenConnectCertification(id: "cert-child", personId: "p2", type: .childSafety, expiresAt: now.addingTimeInterval(-60)),
            AmenConnectCertification(id: "cert-future", personId: "p3", type: .roleTraining, expiresAt: now.addingTimeInterval(90 * 24 * 60 * 60)),
        ], now: now)

        #expect(alerts.map(\.type).contains(.backgroundCheck))
        #expect(alerts.map(\.type).contains(.childSafety))
        #expect(alerts.count == 2)
        #expect(alerts.first?.state == .expired)
    }

    @Test("ReadinessView is derived from assignments and names open gaps")
    func readinessIsDerivedWithNamedGaps() {
        let organization = AmenConnectOrganization(id: "org-1", name: "Grace", orgType: .church)
        let teams = [AmenConnectTeam(id: "team-kids", orgId: organization.id, name: "Kids")]
        let roles = [
            AmenConnectRole(id: "role-checkin", teamId: "team-kids", name: "Check-in", countNeeded: 2),
            AmenConnectRole(id: "role-room", teamId: "team-kids", name: "Room Lead", countNeeded: 1),
        ]
        let assignments = [
            AmenConnectAssignment(id: "a1", eventOrShiftId: "sunday", roleId: "role-checkin", personId: "p1", status: .confirmed),
            AmenConnectAssignment(id: "a2", eventOrShiftId: "sunday", roleId: "role-checkin", personId: "p2", status: .declined),
            AmenConnectAssignment(id: "a3", eventOrShiftId: "other", roleId: "role-room", personId: "p3", status: .confirmed),
        ]

        let readiness = AmenConnectReadinessService().makeReadinessView(
            eventOrShiftId: "sunday",
            organization: organization,
            teams: teams,
            roles: roles,
            assignments: assignments
        )

        #expect(readiness.organizationCoverage.countNeeded == 3)
        #expect(readiness.organizationCoverage.filledCount == 1)
        #expect(readiness.openGaps.map(\.displayName).contains("Kids · Room Lead"))
        #expect(readiness.openGaps.map(\.displayName).contains("Kids · Check-in"))
    }

    @Test("ReliabilitySignal remains attendance facts only")
    func reliabilitySignalIsFactsOnly() {
        let signal = AmenConnectReliabilitySignal(personId: "p1", attendedCount: 4, declinedCount: 1)

        #expect(signal.attendedCount == 4)
        #expect(signal.declinedCount == 1)
        #expect(Mirror(reflecting: signal).children.map { $0.label ?? "" } == ["personId", "attendedCount", "declinedCount"])
    }

    @Test("Readiness pill is fed by derived readiness and exposes worst open gap")
    func readinessPillModelUsesReadinessView() {
        let gap = AmenConnectOpenGap(
            teamId: "team-kids",
            teamName: "Kids",
            roleId: "role-checkin",
            roleName: "Check-in",
            neededCount: 2,
            filledCount: 1,
            openCount: 1
        )
        let readiness = AmenConnectReadinessView(
            eventOrShiftId: "sunday",
            roleCoverage: [],
            teamCoverage: [],
            organizationCoverage: AmenConnectCoverageSummary(countNeeded: 9, filledCount: 8, coverage: 8.0 / 9.0),
            openGaps: [gap]
        )

        let model = AmenConnectReadinessService().makePillModel(label: "Sunday Service", readinessView: readiness)

        #expect(model.label == "Sunday Service")
        #expect(model.coverage == readiness.coverage)
        #expect(model.worstOpenGap?.displayName == "Kids · Check-in")
    }
}
