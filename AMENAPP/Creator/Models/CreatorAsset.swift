import Foundation

struct CreatorAsset: Codable, Identifiable, Hashable {
    let id: String
    let ownerID: String
    var projectID: String
    var type: CreatorAssetType
    var localIdentifier: String?
    var storagePath: String?
    var downloadURL: String?
    var thumbnailURL: String?
    var proxyURL: String?
    var durationMs: Int?
    var width: Int?
    var height: Int?
    var fileSizeBytes: Int?
    var mimeType: String?
    var checksum: String?
    var source: CreatorAssetSource
    var moderationStatus: ModerationStatus
    var authenticityStatus: AuthenticityStatus
    var createdAt: Date
}
