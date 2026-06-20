import Foundation

struct AmenConnectCoordinationBehavior: Equatable, Sendable {
    let orgType: AmenConnectOrgType
    let safetyCertificationTypes: Set<AmenConnectCertificationType>

    static func behavior(for organization: AmenConnectOrganization) -> AmenConnectCoordinationBehavior {
        let safetyTypes: Set<AmenConnectCertificationType>
        switch organization.orgType {
        case .church, .school, .nonprofit, .team, .company, .other:
            safetyTypes = [.backgroundCheck, .childSafety]
        }
        return AmenConnectCoordinationBehavior(
            orgType: organization.orgType,
            safetyCertificationTypes: safetyTypes
        )
    }
}

struct AmenConnectCertificationAlertService {
    var alertWindow: TimeInterval = 30 * 24 * 60 * 60

    func alerts(
        for certifications: [AmenConnectCertification],
        now: Date = Date()
    ) -> [AmenConnectCertificationAlert] {
        certifications.compactMap { certification in
            let secondsUntilExpiry = certification.expiresAt.timeIntervalSince(now)
            let state: AmenConnectCertificationAlertState?

            if secondsUntilExpiry < 0 {
                state = .expired
            } else if secondsUntilExpiry <= alertWindow {
                state = .expiringSoon
            } else {
                state = nil
            }

            guard let state else { return nil }
            return AmenConnectCertificationAlert(
                id: "\(certification.id)-\(state.rawValue)",
                personId: certification.personId,
                certificationId: certification.id,
                type: certification.type,
                expiresAt: certification.expiresAt,
                state: state
            )
        }
        .sorted { lhs, rhs in
            if lhs.expiresAt == rhs.expiresAt { return lhs.certificationId < rhs.certificationId }
            return lhs.expiresAt < rhs.expiresAt
        }
    }
}

struct AmenConnectReadinessService {
    func makeReadinessView(
        eventOrShiftId: String,
        organization: AmenConnectOrganization,
        teams: [AmenConnectTeam],
        roles: [AmenConnectRole],
        assignments: [AmenConnectAssignment]
    ) -> AmenConnectReadinessView {
        _ = AmenConnectCoordinationBehavior.behavior(for: organization)

        let teamsById = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        let coveringAssignments = assignments.filter { assignment in
            assignment.eventOrShiftId == eventOrShiftId
                && (assignment.status == .signedUp || assignment.status == .confirmed)
        }
        let assignmentsByRole = Dictionary(grouping: coveringAssignments, by: \ .roleId)

        let roleCoverage = roles.map { role in
            let filled = min(assignmentsByRole[role.id]?.count ?? 0, max(role.countNeeded, 0))
            let needed = max(role.countNeeded, 0)
            return AmenConnectRoleCoverage(
                id: role.id,
                roleId: role.id,
                teamId: role.teamId,
                roleName: role.name,
                countNeeded: needed,
                filledCount: filled,
                coverage: Self.coverage(filled: filled, needed: needed)
            )
        }

        let roleCoverageByTeam = Dictionary(grouping: roleCoverage, by: \ .teamId)
        let teamCoverage = teams.map { team in
            let coverageItems = roleCoverageByTeam[team.id] ?? []
            let needed = coverageItems.reduce(0) { $0 + $1.countNeeded }
            let filled = coverageItems.reduce(0) { $0 + $1.filledCount }
            return AmenConnectTeamCoverage(
                id: team.id,
                teamId: team.id,
                teamName: team.name,
                countNeeded: needed,
                filledCount: filled,
                coverage: Self.coverage(filled: filled, needed: needed)
            )
        }

        let totalNeeded = roleCoverage.reduce(0) { $0 + $1.countNeeded }
        let totalFilled = roleCoverage.reduce(0) { $0 + $1.filledCount }
        let gaps = roleCoverage.compactMap { coverage -> AmenConnectOpenGap? in
            let open = max(coverage.countNeeded - coverage.filledCount, 0)
            guard open > 0 else { return nil }
            let team = teamsById[coverage.teamId]
            return AmenConnectOpenGap(
                teamId: coverage.teamId,
                teamName: team?.name ?? "Team",
                roleId: coverage.roleId,
                roleName: coverage.roleName,
                neededCount: coverage.countNeeded,
                filledCount: coverage.filledCount,
                openCount: open
            )
        }
        .sorted { lhs, rhs in
            if lhs.openCount == rhs.openCount { return lhs.displayName < rhs.displayName }
            return lhs.openCount > rhs.openCount
        }

        return AmenConnectReadinessView(
            eventOrShiftId: eventOrShiftId,
            roleCoverage: roleCoverage,
            teamCoverage: teamCoverage,
            organizationCoverage: AmenConnectCoverageSummary(
                countNeeded: totalNeeded,
                filledCount: totalFilled,
                coverage: Self.coverage(filled: totalFilled, needed: totalNeeded)
            ),
            openGaps: gaps
        )
    }

    func makePillModel(label: String, readinessView: AmenConnectReadinessView) -> AmenConnectReadinessPillModel {
        AmenConnectReadinessPillModel(
            label: label,
            coverage: readinessView.coverage,
            worstOpenGap: readinessView.worstOpenGap
        )
    }

    private static func coverage(filled: Int, needed: Int) -> Double {
        guard needed > 0 else { return 1 }
        return min(Double(filled) / Double(needed), 1)
    }
}
