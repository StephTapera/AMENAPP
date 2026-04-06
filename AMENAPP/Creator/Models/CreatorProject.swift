import Foundation

struct CreatorProject: Codable, Identifiable, Hashable {
    let id: String
    let ownerID: String
    var title: String
    var projectType: CreatorProjectType
    var status: CreatorProjectStatus
    var visibility: CreatorProjectVisibility
    var thumbnailURL: String?
    var aspectRatio: CreatorAspectRatio
    var assetIDs: [String]
    var layerIDs: [String]
    var sceneIDs: [String]
    var subtitleTrackIDs: [String]
    var templateID: String?
    var brandKitID: String?
    var coverAssetID: String?
    var coverImageURL: String?
    var coverFrameTimeMs: Int?
    var outputVariants: [CreatorOutputVariant]
    var publishTargets: [CreatorPublishTarget]
    var autosaveVersion: Int
    var lastEditedAt: Date
    var createdAt: Date
    var publishedAt: Date?
    var sourceContext: CreatorSourceContext?
    var premiumRequired: Bool
}
