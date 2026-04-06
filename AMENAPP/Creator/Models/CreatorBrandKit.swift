import Foundation

struct CreatorBrandKit: Codable, Identifiable, Hashable {
    let id: String
    let ownerID: String
    var scope: BrandKitScope
    var name: String
    var primaryHex: String?
    var secondaryHex: String?
    var accentHex: String?
    var logoURL: String?
    var fontStyle: CreatorFontStyle
    var defaultCaptionStyle: CreatorCaptionStyle
    var createdAt: Date
    var updatedAt: Date
}
