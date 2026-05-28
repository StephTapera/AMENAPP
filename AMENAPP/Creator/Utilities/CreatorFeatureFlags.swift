import Foundation

struct CreatorFeatureFlags: Codable, Hashable {
    var creatorEnabled: Bool
    var creatorVideoEnabled: Bool
    var creatorCampaignBuilderEnabled: Bool
    var creatorTranslationEnabled: Bool
    var creatorBrandKitsEnabled: Bool
    var creatorPublishToChurchEnabled: Bool
    var creatorTemplatesEnabled: Bool
    var creatorPremiumEnabled: Bool
    var creatorAuthenticityChecksEnabled: Bool

    static let `default` = CreatorFeatureFlags(
        creatorEnabled: true,
        creatorVideoEnabled: true,
        creatorCampaignBuilderEnabled: true,
        creatorTranslationEnabled: true,
        creatorBrandKitsEnabled: true,
        creatorPublishToChurchEnabled: true,
        creatorTemplatesEnabled: true,
        creatorPremiumEnabled: true,
        creatorAuthenticityChecksEnabled: true
    )
}
