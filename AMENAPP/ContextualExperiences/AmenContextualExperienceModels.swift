import Foundation
import FirebaseFirestore

// MARK: - Core Types

enum AmenContextualOrganizationType: String, Codable, CaseIterable, Identifiable {
    case church
    case school
    case university
    case ministry
    case business
    case enterprise
    case nonprofit
    case prayerGroup
    case creatorCommunity
    case campusGroup
    case bibleStudy
    case communityGroup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .church: return "Church"
        case .school: return "School"
        case .university: return "University"
        case .ministry: return "Ministry"
        case .business: return "Business"
        case .enterprise: return "Enterprise"
        case .nonprofit: return "Nonprofit"
        case .prayerGroup: return "Prayer Group"
        case .creatorCommunity: return "Creator Community"
        case .campusGroup: return "Campus Group"
        case .bibleStudy: return "Bible Study"
        case .communityGroup: return "Community Group"
        }
    }
}

enum AmenContextualExperienceType: String, Codable, CaseIterable, Identifiable {
    case easter
    case christmas
    case lent
    case advent
    case thanksgiving
    case schoolSpiritWeek
    case graduation
    case chapelWeek
    case worshipNight
    case youthCamp
    case vbs
    case revivalWeek
    case missionTrip
    case conference
    case fastingCampaign
    case prayerCampaign
    case memorial
    case mentalHealthAwareness
    case organizationAnniversary
    case localCelebration
    case emergencyPrayerMobilization

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easter: return "Easter"
        case .christmas: return "Christmas"
        case .lent: return "Lent"
        case .advent: return "Advent"
        case .thanksgiving: return "Gratitude"
        case .schoolSpiritWeek: return "School Spirit Week"
        case .graduation: return "Graduation"
        case .chapelWeek: return "Chapel Week"
        case .worshipNight: return "Worship Night"
        case .youthCamp: return "Youth Camp"
        case .vbs: return "VBS"
        case .revivalWeek: return "Revival Week"
        case .missionTrip: return "Mission Trip"
        case .conference: return "Conference"
        case .fastingCampaign: return "Fasting Campaign"
        case .prayerCampaign: return "Prayer Campaign"
        case .memorial: return "Memorial"
        case .mentalHealthAwareness: return "Mental Health Awareness"
        case .organizationAnniversary: return "Organization Anniversary"
        case .localCelebration: return "Local Celebration"
        case .emergencyPrayerMobilization: return "Emergency Prayer"
        }
    }

    var symbolName: String {
        switch self {
        case .easter: return "sunrise.fill"
        case .christmas: return "star.fill"
        case .lent, .fastingCampaign: return "leaf.fill"
        case .advent: return "flame.fill"
        case .thanksgiving: return "hands.sparkles.fill"
        case .schoolSpiritWeek, .graduation, .chapelWeek: return "graduationcap.fill"
        case .worshipNight: return "music.mic"
        case .youthCamp, .vbs: return "figure.2.and.child.holdinghands"
        case .revivalWeek: return "sparkles"
        case .missionTrip: return "globe.americas.fill"
        case .conference: return "person.3.sequence.fill"
        case .prayerCampaign, .emergencyPrayerMobilization: return "hands.sparkles.fill"
        case .memorial: return "heart.text.square.fill"
        case .mentalHealthAwareness: return "brain.head.profile"
        case .organizationAnniversary: return "calendar.badge.clock"
        case .localCelebration: return "party.popper.fill"
        }
    }
}

enum AmenContextualExperienceVisibility: String, Codable, CaseIterable, Identifiable {
    case `public`
    case members
    case internalOnly = "internal"
    case `private`

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .public: return "Public"
        case .members: return "Members"
        case .internalOnly: return "Internal"
        case .private: return "Private"
        }
    }
}

enum AmenContextualExperienceStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case published
    case archived
    case ended

    var id: String { rawValue }
}

enum AmenContextualExperienceLayer: String, Codable, CaseIterable, Identifiable {
    case global
    case regional
    case organization
    case campus
    case group
    case event
    case tradition
    case userAccessibility
    case userEmotional
    case `default`

