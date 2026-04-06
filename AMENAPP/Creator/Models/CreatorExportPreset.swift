import Foundation

struct CreatorExportPreset: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var aspectRatio: CreatorAspectRatio
    var outputVariant: CreatorOutputVariant
    var resolution: String
    var isPremium: Bool
}
