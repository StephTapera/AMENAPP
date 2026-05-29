// ContextualExperienceModels.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// Canonical Swift model types for the Contextual Experience layer.
// All types are Codable so they can be decoded from Firestore via
// `try doc.data(as: ModelType.self)` and from Cloud Function responses.
//
// IMPORTANT: Never log prayer content or PII.

import SwiftUI
import FirebaseFirestore

// MARK: - OrganizationType

enum OrganizationType: String, Codable, CaseIterable {
    case church
    case school
    case university
    case ministry
    case business
    case enterprise
    case nonprofit
    case prayerGroup         = "prayer_group"
    case creatorCommunity    = "creator_community"
    case campus

    var displayName: String {
        switch self {
        case .church:            return "Church"
        case .school:            return "School"
        case .university:        return "University"
        case .ministry:          return "Ministry"
        case .business:          return "Business"
        case .enterprise:        return "Enterprise"
        case .nonprofit:         return "Nonprofit"
        case .prayerGroup:       return "Prayer Group"
        case .creatorCommunity:  return "Creator Community"
        case .campus:            return "Campus"
        }
    }

    var icon: String {
        switch self {
        case .church:            return "building.columns.fill"
        case .school:            return "book.closed.fill"
        case .university:        return "graduationcap.fill"
        case .ministry:          return "hands.sparkles.fill"
        case .business:          return "briefcase.fill"
        case .enterprise:        return "building.2.fill"
        case .nonprofit:         return "heart.fill"
        case .prayerGroup:       return "hands.and.sparkles.fill"
        case .creatorCommunity:  return "person.3.fill"
        case .campus:            return "building.fill"
        }
    }
}

// MARK: - OrgMemberRole

enum OrgMemberRole: String, Codable, CaseIterable {
    case owner
    case pastor
    case teacher
    case admin
    case moderator
    case member
    case volunteer
    case youthLeader   = "youth_leader"
    case studentLeader = "student_leader"
    case prayerLead    = "prayer_lead"
    case commsLead     = "comms_lead"

    var displayName: String {
        switch self {
        case .owner:         return "Owner"
        case .pastor:        return "Pastor"
        case .teacher:       return "Teacher"
        case .admin:         return "Admin"
        case .moderator:     return "Moderator"
        case .member:        return "Member"
        case .volunteer:     return "Volunteer"
        case .youthLeader:   return "Youth Leader"
        case .studentLeader: return "Student Leader"
        case .prayerLead:    return "Prayer Lead"
        case .commsLead:     return "Comms Lead"
        }
    }

    var canManageExperiences: Bool {
        [.owner, .pastor, .admin, .commsLead].contains(self)
    }

    var canModerate: Bool {
        [.owner, .pastor, .admin, .moderator].contains(self)
    }

    var isAdmin: Bool {
        [.owner, .pastor, .admin].contains(self)
    }
}

// MARK: - Organization

struct Organization: Codable, Identifiable {
    @DocumentID var id: String?
    let name: String
    let handle: String
    let type: OrganizationType
    let region: String
    let denomination: String?
    let avatarURL: String?
    let bannerURL: String?
    let description: String
    let ownerUserId: String
    let isPublic: Bool
    let isVerified: Bool
    let memberCount: Int
    let createdAt: Date
}

// MARK: - OrgMembership

struct OrgMembership: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let organizationId: String
    let role: OrgMemberRole
    let joinedAt: Date
}

// MARK: - ExperienceType

enum ExperienceType: String, Codable, CaseIterable {
    case celebration
    case prayerCampaign       = "prayer_campaign"
    case event
    case tradition
    case communityChallenge   = "community_challenge"
    case worshipNight         = "worship_night"
    case graduationWeek       = "graduation_week"
    case fasting
    case conferenceMode       = "conference_mode"
    case youthCamp            = "youth_camp"
    case vbs
    case revivalWeek          = "revival_week"
    case missionTrip          = "mission_trip"
    case emergencyPrayer      = "emergency_prayer"
    case memorial
    case mentalHealthAwareness = "mental_health_awareness"
    case chapelWeek           = "chapel_week"
    case anniversary

