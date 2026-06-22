//
//  ProfileIdentityModels.swift
//  AMENAPP
//
//  Data models for the extended profile identity layer.
//  These power trust, calling, discovery, and community-fit signals —
//  the dimension of AMEN profiles that goes beyond generic social identity.
//
//  Persisted to: users/{uid} with "identity_" prefixed fields (backward-compatible).
//

import Foundation

// MARK: - User Persona / Role

enum UserPersona: String, Codable, CaseIterable {
    case believer       = "believer"
    case churchLeader   = "churchLeader"
    case pastor         = "pastor"
    case worshipLeader  = "worshipLeader"
    case creator        = "creator"
    case ministry       = "ministry"
    case business       = "business"
    case nonprofit      = "nonprofit"
    case student        = "student"

    var displayName: String {
        switch self {
        case .believer:      return "Believer"
        case .churchLeader:  return "Church Leader"
        case .pastor:        return "Pastor"
        case .worshipLeader: return "Worship Leader"
        case .creator:       return "Creator"
        case .ministry:      return "Ministry"
        case .business:      return "Business"
        case .nonprofit:     return "Nonprofit"
        case .student:       return "Student"
        }
    }

    var icon: String {
        switch self {
        case .believer:      return "person.fill"
        case .churchLeader:  return "building.columns.fill"
        case .pastor:        return "book.closed.fill"
        case .worshipLeader: return "music.note"
        case .creator:       return "pencil.circle.fill"
        case .ministry:      return "hands.sparkles.fill"
        case .business:      return "briefcase.fill"
        case .nonprofit:     return "heart.fill"
        case .student:       return "graduationcap.fill"
        }
    }

    /// Features that become more prominent for this persona.
    /// Used by discovery + Berean prompt routing.
    var emphasizedFeatures: [String] {
        switch self {
        case .pastor, .churchLeader: return ["churchNotes", "sermons", "discipleship"]
        case .worshipLeader:         return ["music", "worship", "churchNotes"]
        case .creator:               return ["studio", "posts", "sermons"]
        case .ministry, .nonprofit:  return ["giving", "fellowship", "events"]
        case .business:              return ["studio", "giving", "discovery"]
        case .student:               return ["berean", "discipleship", "churchNotes"]
        default:                     return ["feed", "berean", "prayer"]
        }
    }
}

// MARK: - Faith Journey Stage

enum FaithJourneyStage: String, Codable, CaseIterable {
    case exploring      = "exploring"
    case newBeliever    = "newBeliever"
    case growing        = "growing"
    case rooted         = "rooted"
    case serving        = "serving"
    case leading        = "leading"

    var displayName: String {
        switch self {
        case .exploring:   return "Exploring faith"
        case .newBeliever: return "New believer"
        case .growing:     return "Growing in faith"
        case .rooted:      return "Rooted in Christ"
        case .serving:     return "Serving others"
        case .leading:     return "Leading a community"
        }
    }

    /// Hint passed to Berean when generating suggested conversation starters.
    var bereanSuggestionHint: String {
        switch self {
        case .exploring:   return "I'm exploring what I believe about Christianity"
        case .newBeliever: return "I recently came to faith and want to understand the basics"
        case .growing:     return "I want to go deeper in my understanding of Scripture"
        case .rooted:      return "I want to explore harder theological questions"
        case .serving:     return "Help me think through how to serve and lead others"
        case .leading:     return "I need wisdom for leading people in their faith"
        }
    }
}

// MARK: - "Open To" Signals

