import Foundation

enum VisibilityLevel: String, Codable, CaseIterable {
    case publicVisible
    case followersOnly
    case mutualsOnly
    case privateOnly
    case churchAdminsOnly
}
