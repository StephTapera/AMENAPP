// AmenDiscoveryRailModels.swift
// AMEN App — Spiritual OS / Community Discovery
//
// Data contracts for the horizontal discovery rail system.
// Inspired by Apple TV / Netflix "Continue Watching" rails.
//
// Design rules:
//   • No glass on cards — plain surfaceCard background only.
//   • Glass is allowed only on overlaid action controls, never on the cards themselves.
//   • Section titles use AmenTheme.Colors.textPrimary (no decorative gold).
//
// Feature flag: amen_discovery_rails_enabled (AppStorage, default OFF).

import Foundation

// MARK: - DiscoveryRailType

enum DiscoveryRailType: String, CaseIterable {
    case continueJourney      = "continue_journey"
    case recommendedMentors   = "recommended_mentors"
    case activeSpaces         = "active_spaces"
    case churchesNearYou      = "churches_near_you"
    case upcomingEvents       = "upcoming_events"
    case featuredStudies      = "featured_studies"
    case peopleYouShouldMeet  = "people_you_should_meet"
    case prayerCommunities    = "prayer_communities"
    case newCommunities       = "new_communities"
    case churchNotes          = "church_notes"

    var title: String {
        switch self {
        case .continueJourney:     return "Continue Your Journey"
        case .recommendedMentors:  return "Recommended Mentors"
        case .activeSpaces:        return "Active Spaces"
        case .churchesNearYou:     return "Churches Near You"
        case .upcomingEvents:      return "Upcoming Events"
        case .featuredStudies:     return "Featured Studies"
        case .peopleYouShouldMeet: return "People You Should Meet"
        case .prayerCommunities:   return "Prayer Communities"
        case .newCommunities:      return "New Communities"
        case .churchNotes:         return "Shared Church Notes"
        }
    }

    var subtitle: String {
        switch self {
        case .continueJourney:     return "Pick up where you left off"
        case .recommendedMentors:  return "Faith guides for your season"
        case .activeSpaces:        return "Your community is moving"
        case .churchesNearYou:     return "Verified congregations nearby"
        case .upcomingEvents:      return "Coming up in your area"
        case .featuredStudies:     return "Curated studies for this season"
        case .peopleYouShouldMeet: return "From your church family"
        case .prayerCommunities:   return "Spaces focused on intercession"
        case .newCommunities:      return "Recently formed spaces"
        case .churchNotes:         return "Wisdom from the congregation"
        }
    }

    var iconName: String {
        switch self {
        case .continueJourney:     return "arrow.clockwise.circle"
        case .recommendedMentors:  return "person.2.circle"
        case .activeSpaces:        return "bubble.left.and.bubble.right"
        case .churchesNearYou:     return "building.columns"
        case .upcomingEvents:      return "calendar"
        case .featuredStudies:     return "star"
        case .peopleYouShouldMeet: return "person.badge.plus"
        case .prayerCommunities:   return "hands.sparkles"
        case .newCommunities:      return "sparkles"
        case .churchNotes:         return "doc.text"
        }
    }
}

// MARK: - DiscoveryRailItemType

enum DiscoveryRailItemType: String {
    case space
    case mentor
    case church
    case event
    case study
    case person
    case churchNote
    case discussion
}

// MARK: - DiscoveryRailItem

struct DiscoveryRailItem: Identifiable {
    let id: String
    let type: DiscoveryRailItemType
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let badgeText: String?          // "Live", "New", "3 joined today"
    let progressFraction: Double?   // 0.0–1.0; non-nil only for continueJourney items
    let metadata: [String: String]  // flexible extra payload (e.g. churchId, spaceId)
}

// MARK: - DiscoveryRail

struct DiscoveryRail: Identifiable {
    let id: String
    let type: DiscoveryRailType
    var items: [DiscoveryRailItem]
    let loadedAt: Date
}
