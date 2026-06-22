// AmenHubModels.swift
// AMEN Hub — Unified Inbox Models
//
// Defines the data model for the Hub (Unified Inbox) feature.
// Firestore path: notifications/{uid}/items

import Foundation

// MARK: - AmenHubItemType

enum AmenHubItemType: String, Codable, CaseIterable {
    case message            = "message"
    case prayerRequest      = "prayerRequest"
    case churchMention      = "churchMention"
    case bereanResponse     = "bereanResponse"
    case volunteerRequest   = "volunteerRequest"
    case eventInvitation    = "eventInvitation"
    case mentorReply        = "mentorReply"
    case spaceActivity      = "spaceActivity"
}

extension AmenHubItemType {
    var label: String {
        switch self {
        case .message:          return "Messages"
        case .prayerRequest:    return "Prayer"
        case .churchMention:    return "Mentions"
        case .bereanResponse:   return "Berean"
        case .volunteerRequest: return "Volunteer"
        case .eventInvitation:  return "Events"
        case .mentorReply:      return "Mentor"
        case .spaceActivity:    return "Spaces"
        }
    }
}

// MARK: - AmenHubItem

struct AmenHubItem: Identifiable {
    let id: String
    let type: AmenHubItemType
    let title: String
    let body: String
    let senderName: String
    let senderPhotoURL: String?
    let timestamp: Date
    var isRead: Bool
    let deepLink: String
}

// MARK: - HubFilter
// Used by AmenHubRealtimeViewModel.filteredItems(for:)

enum HubFilter: Equatable {
    case all
    case type(AmenHubItemType)

    func matches(_ type: AmenHubItemType) -> Bool {
        switch self {
        case .all:          return true
        case .type(let t):  return t == type
        }
    }
}
