import Foundation

enum AmenObjectHubOpenSource: String, Codable, Hashable {
    case postCardInlineHubPill
    case postCardInlineHubCluster
    case unknown
}

enum AmenObjectHubTarget: Equatable {
    case canonicalObjectId(String)
    case url(String)
}

struct AmenObjectHubPreviewPillModel: Equatable {
    let target: AmenObjectHubTarget
    let objectType: AmenAttachmentType
    let aggregateText: String
    let actionText: String
    let iconName: String
    let safetyState: AmenAttachmentSafetyStatus
    let explicitContentState: AmenExplicitContentState
    let accessibilityLabel: String
}
