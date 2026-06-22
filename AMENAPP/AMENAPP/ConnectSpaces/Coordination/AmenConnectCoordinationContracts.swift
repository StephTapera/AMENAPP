import Foundation

/// Organization contract: polymorphic customer root; church is one orgType value, not a special model.
struct AmenConnectOrganization: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let orgType: AmenConnectOrgType
}

/// Organization type contract: generic org taxonomy used by coordination behavior.
enum AmenConnectOrgType: String, Codable, CaseIterable, Equatable, Sendable {
    case church
    case school
    case nonprofit
    case team
    case company
    case other
}

/// Team contract: generic coordination group scoped to an organization.
struct AmenConnectTeam: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let orgId: String
    let name: String
}

/// Role contract: required coverage unit for a team.
struct AmenConnectCoordinationRole: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let teamId: String
    let name: String
    let countNeeded: Int
}

/// Person contract: participant facts scoped to an organization.
struct AmenConnectPerson: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let orgId: String
    let name: String
    let skillIds: [String]
    let certificationIds: [String]
    let availability: AmenConnectAvailability?
}

/// Skill contract: reusable capability required by roles or people.
struct AmenConnectSkill: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// Certification contract: person-held credential with an expiry date for alerts.
struct AmenConnectCertification: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let personId: String
    let type: AmenConnectCertificationType
    let expiresAt: Date
}

/// Certification type contract: includes safety credentials without making them church-specific.
enum AmenConnectCertificationType: String, Codable, CaseIterable, Equatable, Sendable {
    case backgroundCheck = "background-check"
    case childSafety = "child-safety"
    case safetyTraining = "safety-training"
    case roleTraining = "role-training"
    case other
}

/// Availability contract: simple V0 pattern attached to a person.
struct AmenConnectAvailability: Codable, Equatable, Sendable {
    let personId: String
    let pattern: String
}

/// Reliability signal contract: attendance facts only; no judgment label is computed from this model.
struct AmenConnectReliabilitySignal: Codable, Equatable, Sendable {
    let personId: String
    let attendedCount: Int
    let declinedCount: Int
}

/// Assignment contract: person-to-role coverage state for one event or shift.
struct AmenConnectAssignment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let eventOrShiftId: String
    let roleId: String
    let personId: String
    let status: AmenConnectAssignmentStatus
}

/// Assignment status contract: V0 coordination lifecycle states.
enum AmenConnectAssignmentStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case signedUp
    case confirmed
    case declined
    case waitlisted
}

/// Readiness view contract: transparent derived coverage rollup with named gaps.
struct AmenConnectReadinessView: Codable, Equatable, Sendable {
    let eventOrShiftId: String
    let roleCoverage: [AmenConnectRoleCoverage]
    let teamCoverage: [AmenConnectTeamCoverage]
    let organizationCoverage: AmenConnectCoverageSummary
    let openGaps: [AmenConnectOpenGap]

    var coverage: Double { organizationCoverage.coverage }
    var worstOpenGap: AmenConnectOpenGap? { openGaps.first }
}

/// Readiness pill model contract: compact Liquid Glass capsule payload.
struct AmenConnectReadinessPillModel: Codable, Equatable, Sendable {
    let label: String
    let coverage: Double
    let worstOpenGap: AmenConnectOpenGap?
}

/// Role coverage contract: derived coverage details for one role.
struct AmenConnectRoleCoverage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let roleId: String
    let teamId: String
    let roleName: String
    let countNeeded: Int
    let filledCount: Int
    let coverage: Double
}

/// Team coverage contract: derived coverage details for one team.
struct AmenConnectTeamCoverage: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let teamId: String
    let teamName: String
    let countNeeded: Int
    let filledCount: Int
    let coverage: Double
}

/// Coverage summary contract: derived aggregate totals.
struct AmenConnectCoverageSummary: Codable, Equatable, Sendable {
    let countNeeded: Int
    let filledCount: Int
    let coverage: Double
}

/// Open gap contract: named shortage surfaced by the readiness rollup.
struct AmenConnectOpenGap: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(teamId)-\(roleId)" }
    let teamId: String
    let teamName: String
    let roleId: String
    let roleName: String
    let neededCount: Int
    let filledCount: Int
    let openCount: Int

    var displayName: String { "\(teamName) · \(roleName)" }
}

/// Certification alert contract: derived expiry alert for credentials approaching or past expiry.
struct AmenConnectCertificationAlert: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let personId: String
    let certificationId: String
    let type: AmenConnectCertificationType
    let expiresAt: Date
    let state: AmenConnectCertificationAlertState
}

/// Certification alert state contract: date-derived credential alert state.
enum AmenConnectCertificationAlertState: String, Codable, Equatable, Sendable {
    case expired
    case expiringSoon
}
