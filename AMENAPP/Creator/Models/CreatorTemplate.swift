import Foundation

struct CreatorTemplate: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String?
    var previewURL: String?
    var projectType: CreatorProjectType
    var outputVariants: [CreatorOutputVariant]
    var isPremium: Bool
    var createdAt: Date
}
