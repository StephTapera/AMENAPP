//
//  UserProfileMiniMapper.swift
//  AMENAPP
//
//  Maps the [String: Any] payload from the getUserProfileMiniContext
//  Firebase callable to UserProfileMiniModel. Designed to be resilient:
//
//  - null trigger          → nil (no crash)
//  - unknown artifactType  → trigger dropped (nil)
//  - missing pronoun       → nil
//  - unknown viewerState   → .unknown
//  - unknown reasonKind    → reason dropped (silently, via compactMap)
//  - unknown badgeColor    → .neutral fallback
//

import Foundation

struct UserProfileMiniMapper {

    // MARK: - Primary Entry Point

    /// Returns nil only if required fields (userId, username, displayName) are absent.
    static func model(
        from data: [String: Any],
        source: UserMiniSuggestionSource
    ) -> UserProfileMiniModel? {
        guard
            let id           = data["userId"] as? String, !id.isEmpty,
            let username     = data["username"] as? String,
            let displayName  = data["displayName"] as? String
        else { return nil }

        return UserProfileMiniModel(
            id:                             id,
            username:                       username,
            displayName:                    displayName,
            roleTitle:                      data["roleTitle"] as? String,
            bioShort:                       data["bioShort"] as? String,
            avatarURL:                      url(data["avatarURL"]),
            followerCount:                  data["followerCount"] as? Int,
            sharedPrayerCount:              data["sharedPrayerCount"] as? Int,
            mutualConnectionCount:          data["mutualConnectionCount"] as? Int,
            mutualConnectionPreview:        mutuals(data["mutualConnectionPreview"]),
            city:                           data["city"] as? String,
            pronoun:                        data["pronoun"] as? String,        // nil if missing
            pronunciation:                  data["pronunciation"] as? String,  // nil if missing
            badges:                         badges(data["badges"]),
            contextReasons:                 reasons(data["contextReasons"]),
            suggestionSource:               source,
            credibility:                    credibility(data["credibility"]),
            canMessage:                     data["canMessage"] as? Bool ?? false,
            isFollowed:                     data["isFollowed"] as? Bool ?? false,
            isSavedSuggestion:              false,
            profileRoute:                   data["profileRoute"] as? String,
            trigger:                        trigger(data["trigger"]),
            directRelationshipReason:       data["directRelationshipReason"] as? String,
            recentSharedEngagementReason:   data["recentSharedEngagementReason"] as? String,
            sharedTopicReason:              data["sharedTopicReason"] as? String,
            communityReason:                data["communityReason"] as? String,
            popularityReason:               data["popularityReason"] as? String,
            priorityExplanation:            data["priorityExplanation"] as? String,
            suggestionScore:                data["suggestionScore"] as? Double,
            testimonyOverlapCount:          data["testimonyOverlapCount"] as? Int,
            topicOverlapCount:              data["topicOverlapCount"] as? Int,
            isProfileUnavailable:           data["isProfileUnavailable"] as? Bool ?? false,
            isBlocked:                      data["isBlocked"] as? Bool ?? false,
            publicVerificationSummary:      publicVerificationSummary(data["publicVerificationSummary"])
        )
    }

    // MARK: - Trigger

    /// Returns nil for null trigger OR unrecognised artifactType (no crash).
    private static func trigger(_ value: Any?) -> UserMiniTrigger? {
        guard
            let dict        = value as? [String: Any],
            let typeRaw     = dict["artifactType"] as? String,
            let artifactType = UserMiniTrigger.ArtifactType(rawValue: typeRaw),
            let artifactId  = dict["artifactId"] as? String, !artifactId.isEmpty
        else { return nil }

        return UserMiniTrigger(
            artifactType: artifactType,
            artifactId:   artifactId,
            title:        dict["title"] as? String,
            topic:        dict["topic"] as? String,
            viewerState:  UserMiniTrigger.ViewerState(rawValue: dict["viewerState"] as? String ?? "")
            // ViewerState.init(rawValue:) maps unknown strings → .unknown
        )
    }

    // MARK: - Reasons

    /// Unknown reason kinds are silently dropped; never crash.
    private static func reasons(_ value: Any?) -> [UserMiniReason] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let id       = dict["id"] as? String,
                let label    = dict["label"] as? String,
                let kindRaw  = dict["kind"] as? String,
                let kind     = UserMiniReason.ReasonKind(rawValue: kindRaw)
            else { return nil }

            return UserMiniReason(
                id:    id,
                label: label,
                icon:  dict["icon"] as? String,
                kind:  kind
            )
        }
    }

    // MARK: - Mutuals

    private static func mutuals(_ value: Any?) -> [MiniMutualUser] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let id   = dict["id"] as? String,
                let name = dict["displayName"] as? String
            else { return nil }
            return MiniMutualUser(id: id, displayName: name, avatarURL: url(dict["avatarURL"]))
        }
    }

    // MARK: - Badges

    private static func badges(_ value: Any?) -> [UserMiniBadge] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard
                let id    = dict["id"] as? String,
                let icon  = dict["icon"] as? String,
                let label = dict["label"] as? String
            else { return nil }
            let color = UserMiniBadge.UserMiniBadgeColor(rawValue: dict["color"] as? String ?? "") ?? .neutral
            return UserMiniBadge(id: id, icon: icon, label: label, color: color)
        }
    }

    // MARK: - Credibility

    private static func credibility(_ value: Any?) -> UserMiniCredibility? {
        guard let dict = value as? [String: Any] else { return nil }
        let responseLabel = dict["responseLabel"] as? String
        let activeLabel   = dict["activeLabel"] as? String
        guard responseLabel != nil || activeLabel != nil else { return nil }
        return UserMiniCredibility(responseLabel: responseLabel, activeLabel: activeLabel)
    }

    private static func publicVerificationSummary(_ value: Any?) -> AmenPublicVerificationSummary {
        guard let dict = value as? [String: Any] else { return .empty }
        let safetyRaw = dict["safetyStanding"] as? String ?? ""
        let safetyStanding = AmenSafetyStanding(rawValue: safetyRaw) ?? .active
        let visibleBadges = dict["visibleBadges"] as? [String] ?? []

        return AmenPublicVerificationSummary(
            emailVerified: dict["emailVerified"] as? Bool ?? false,
            phoneVerified: dict["phoneVerified"] as? Bool ?? false,
            identityVerified: dict["identityVerified"] as? Bool ?? false,
            creatorVerified: dict["creatorVerified"] as? Bool ?? false,
            safetyStanding: safetyStanding,
            visibleBadges: visibleBadges,
            updatedAt: nil
        )
    }

    // MARK: - URL Helper

    private static func url(_ value: Any?) -> URL? {
        (value as? String).flatMap { URL(string: $0) }
    }
}