    var id: String { rawValue }
}

struct AmenExperienceTheme: Codable, Hashable {
    var accentName: String
    var accentHex: String?
    var glassIntensity: Double
    var liquidGlassBehavior: String
    var symbolName: String
    var prefersQuietVisuals: Bool

    static let subtle = AmenExperienceTheme(
        accentName: "default",
        accentHex: nil,
        glassIntensity: 0.32,
        liquidGlassBehavior: "subtle",
        symbolName: "sparkles",
        prefersQuietVisuals: false
    )
}

struct AmenExperienceNotificationRules: Codable, Hashable {
    var enabled: Bool
    var quietHoursEnabled: Bool
    var maxPerDay: Int
    var allowUrgent: Bool

    static let quiet = AmenExperienceNotificationRules(enabled: true, quietHoursEnabled: true, maxPerDay: 1, allowUrgent: false)
}

struct AmenExperienceSafetyRules: Codable, Hashable {
    var griefSensitive: Bool
    var youthProtected: Bool
    var privatePrayerDefault: Bool
    var requireModeration: Bool
    var killSwitch: Bool

    static let standard = AmenExperienceSafetyRules(griefSensitive: false, youthProtected: false, privatePrayerDefault: true, requireModeration: false, killSwitch: false)
}

struct AmenExperienceAccessibilityBehavior: Codable, Hashable {
    var reduceMotionDefault: Bool
    var reduceTransparencyFallback: Bool
    var highContrastSafe: Bool
    var dynamicTypeRequired: Bool

    static let standard = AmenExperienceAccessibilityBehavior(reduceMotionDefault: false, reduceTransparencyFallback: true, highContrastSafe: true, dynamicTypeRequired: true)
}

struct AmenExperienceModerationConfiguration: Codable, Hashable {
    var discussionMode: String
    var prayerMode: String
    var reportThreshold: Int

    static let standard = AmenExperienceModerationConfiguration(discussionMode: "moderated", prayerMode: "private", reportThreshold: 3)
}

struct AmenContextualExperience: Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var organizationId: String
    var organizationType: AmenContextualOrganizationType
    var region: String
    var sourceLayer: AmenContextualExperienceLayer
    var experienceType: AmenContextualExperienceType
    var visibility: AmenContextualExperienceVisibility
    var status: AmenContextualExperienceStatus
    var startAt: Date
    var endAt: Date
    var rolesAllowedToManage: [String]
    var theme: AmenExperienceTheme
    var notificationRules: AmenExperienceNotificationRules
    var safetyRules: AmenExperienceSafetyRules
    var accessibilityBehavior: AmenExperienceAccessibilityBehavior
    var moderationConfiguration: AmenExperienceModerationConfiguration
    var participantCount: Int
    var canManage: Bool

    var isActive: Bool {
        status == .published && startAt <= Date() && endAt >= Date() && !safetyRules.killSwitch
    }

    static func from(_ raw: [String: Any], canManage: Bool = false) -> AmenContextualExperience? {
        guard let id = raw["id"] as? String,
              let title = raw["title"] as? String,
              let description = raw["description"] as? String,
              let organizationId = raw["organizationId"] as? String else { return nil }

        let orgType = AmenContextualOrganizationType(rawValue: raw["organizationType"] as? String ?? "church") ?? .church
        let type = AmenContextualExperienceType(rawValue: raw["experienceType"] as? String ?? "prayerCampaign") ?? .prayerCampaign
        let visibility = AmenContextualExperienceVisibility(rawValue: raw["visibility"] as? String ?? "members") ?? .members
        let status = AmenContextualExperienceStatus(rawValue: raw["status"] as? String ?? "draft") ?? .draft
        let layer = AmenContextualExperienceLayer(rawValue: raw["sourceLayer"] as? String ?? "organization") ?? .organization

        return AmenContextualExperience(
            id: id,
            title: title,
            description: description,
            organizationId: organizationId,
            organizationType: orgType,
            region: raw["region"] as? String ?? "global",
            sourceLayer: layer,
            experienceType: type,
            visibility: visibility,
            status: status,
            startAt: AmenContextualExperience.date(from: raw["startAt"]) ?? Date(),
            endAt: AmenContextualExperience.date(from: raw["endAt"]) ?? Date().addingTimeInterval(86400),
            rolesAllowedToManage: raw["rolesAllowedToManage"] as? [String] ?? ["owner", "admin", "pastor", "teacher", "moderator"],
            theme: AmenExperienceTheme.from(raw["theme"] as? [String: Any]),
            notificationRules: AmenExperienceNotificationRules.from(raw["notificationRules"] as? [String: Any]),
            safetyRules: AmenExperienceSafetyRules.from(raw["safetyRules"] as? [String: Any]),
            accessibilityBehavior: AmenExperienceAccessibilityBehavior.from(raw["accessibilityBehavior"] as? [String: Any]),
            moderationConfiguration: AmenExperienceModerationConfiguration.from(raw["moderationConfiguration"] as? [String: Any]),
            participantCount: raw["participantCount"] as? Int ?? 0,
            canManage: canManage
        )
    }

    static func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let millis = value as? Double { return Date(timeIntervalSince1970: millis / 1000) }
        if let millis = value as? Int { return Date(timeIntervalSince1970: Double(millis) / 1000) }
        return nil
    }
}

