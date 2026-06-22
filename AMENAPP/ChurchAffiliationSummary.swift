import Foundation

struct ChurchAffiliationSummary: Codable, Hashable {
    let churchId: String
    let churchName: String?
    let relationshipType: ChurchRelationshipType
    let visibility: VisibilityLevel
    let displayEnabled: Bool
    let isPrimaryChurch: Bool
}
