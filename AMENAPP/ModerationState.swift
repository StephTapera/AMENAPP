// ModerationState.swift
// AMENAPP
// Shared moderation state for universal content nodes and job listings.

import Foundation

/// General-purpose moderation outcome used by content nodes, jobs, and profiles.
enum ModerationState: String, Codable, CaseIterable, Equatable {
    case pending     = "pending"
    case active      = "active"
    case approved    = "approved"
    case rejected    = "rejected"
    case flagged     = "flagged"
    case underReview = "under_review"
    case warned      = "warned"
    case restricted  = "restricted"
    case suspended   = "suspended"

    var allowsPublicDisplay: Bool {
        self == .active || self == .approved
    }
}

/// Legacy outcome enum used by moderation review APIs.
enum ModerationStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
    case flagged
}
