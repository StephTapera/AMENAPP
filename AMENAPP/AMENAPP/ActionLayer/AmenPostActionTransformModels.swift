// AmenPostActionTransformModels.swift
// AMEN App — Action Layer: data models for post-to-action transforms

import SwiftUI

// MARK: - AmenPostTransformAction

enum AmenPostTransformAction: String, CaseIterable, Identifiable {
    case reminder = "reminder"
    case event = "event"
    case prayerItem = "prayerItem"
    case task = "task"
    case discussion = "discussion"
    case volunteerOpportunity = "volunteer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reminder:             return "Set Reminder"
        case .event:                return "Create Event"
        case .prayerItem:           return "Add to Prayer"
        case .task:                 return "Create Task"
        case .discussion:           return "Start Discussion"
        case .volunteerOpportunity: return "Volunteer Opportunity"
        }
    }

    var description: String {
        switch self {
        case .reminder:             return "Get notified at the right time"
        case .event:                return "Put this on your calendar"
        case .prayerItem:           return "Pray over this post intentionally"
        case .task:                 return "Turn this into something you act on"
        case .discussion:           return "Open a reasoning thread"
        case .volunteerOpportunity: return "Signal your willingness to serve"
        }
    }

    var icon: String {
        switch self {
        case .reminder:             return "bell.fill"
        case .event:                return "calendar.badge.plus"
        case .prayerItem:           return "hands.sparkles.fill"
        case .task:                 return "checkmark.circle.fill"
        case .discussion:           return "bubble.left.and.bubble.right.fill"
        case .volunteerOpportunity: return "figure.wave"
        }
    }

    var accentColor: Color {
        switch self {
        case .reminder:             return Color(red: 0.36, green: 0.54, blue: 0.95)  // blue-violet
        case .event:                return Color(red: 0.22, green: 0.70, blue: 0.53)  // teal-green
        case .prayerItem:           return Color.accentColor
        case .task:                 return Color(red: 0.28, green: 0.73, blue: 0.36)  // sage green
        case .discussion:           return Color(red: 0.60, green: 0.36, blue: 0.90)  // purple
        case .volunteerOpportunity: return Color(red: 0.93, green: 0.47, blue: 0.22)  // warm orange
        }
    }
}

// MARK: - AmenPostTransformRequest

struct AmenPostTransformRequest {
    let postId: String
    let postText: String
    let authorName: String
    let action: AmenPostTransformAction
    var scheduledDate: Date?
    var customTitle: String?
    var assignedTo: String?
}