struct OpenToSignal: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let discoveryTag: String    // used in feed / recommendation routing

    static let prayer          = OpenToSignal(id: "prayer",          label: "Prayer partners",       discoveryTag: "prayer")
    static let fellowship      = OpenToSignal(id: "fellowship",      label: "Fellowship",            discoveryTag: "community")
    static let mentorship      = OpenToSignal(id: "mentorship",      label: "Giving mentorship",     discoveryTag: "discipleship")
    static let beingMentored   = OpenToSignal(id: "beingMentored",   label: "Being mentored",        discoveryTag: "discipleship")
    static let serving         = OpenToSignal(id: "serving",         label: "Serving opportunities", discoveryTag: "ministry")
    static let learning        = OpenToSignal(id: "learning",        label: "Learning from others",  discoveryTag: "growth")
    static let collaboration   = OpenToSignal(id: "collaboration",   label: "Ministry collaboration",discoveryTag: "ministry")
    static let speaking        = OpenToSignal(id: "speaking",        label: "Speaking / teaching",   discoveryTag: "creator")

    static let allOptions: [OpenToSignal] = [
        .prayer, .fellowship, .mentorship, .beingMentored,
        .serving, .learning, .collaboration, .speaking
    ]

    static func from(id: String) -> OpenToSignal? {
        allOptions.first { $0.id == id }
    }
}

// MARK: - Denomination / Tradition

enum Denomination: String, Codable, CaseIterable {
    case nonDenominational  = "nonDenominational"
    case baptist            = "baptist"
    case pentecostal        = "pentecostal"
    case charismatic        = "charismatic"
    case methodist          = "methodist"
    case lutheran           = "lutheran"
    case presbyterian       = "presbyterian"
    case catholic           = "catholic"
    case anglican           = "anglican"
    case adventist          = "adventist"
    case reformed           = "reformed"
    case evangelical        = "evangelical"
    case orthodox           = "orthodox"
    case other              = "other"
    case preferNotToSay     = "preferNotToSay"

    var displayName: String {
        switch self {
        case .nonDenominational: return "Non-denominational"
        case .baptist:           return "Baptist"
        case .pentecostal:       return "Pentecostal"
        case .charismatic:       return "Charismatic"
        case .methodist:         return "Methodist"
        case .lutheran:          return "Lutheran"
        case .presbyterian:      return "Presbyterian"
        case .catholic:          return "Catholic"
        case .anglican:          return "Anglican / Episcopal"
        case .adventist:         return "Seventh-day Adventist"
        case .reformed:          return "Reformed"
        case .evangelical:       return "Evangelical"
        case .orthodox:          return "Eastern Orthodox"
        case .other:             return "Other"
        case .preferNotToSay:    return "Prefer not to say"
        }
    }
}

// MARK: - Profile Burden / Prayer Focus
// The third signal category (beyond interests and topics):
// what this person is carrying right now — AMEN-native and prayer-oriented.

struct ProfileBurden: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var text: String           // e.g. "praying for a family member's healing"
    var isPublic: Bool = true  // followers can see; false = private / journal only

    enum CodingKeys: String, CodingKey { case id, text, isPublic }
}

// MARK: - Pinned Spiritual Cards

enum PinnedCardKind: String, Codable, CaseIterable {
    case favoriteVerse      = "favoriteVerse"
    case currentPrayer      = "currentPrayer"
    case testimony          = "testimony"
    case churchHome         = "churchHome"
    case currentStudy       = "currentStudy"
    case discipleshipFocus  = "discipleshipFocus"

    var displayName: String {
        switch self {
        case .favoriteVerse:     return "Favorite verse"
        case .currentPrayer:     return "Current prayer"
        case .testimony:         return "Testimony"
        case .churchHome:        return "Church home"
        case .currentStudy:      return "Current study"
        case .discipleshipFocus: return "Discipleship focus"
        }
    }

    var icon: String {
        switch self {
        case .favoriteVerse:     return "book.fill"
        case .currentPrayer:     return "hands.sparkles"
        case .testimony:         return "star.fill"
        case .churchHome:        return "building.columns"
        case .currentStudy:      return "graduationcap"
        case .discipleshipFocus: return "arrow.up.heart"
        }
    }
}

struct PinnedProfileCard: Codable, Identifiable {
    var id: String = UUID().uuidString
    var kind: PinnedCardKind
    var content: String         // verse text, prayer, testimony excerpt, etc.
    var reference: String?      // "John 3:16", church name, series title, etc.
    var isVisible: Bool = true
    var sortOrder: Int  = 0

    enum CodingKeys: String, CodingKey {
        case id, kind, content, reference, isVisible, sortOrder
    }
}

// MARK: - "Ask Me About" Prompts

