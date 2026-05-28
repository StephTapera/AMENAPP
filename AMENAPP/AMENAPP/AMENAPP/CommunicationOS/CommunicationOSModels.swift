// CommunicationOSModels.swift
// AMENAPP
//
// Shared model types for the Communication OS intelligence layer.

import Foundation

// MARK: - Decision

enum DecisionStatus: String, Codable {
    case proposed, confirmed, challenged, outdated
}

struct ThreadDecision: Identifiable {
    let id: String
    let summary: String
    let sourceMessageSnippet: String?
    var status: DecisionStatus
    let extractedAt: Date

    init?(from dict: [String: Any]) {
        guard let summary = dict["summary"] as? String, !summary.isEmpty else { return nil }
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.summary = summary
        self.sourceMessageSnippet = dict["sourceSnippet"] as? String
        self.status = DecisionStatus(rawValue: dict["status"] as? String ?? "") ?? .proposed
        self.extractedAt = Date()
    }
}

// MARK: - Question

struct ThreadQuestion: Identifiable {
    let id: String
    let text: String
    let askedBy: String?
    let sourceMessageSnippet: String?
    var isResolved: Bool
    let detectedAt: Date

    init?(from dict: [String: Any]) {
        guard let text = dict["question"] as? String, !text.isEmpty else { return nil }
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.text = text
        self.askedBy = dict["askedBy"] as? String
        self.sourceMessageSnippet = dict["sourceSnippet"] as? String
        self.isResolved = (dict["isResolved"] as? Bool) ?? false
        self.detectedAt = Date()
    }
}

// MARK: - Action

enum ActionStatus: String, Codable {
    case suggested, accepted, done, dismissed
}

struct ThreadAction: Identifiable {
    let id: String
    let description: String
    let assignedTo: String?
    let sourceMessageSnippet: String?
    var status: ActionStatus
    let extractedAt: Date

    init?(from dict: [String: Any]) {
        guard let desc = dict["action"] as? String, !desc.isEmpty else { return nil }
        self.id = dict["id"] as? String ?? UUID().uuidString
        self.description = desc
        self.assignedTo = dict["assignedTo"] as? String
        self.sourceMessageSnippet = dict["sourceSnippet"] as? String
        self.status = ActionStatus(rawValue: dict["status"] as? String ?? "") ?? .suggested
        self.extractedAt = Date()
    }
}

// MARK: - Group Pulse

struct GroupPulseData {
    let activeTopic: String?
    let openQuestions: [String]
    let pendingDecisions: [String]
    let suggestedNextAction: String?
    let generatedAt: Date

    init(from dict: [String: Any]) {
        activeTopic = dict["activeTopic"] as? String
        openQuestions = dict["openQuestions"] as? [String] ?? []
        pendingDecisions = dict["pendingDecisions"] as? [String] ?? []
        suggestedNextAction = dict["suggestedNextAction"] as? String
        generatedAt = Date()
    }

    static let empty = GroupPulseData(from: [:])
}

// MARK: - Smart Presence

enum SmartPresenceStatus: String, Codable, CaseIterable {
    case activeNow       = "Active now"
    case recentlyActive  = "Recently active"
    case focusMode       = "Focus mode"
    case quietMode       = "Quiet mode"
    case mayReplyLater   = "May reply later"
    case mobile          = "On mobile"

    var icon: String {
        switch self {
        case .activeNow:      return "circle.fill"
        case .recentlyActive: return "circle.fill"
        case .focusMode:      return "moon.fill"
        case .quietMode:      return "bell.slash.fill"
        case .mayReplyLater:  return "clock.fill"
        case .mobile:         return "iphone"
        }
    }

    var isOnline: Bool { self == .activeNow }
}