    var displayName: String {
        switch self {
        case .celebration:           return "Celebration"
        case .prayerCampaign:        return "Prayer Campaign"
        case .event:                 return "Event"
        case .tradition:             return "Tradition"
        case .communityChallenge:    return "Community Challenge"
        case .worshipNight:          return "Worship Night"
        case .graduationWeek:        return "Graduation Week"
        case .fasting:               return "Fasting"
        case .conferenceMode:        return "Conference Mode"
        case .youthCamp:             return "Youth Camp"
        case .vbs:                   return "VBS"
        case .revivalWeek:           return "Revival Week"
        case .missionTrip:           return "Mission Trip"
        case .emergencyPrayer:       return "Emergency Prayer"
        case .memorial:              return "Memorial"
        case .mentalHealthAwareness: return "Mental Health Awareness"
        case .chapelWeek:            return "Chapel Week"
        case .anniversary:           return "Anniversary"
        }
    }

    var icon: String {
        switch self {
        case .celebration:           return "party.popper.fill"
        case .prayerCampaign:        return "hands.and.sparkles.fill"
        case .event:                 return "calendar.badge.plus"
        case .tradition:             return "star.fill"
        case .communityChallenge:    return "flag.checkered.2.crossed"
        case .worshipNight:          return "music.note.list"
        case .graduationWeek:        return "graduationcap.fill"
        case .fasting:               return "fork.knife.circle.fill"
        case .conferenceMode:        return "mic.fill"
        case .youthCamp:             return "tent.fill"
        case .vbs:                   return "sun.max.fill"
        case .revivalWeek:           return "flame.fill"
        case .missionTrip:           return "airplane.departure"
        case .emergencyPrayer:       return "exclamationmark.bubble.fill"
        case .memorial:              return "heart.fill"
        case .mentalHealthAwareness: return "brain.head.profile"
        case .chapelWeek:            return "building.columns.fill"
        case .anniversary:           return "gift.fill"
        }
    }

    var isGriefSensitive: Bool {
        [.memorial, .mentalHealthAwareness].contains(self)
    }

    var requiresYouthSafety: Bool {
        [.youthCamp, .vbs, .chapelWeek].contains(self)
    }
}

// MARK: - ExperienceScope

enum ExperienceScope: String, Codable, CaseIterable {
    case global
    case regional
    case organization
    case campus
    case group
    case invite

    var displayName: String {
        switch self {
        case .global:       return "Global"
        case .regional:     return "Regional"
        case .organization: return "Organization"
        case .campus:       return "Campus"
        case .group:        return "Group"
        case .invite:       return "Invite Only"
        }
    }
}

// MARK: - ExperienceStatus

enum ContextualExperienceStatus: String, Codable {
    case draft
    case published
    case archived
    case deleted
}

// MARK: - ExperienceModuleType

enum ExperienceModuleType: String, Codable, CaseIterable {
    case prayer
    case discussion
    case event
    case memory
    case tradition
    case scripture
    case worship
    case livestream
    case announcements

    var displayName: String {
        switch self {
        case .prayer:        return "Prayer"
        case .discussion:    return "Discussion"
        case .event:         return "Event"
        case .memory:        return "Memory"
        case .tradition:     return "Tradition"
        case .scripture:     return "Scripture"
        case .worship:       return "Worship"
        case .livestream:    return "Livestream"
        case .announcements: return "Announcements"
        }
    }

    var icon: String {
        switch self {
        case .prayer:        return "hands.and.sparkles.fill"
        case .discussion:    return "bubble.left.and.bubble.right.fill"
        case .event:         return "calendar.badge.plus"
        case .memory:        return "photo.fill"
        case .tradition:     return "star.fill"
        case .scripture:     return "book.closed.fill"
        case .worship:       return "music.note"
        case .livestream:    return "video.fill"
        case .announcements: return "megaphone.fill"
        }
    }
}

// MARK: - ExperienceThemeConfig

struct ExperienceThemeConfig: Codable, Equatable {
    /// One of: #C9A84C, #5B2D8E, #1A6DB5, #0A0A0A, #FFFFFF
    let accentColorHex: String
    /// 0.0–1.0
    let motionIntensity: Double
    /// 0.0–1.0
    let glassOpacity: Double
    /// "light" | "dark" | "adaptive"
    let backgroundStyle: String

    static let defaultTheme = ExperienceThemeConfig(
        accentColorHex: "#C9A84C",
        motionIntensity: 0.5,
        glassOpacity: 0.3,
        backgroundStyle: "adaptive"
    )

    /// Returns a SwiftUI Color from the stored hex string.
    /// Uses the project-wide Color(hex:) initializer defined in Color+Hex.swift.
    var accentColor: Color {
        Color(hex: accentColorHex)
    }

}

// MARK: - ExperienceSafetyConfig

struct ExperienceSafetyConfig: Codable {
    let requiresYouthProtection: Bool
    let moderationStrictness: String
    let allowAnonymousPrayer: Bool
    let requireApprovalToJoin: Bool
    let griefSensitiveMode: Bool

