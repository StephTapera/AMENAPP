import Foundation

protocol SocialV2SpacesServicing {
    func discoverSpaces(for userID: SocialV2Identifier) async throws -> [SocialV2Space]
    func moderationDecision(forPostID postID: SocialV2Identifier) async throws -> SocialV2ModerationDecision
}

protocol SocialV2FeedServicing {
    func loadFeed(kind: SocialV2FeedKind, userID: SocialV2Identifier) async throws -> [SocialV2Identifier]
}

protocol SocialV2SearchServicing {
    func search(
        query: String,
        entities: Set<SocialV2SearchEntity>,
        privacy: SocialV2AIPrivacyToggles
    ) async throws -> [SocialV2Identifier]
}

protocol SocialV2MessagingServicing {
    func scanBeforeDelivery(messageID: SocialV2Identifier) async throws -> SocialV2ModerationDecision
    func loadThreads(userID: SocialV2Identifier) async throws -> [SocialV2MessageThread]
}

protocol SocialV2PrivacySafetyServicing {
    func loadPrivacyToggles(userID: SocialV2Identifier) async throws -> SocialV2AIPrivacyToggles
    func updateLocationScope(_ scope: SocialV2LocationScope, userID: SocialV2Identifier) async throws
}

protocol SocialV2KnowledgeVaultServicing {
    func saveItem(id: SocialV2Identifier, userID: SocialV2Identifier) async throws
    func validateContextNote(id: SocialV2Identifier) async throws -> SocialV2ModerationDecision
}
