// ModerationState.swift
// AMENAPP
// Shared moderation state for universal content nodes.

import Foundation

enum ModerationStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
    case flagged
}

struct ModerationState: Codable, Equatable {
    var status: ModerationStatus
    var reason: String?
    var reviewedBy: String?
    var reviewedAt: Date?
    var queuedAt: Date?
    var notes: String?

    var allowsPublicDisplay: Bool {
        status == .approved
    }

    static let pending = ModerationState(status: .pending)
}