extension AmenExperienceTheme {
    static func from(_ raw: [String: Any]?) -> AmenExperienceTheme {
        guard let raw else { return .subtle }
        return AmenExperienceTheme(
            accentName: raw["accentName"] as? String ?? "default",
            accentHex: raw["accentHex"] as? String,
            glassIntensity: raw["glassIntensity"] as? Double ?? 0.32,
            liquidGlassBehavior: raw["liquidGlassBehavior"] as? String ?? "subtle",
            symbolName: raw["symbolName"] as? String ?? "sparkles",
            prefersQuietVisuals: raw["prefersQuietVisuals"] as? Bool ?? false
        )
    }
}

extension AmenExperienceNotificationRules {
    static func from(_ raw: [String: Any]?) -> AmenExperienceNotificationRules {
        guard let raw else { return .quiet }
        return AmenExperienceNotificationRules(
            enabled: raw["enabled"] as? Bool ?? true,
            quietHoursEnabled: raw["quietHoursEnabled"] as? Bool ?? true,
            maxPerDay: raw["maxPerDay"] as? Int ?? 1,
            allowUrgent: raw["allowUrgent"] as? Bool ?? false
        )
    }
}

extension AmenExperienceSafetyRules {
    static func from(_ raw: [String: Any]?) -> AmenExperienceSafetyRules {
        guard let raw else { return .standard }
        return AmenExperienceSafetyRules(
            griefSensitive: raw["griefSensitive"] as? Bool ?? false,
            youthProtected: raw["youthProtected"] as? Bool ?? false,
            privatePrayerDefault: raw["privatePrayerDefault"] as? Bool ?? true,
            requireModeration: raw["requireModeration"] as? Bool ?? false,
            killSwitch: raw["killSwitch"] as? Bool ?? false
        )
    }
}

extension AmenExperienceAccessibilityBehavior {
    static func from(_ raw: [String: Any]?) -> AmenExperienceAccessibilityBehavior {
        guard let raw else { return .standard }
        return AmenExperienceAccessibilityBehavior(
            reduceMotionDefault: raw["reduceMotionDefault"] as? Bool ?? false,
            reduceTransparencyFallback: raw["reduceTransparencyFallback"] as? Bool ?? true,
            highContrastSafe: raw["highContrastSafe"] as? Bool ?? true,
            dynamicTypeRequired: raw["dynamicTypeRequired"] as? Bool ?? true
        )
    }
}

extension AmenExperienceModerationConfiguration {
    static func from(_ raw: [String: Any]?) -> AmenExperienceModerationConfiguration {
        guard let raw else { return .standard }
        return AmenExperienceModerationConfiguration(
            discussionMode: raw["discussionMode"] as? String ?? "moderated",
            prayerMode: raw["prayerMode"] as? String ?? "private",
            reportThreshold: raw["reportThreshold"] as? Int ?? 3
        )
    }
}

