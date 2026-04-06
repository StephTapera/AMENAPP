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
        creatorEnabled: false,
        creatorVideoEnabled: false,
        creatorCampaignBuilderEnabled: false,
        creatorTranslationEnabled: false,
        creatorBrandKitsEnabled: false,
        creatorPublishToChurchEnabled: false,
        creatorTemplatesEnabled: false,
        creatorPremiumEnabled: false,
        creatorAuthenticityChecksEnabled: false
    )
}