struct AskMeAboutPrompt: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var topic: String    // e.g. "prayer", "marriage", "apologetics"

    static let suggestions: [String] = [
        "prayer", "marriage", "parenting", "worship leadership",
        "apologetics", "discipleship", "healing", "missions",
        "youth ministry", "pastoral care", "theology",
        "church planting", "evangelism", "mental health + faith",
        "biblical finances", "leadership", "grief and loss"
    ]

    enum CodingKeys: String, CodingKey { case id, topic }
}

// MARK: - Link Category (for social links)

enum SocialLinkCategory: String, Codable, CaseIterable {
    case personal   = "personal"
    case ministry   = "ministry"
    case sermon     = "sermon"
    case music      = "music"
    case teaching   = "teaching"
    case donation   = "donation"
    case website    = "website"
    case study      = "study"
    case giving     = "giving"
    case testimony  = "testimony"

    var displayName: String {
        switch self {
        case .personal:  return "Personal"
        case .ministry:  return "Ministry"
        case .sermon:    return "Sermons"
        case .music:     return "Music"
        case .teaching:  return "Teaching"
        case .donation:  return "Donation"
        case .website:   return "Website"
        case .study:     return "Bible study"
        case .giving:    return "Giving page"
        case .testimony: return "Testimony"
        }
    }

    var icon: String {
        switch self {
        case .personal:  return "person.fill"
        case .ministry:  return "hands.sparkles.fill"
        case .sermon:    return "mic.fill"
        case .music:     return "music.note"
        case .teaching:  return "book.fill"
        case .donation:  return "gift.fill"
        case .website:   return "globe"
        case .study:     return "text.book.closed.fill"
        case .giving:    return "heart.fill"
        case .testimony: return "star.fill"
        }
    }
}

// MARK: - Field-level Privacy Settings

struct ProfilePrivacySettings: Codable {
    var bioVisibility:         VisibilityLevel = .publicVisible
    var websiteVisibility:     VisibilityLevel = .publicVisible
    var socialLinksVisibility: VisibilityLevel = .publicVisible
    var topicsVisibility:      VisibilityLevel = .publicVisible
    var churchVisibility:      VisibilityLevel = .followersOnly
    var interestsVisibility:   VisibilityLevel = .publicVisible
    var locationVisibility:    VisibilityLevel = .followersOnly
    var denomVisibility:       VisibilityLevel = .followersOnly
    var faithStageVisibility:  VisibilityLevel = .followersOnly
    var openToVisibility:      VisibilityLevel = .followersOnly
    var burdensVisibility:     VisibilityLevel = .followersOnly

    static let `default` = ProfilePrivacySettings()
}

// MARK: - Extended Profile Identity

/// The full identity payload for users/{uid}.
/// Fields are written with "identity_" prefix to avoid collisions with
/// existing user document fields.
struct UserProfileIdentity: Codable {
    var persona:           UserPersona?        = nil
    var cityRegion:        String?             = nil  // coarse, user-controlled
    var faithJourneyStage: FaithJourneyStage?  = nil
    var denomination:      Denomination?       = nil
    var openToSignalIds:   [String]            = []   // OpenToSignal.id values
    var burdens:           [ProfileBurden]     = []
    var pinnedCards:       [PinnedProfileCard] = []
    var askMeAbout:        [AskMeAboutPrompt]  = []
    var privacy:           ProfilePrivacySettings = .default

    /// Convenience: resolved OpenToSignal objects from stored ids.
    var openToSignals: [OpenToSignal] {
        openToSignalIds.compactMap { OpenToSignal.from(id: $0) }
    }

    /// True when at least one AMEN-native identity signal is present.
    var hasAnyIdentitySignal: Bool {
        persona != nil
        || faithJourneyStage != nil
        || denomination != nil
        || !openToSignalIds.isEmpty
        || !burdens.isEmpty
        || !pinnedCards.isEmpty
        || !askMeAbout.isEmpty
        || cityRegion != nil
    }
}

extension UserProfileIdentity {
    var churchAffiliationName: String? { nil }
    var churchAffiliationId: String? { nil }
}