struct AmenContextualExperienceStackResolution: Hashable {
    var activeExperienceId: String?
    var sourceLayer: AmenContextualExperienceLayer
    var theme: AmenExperienceTheme
    var bannerTitle: String?
    var bannerSubtitle: String?
    var secondaryExperiences: [AmenContextualExperience]
    var debugRows: [String]

    static let empty = AmenContextualExperienceStackResolution(
        activeExperienceId: nil,
        sourceLayer: .default,
        theme: .subtle,
        bannerTitle: nil,
        bannerSubtitle: nil,
        secondaryExperiences: [],
        debugRows: []
    )
}

struct AmenExperienceDraft: Hashable {
    var title = ""
    var description = ""
    var organizationId = ""
    var organizationType: AmenContextualOrganizationType = .church
    var region = "global"
    var sourceLayer: AmenContextualExperienceLayer = .organization
    var experienceType: AmenContextualExperienceType = .prayerCampaign
    var visibility: AmenContextualExperienceVisibility = .members
    var startAt = Date()
    var endAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(604800)
    var theme = AmenExperienceTheme.subtle
    var notificationRules = AmenExperienceNotificationRules.quiet
    var safetyRules = AmenExperienceSafetyRules.standard
    var accessibilityBehavior = AmenExperienceAccessibilityBehavior.standard
    var moderationConfiguration = AmenExperienceModerationConfiguration.standard

    init() {}

    init(experience: AmenContextualExperience) {
        title = experience.title
        description = experience.description
        organizationId = experience.organizationId
        organizationType = experience.organizationType
        region = experience.region
        sourceLayer = experience.sourceLayer
        experienceType = experience.experienceType
        visibility = experience.visibility
        startAt = experience.startAt
        endAt = experience.endAt
        theme = experience.theme
        notificationRules = experience.notificationRules
        safetyRules = experience.safetyRules
        accessibilityBehavior = experience.accessibilityBehavior
        moderationConfiguration = experience.moderationConfiguration
    }

    var payload: [String: Any] {
        [
            "title": title,
            "description": description,
            "organizationId": organizationId,
            "organizationType": organizationType.rawValue,
            "region": region,
            "sourceLayer": sourceLayer.rawValue,
            "experienceType": experienceType.rawValue,
            "visibility": visibility.rawValue,
            "startAt": startAt.timeIntervalSince1970 * 1000,
            "endAt": endAt.timeIntervalSince1970 * 1000,
            "theme": [
                "accentName": theme.accentName,
                "accentHex": theme.accentHex as Any,
                "glassIntensity": theme.glassIntensity,
                "liquidGlassBehavior": theme.liquidGlassBehavior,
                "symbolName": theme.symbolName,
                "prefersQuietVisuals": theme.prefersQuietVisuals
            ],
            "notificationRules": [
                "enabled": notificationRules.enabled,
                "quietHoursEnabled": notificationRules.quietHoursEnabled,
                "maxPerDay": notificationRules.maxPerDay,
                "allowUrgent": notificationRules.allowUrgent
            ],
            "safetyRules": [
                "griefSensitive": safetyRules.griefSensitive,
                "youthProtected": safetyRules.youthProtected,
                "privatePrayerDefault": safetyRules.privatePrayerDefault,
                "requireModeration": safetyRules.requireModeration,
                "killSwitch": safetyRules.killSwitch
            ],
            "accessibilityBehavior": [
                "reduceMotionDefault": accessibilityBehavior.reduceMotionDefault,
                "reduceTransparencyFallback": accessibilityBehavior.reduceTransparencyFallback,
                "highContrastSafe": accessibilityBehavior.highContrastSafe,
                "dynamicTypeRequired": accessibilityBehavior.dynamicTypeRequired
            ],
            "moderationConfiguration": [
                "discussionMode": moderationConfiguration.discussionMode,
                "prayerMode": moderationConfiguration.prayerMode,
                "reportThreshold": moderationConfiguration.reportThreshold
            ],
            "featureFlags": [
                "enabled": true,
                "killSwitch": safetyRules.killSwitch,
                "liquidGlassEnabled": true
            ]
        ]
    }
}
