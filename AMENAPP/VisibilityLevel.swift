import Foundation

enum VisibilityLevel: String, Codable, CaseIterable {
    case publicVisible
    case mutualsOnly
    case privateOnly
    case churchAdminsOnly
}
