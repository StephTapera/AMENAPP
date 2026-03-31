import Foundation

struct ChurchMembership: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let churchId: String
    let relationshipType: ChurchRelationshipType
    let visibility: VisibilityLevel
    let displayOnProfile: Bool
    let isPrimaryChurch: Bool
    let joinedAt: Date
    let source: String
    let status: String
}
