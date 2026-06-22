import Foundation

enum ChurchRelationshipType: String, Codable, CaseIterable {
    case attends
    case member
    case serves
    case leads
    case watchesOnline
    case visited
}
