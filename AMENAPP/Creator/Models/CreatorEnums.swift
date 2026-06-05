import Foundation

enum CreatorProjectType: String, Codable, CaseIterable {
    case videoClip
    case flyer
    case testimonyPack
    case sermonSnippet
    case eventPromo
    case quoteGraphic
    case campaignKit
    case multiAssetCampaign
}

enum CreatorProjectStatus: String, Codable {
    case draft
    case processing
    case ready
    case failed
    case published
}

enum CreatorProjectVisibility: String, Codable {
    case `private`
    case unlisted
    case publicPost
}

enum CreatorAssetType: String, Codable {
    case image
    case video
    case audio
    case document
}

enum CreatorAssetSource: String, Codable {
    case device
    case amen
    case church
    case imported
}

enum CreatorAspectRatio: String, Codable, CaseIterable {
    case square
    case portrait
    case landscape
}

enum CreatorOutputVariant: String, Codable, CaseIterable {
    case feedSquare
    case reelVertical
    case flyerImage
    case quoteCard
    case teaser
}

enum CreatorPublishTarget: String, Codable, CaseIterable {
    case openTable
    case testimonies
    case prayer
    case churchPage
    case resourcesLibrary
    case draftOnly
}

enum CreatorJobType: String, Codable {
    case proxy
    case thumbnail
    case transcription
    case subtitles
    case translation
    case exportRender
    case publish
}

enum CreatorJobStatus: String, Codable {
    case queued
    case running
    case completed
    case failed
}

enum CreatorModerationStatus: String, Codable {
    case pending
    case approved
    case flagged
    case blocked
}

enum AuthenticityStatus: String, Codable {
    case unverified
    case verified
    case warning
    case blocked
}

enum BrandKitScope: String, Codable {
    case personal
    case church
}

enum CreatorFontStyle: String, Codable, CaseIterable {
    case classic
    case modern
    case bold
    case serif
}

enum CreatorCaptionStyle: String, Codable, CaseIterable {
    case minimal
    case highContrast
    case softGlass
}

enum CreatorTransitionType: String, Codable, CaseIterable {
    case none
    case crossFade
    case slide
    case zoom
}

enum CreatorLayerKind: String, Codable {
    case asset
    case text
    case subtitle
    case sticker
}

enum CreatorSuggestionKind: String, Codable {
    case action
    case edit
    case export
}

struct CreatorSourceContext: Codable, Hashable {
    let sourceType: String
    let sourceId: String
    let metadata: [String: String]?
}