    static let standard = ExperienceSafetyConfig(
        requiresYouthProtection: false,
        moderationStrictness: "standard",
        allowAnonymousPrayer: true,
        requireApprovalToJoin: false,
        griefSensitiveMode: false
    )

    static let youth = ExperienceSafetyConfig(
        requiresYouthProtection: true,
        moderationStrictness: "youth",
        allowAnonymousPrayer: false,
        requireApprovalToJoin: true,
        griefSensitiveMode: false
    )
}

// MARK: - ContextualExperience

struct ContextualExperience: Codable, Identifiable {
    @DocumentID var id: String?
    let organizationId: String
    let organizationType: OrganizationType
    let type: ExperienceType
    let title: String
    let description: String
    let region: String?
    let startDate: Date
    let endDate: Date
    let visibility: ExperienceScope
    var status: ContextualExperienceStatus
    let theme: ExperienceThemeConfig
    let allowedManagerRoles: [OrgMemberRole]
    let enabledModules: [ExperienceModuleType]
    let participantCount: Int
    let createdBy: String
    let createdAt: Date
    let safety: ExperienceSafetyConfig
    let analyticsEnabled: Bool
    let memoriesEnabled: Bool
    let prayerCampaignsEnabled: Bool
    var isKillSwitched: Bool

    var isActive: Bool {
        let now = Date()
        return status == .published && now >= startDate && now <= endDate && !isKillSwitched
    }

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }
}

// MARK: - Experience Modules

struct ExperienceEvent: Codable, Identifiable {
    @DocumentID var id: String?
    let experienceId: String
    let title: String
    let description: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let createdBy: String
    let createdAt: Date
}

struct ExperiencePrayerPrompt: Codable, Identifiable {
    @DocumentID var id: String?
    let experienceId: String
    let prompt: String
    let scriptureReference: String?
    let isAnonymousAllowed: Bool
    let createdBy: String
    let createdAt: Date
}

struct ExperienceDiscussion: Codable, Identifiable {
    @DocumentID var id: String?
    let experienceId: String
    let title: String
    let body: String
    let createdBy: String
    let createdAt: Date
    let replyCount: Int
}

struct ExperienceMemory: Codable, Identifiable {
    @DocumentID var id: String?
    let experienceId: String
    let title: String
    let imageURL: String?
    let note: String
    let scriptureReference: String?
    let createdBy: String
    let createdAt: Date
}

struct ExperienceTradition: Codable, Identifiable {
    @DocumentID var id: String?
    let experienceId: String
    let title: String
    let description: String
    /// "annual" | "monthly" | "weekly"
    let recurrencePattern: String
    let createdBy: String
    let createdAt: Date
}

// MARK: - ExperienceLayer

enum ExperienceLayer: String, Codable {
    case accessibility
    case safetyGrief      = "safety_grief"
    case activeUserEvent  = "active_user_event"
    case organization
    case campus
    case regional
    case global
    case defaultUI        = "default_ui"
}

// MARK: - ResolvedExperience

struct ResolvedExperience: Codable {
    let activeExperienceId: String?
    let sourceLayer: ExperienceLayer
    let themeTokens: ExperienceThemeConfig?
    let allowedModules: [ExperienceModuleType]
    let activeBannerTitle: String?
    let activeBannerSubtitle: String?
    let navigationAction: String?
    let notificationBehavior: String
    let safetyBehavior: String
    let accessibilityAdjustments: [String: Bool]
    let secondaryExperiences: [SecondaryExperience]
    let debugMetadata: [String: String]?

    struct SecondaryExperience: Codable, Identifiable {
        let id: String
        let title: String
        let layer: ExperienceLayer
    }

    static let defaultResolved = ResolvedExperience(
        activeExperienceId: nil,
        sourceLayer: .defaultUI,
        themeTokens: nil,
        allowedModules: ExperienceModuleType.allCases,
        activeBannerTitle: nil,
        activeBannerSubtitle: nil,
        navigationAction: nil,
        notificationBehavior: "normal",
        safetyBehavior: "standard",
        accessibilityAdjustments: [:],
        secondaryExperiences: [],
        debugMetadata: nil
    )
}

// MARK: - ExperienceAnalytics

struct ExperienceAnalytics: Codable {
    let participantCount: Int
    let activeToday: Int
    let prayerCount: Int
    let discussionCount: Int
    let memoryCount: Int
    let joinedLast7Days: Int
}
