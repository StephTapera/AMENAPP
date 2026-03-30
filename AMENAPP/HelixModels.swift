// HelixModels.swift
// AMENAPP
//
// All Codable Firestore models for the Helix workspace automation system.

import SwiftUI
import FirebaseFirestore

// MARK: - HelixNodeType

enum HelixNodeType: String, Codable, CaseIterable {
    case person
    case team
    case project
    case goal
    case resource

    var label: String {
        switch self {
        case .person:   return "Person"
        case .team:     return "Team"
        case .project:  return "Project"
        case .goal:     return "Goal"
        case .resource: return "Resource"
        }
    }

    var icon: String {
        switch self {
        case .person:   return "person.circle.fill"
        case .team:     return "person.3.fill"
        case .project:  return "folder.fill"
        case .goal:     return "target"
        case .resource: return "book.closed.fill"
        }
    }

    var color: Color {
        switch self {
        case .person:   return Color(hex: "6B48FF")
        case .team:     return Color(hex: "0EA5E9")
        case .project:  return Color(hex: "F59E0B")
        case .goal:     return Color(hex: "10B981")
        case .resource: return Color(hex: "EC4899")
        }
    }
}

// MARK: - HelixHealth

enum HelixHealth: String, Codable, CaseIterable {
    case onTrack
    case atRisk
    case blocked
    case complete

    var label: String {
        switch self {
        case .onTrack:  return "On Track"
        case .atRisk:   return "At Risk"
        case .blocked:  return "Blocked"
        case .complete: return "Complete"
        }
    }

    var colorHex: String {
        switch self {
        case .onTrack:  return "10B981"
        case .atRisk:   return "F59E0B"
        case .blocked:  return "EF4444"
        case .complete: return "6B48FF"
        }
    }

    var color: Color { Color(hex: colorHex) }

    var icon: String {
        switch self {
        case .onTrack:  return "checkmark.circle.fill"
        case .atRisk:   return "exclamationmark.triangle.fill"
        case .blocked:  return "xmark.octagon.fill"
        case .complete: return "star.circle.fill"
        }
    }
}

// MARK: - HelixNode

struct HelixNode: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var workspaceId: String
    var type: HelixNodeType
    var label: String
    var description: String?
    var ownerId: String?
    var connectedNodeIds: [String]
    var health: HelixHealth
    var createdAt: Date?

    init(
        workspaceId: String,
        type: HelixNodeType = .project,
        label: String,
        description: String? = nil,
        ownerId: String? = nil,
        connectedNodeIds: [String] = [],
        health: HelixHealth = .onTrack,
        createdAt: Date? = Date()
    ) {
        self.workspaceId = workspaceId
        self.type = type
        self.label = label
        self.description = description
        self.ownerId = ownerId
        self.connectedNodeIds = connectedNodeIds
        self.health = health
        self.createdAt = createdAt
    }
}

// MARK: - WorkflowStepType

enum WorkflowStepType: String, Codable, CaseIterable {
    case sendCheckIn
    case notify
    case createPost
    case aiSummary
    case scheduleEvent
    case sendDM
    case waitDelay

    var label: String {
        switch self {
        case .sendCheckIn:   return "Send Check-In"
        case .notify:        return "Notify"
        case .createPost:    return "Create Post"
        case .aiSummary:     return "AI Summary"
        case .scheduleEvent: return "Schedule Event"
        case .sendDM:        return "Send DM"
        case .waitDelay:     return "Wait / Delay"
        }
    }

    var icon: String {
        switch self {
        case .sendCheckIn:   return "checkmark.message.fill"
        case .notify:        return "bell.fill"
        case .createPost:    return "square.and.pencil"
        case .aiSummary:     return "sparkles"
        case .scheduleEvent: return "calendar.badge.plus"
        case .sendDM:        return "paperplane.fill"
        case .waitDelay:     return "clock.fill"
        }
    }
}

// MARK: - WorkflowStep

struct WorkflowStep: Codable, Identifiable {
    var id: String
    var order: Int
    var type: WorkflowStepType
    var config: [String: String]
    var delayMinutes: Int?

    init(
        id: String = UUID().uuidString,
        order: Int,
        type: WorkflowStepType,
        config: [String: String] = [:],
        delayMinutes: Int? = nil
    ) {
        self.id = id
        self.order = order
        self.type = type
        self.config = config
        self.delayMinutes = delayMinutes
    }
}

// MARK: - WorkflowTrigger

enum WorkflowTrigger: String, Codable, CaseIterable {
    case scheduled
    case event
    case manual
    case aiDetected

    var label: String {
        switch self {
        case .scheduled:  return "Scheduled"
        case .event:      return "On Event"
        case .manual:     return "Manual"
        case .aiDetected: return "AI Detected"
        }
    }

    var icon: String {
        switch self {
        case .scheduled:  return "calendar.clock"
        case .event:      return "bolt.fill"
        case .manual:     return "hand.tap.fill"
        case .aiDetected: return "brain.head.profile"
        }
    }
}

// MARK: - WorkflowTemplate

struct WorkflowTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let triggerType: WorkflowTrigger
    let steps: [WorkflowStep]

    static let all: [WorkflowTemplate] = [
        WorkflowTemplate(
            id: "weekly_checkin",
            name: "Weekly Spiritual Health Check-in",
            description: "Automatically sends a reflective check-in to your circle every week to encourage spiritual growth.",
            triggerType: .scheduled,
            steps: [
                WorkflowStep(order: 0, type: .sendCheckIn, config: ["message": "How is your spiritual walk this week?", "style": "Gentle"]),
                WorkflowStep(order: 1, type: .waitDelay, config: [:], delayMinutes: 1440),
                WorkflowStep(order: 2, type: .aiSummary, config: ["prompt": "Summarize the group's spiritual health responses"]),
                WorkflowStep(order: 3, type: .notify, config: ["message": "Your weekly spiritual summary is ready"])
            ]
        ),
        WorkflowTemplate(
            id: "new_member_welcome",
            name: "New Member Welcome",
            description: "Greets every new member with a personalised welcome message and helpful resources.",
            triggerType: .event,
            steps: [
                WorkflowStep(order: 0, type: .sendDM, config: ["message": "Welcome to our community! We're so glad you're here. 🙏"]),
                WorkflowStep(order: 1, type: .waitDelay, config: [:], delayMinutes: 60),
                WorkflowStep(order: 2, type: .notify, config: ["message": "New member joined — check them in!"]),
                WorkflowStep(order: 3, type: .createPost, config: ["template": "new_member_shoutout"])
            ]
        ),
        WorkflowTemplate(
            id: "inactivity_nudge",
            name: "Inactivity Nudge",
            description: "Gently reaches out to members who haven't engaged in a while with an encouraging message.",
            triggerType: .aiDetected,
            steps: [
                WorkflowStep(order: 0, type: .aiSummary, config: ["prompt": "Identify inactive members in the last 14 days"]),
                WorkflowStep(order: 1, type: .sendDM, config: ["message": "Hey, we've been thinking about you. Hope you're well! 💙"]),
                WorkflowStep(order: 2, type: .notify, config: ["message": "Inactivity nudge sent"])
            ]
        ),
        WorkflowTemplate(
            id: "meeting_followup",
            name: "Meeting Follow-up",
            description: "After a scheduled meeting, auto-generates a summary and action items and posts them to the group.",
            triggerType: .event,
            steps: [
                WorkflowStep(order: 0, type: .waitDelay, config: [:], delayMinutes: 15),
                WorkflowStep(order: 1, type: .aiSummary, config: ["prompt": "Generate meeting summary and action items"]),
                WorkflowStep(order: 2, type: .createPost, config: ["template": "meeting_summary"]),
                WorkflowStep(order: 3, type: .notify, config: ["message": "Meeting summary posted"])
            ]
        ),
        WorkflowTemplate(
            id: "goal_progress",
            name: "Goal Progress Check",
            description: "Periodically checks in on goal nodes and surfaces progress updates to the team.",
            triggerType: .scheduled,
            steps: [
                WorkflowStep(order: 0, type: .aiSummary, config: ["prompt": "Analyse goal node health and progress"]),
                WorkflowStep(order: 1, type: .notify, config: ["message": "Goal progress report ready"]),
                WorkflowStep(order: 2, type: .createPost, config: ["template": "goal_update"])
            ]
        )
    ]
}

// MARK: - HelixWorkflow

struct HelixWorkflow: Codable, Identifiable {
    @DocumentID var id: String?
    var workspaceId: String
    var name: String
    var description: String
    var triggerType: WorkflowTrigger
    var triggerConfig: [String: String]
    var steps: [WorkflowStep]
    var isActive: Bool
    var lastRunAt: Date?
    var nextRunAt: Date?
    var runCount: Int
    var createdBy: String
    var createdAt: Date?

    init(
        workspaceId: String,
        name: String,
        description: String,
        triggerType: WorkflowTrigger = .manual,
        triggerConfig: [String: String] = [:],
        steps: [WorkflowStep] = [],
        isActive: Bool = false,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        runCount: Int = 0,
        createdBy: String = "",
        createdAt: Date? = Date()
    ) {
        self.workspaceId = workspaceId
        self.name = name
        self.description = description
        self.triggerType = triggerType
        self.triggerConfig = triggerConfig
        self.steps = steps
        self.isActive = isActive
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.runCount = runCount
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

// MARK: - StepStatus

enum StepStatus: String, Codable {
    case pending
    case running
    case completed
    case failed

    var icon: String {
        switch self {
        case .pending:   return "clock"
        case .running:   return "arrow.trianglehead.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return .gray
        case .running:   return Color(hex: "F59E0B")
        case .completed: return Color(hex: "10B981")
        case .failed:    return Color(hex: "EF4444")
        }
    }
}

// MARK: - StepResult

struct StepResult: Codable, Identifiable {
    var id: String
    var stepId: String
    var status: StepStatus
    var resultSummary: String?
    var errorMessage: String?
    var completedAt: Date?
}

// MARK: - RunStatus

enum RunStatus: String, Codable {
    case running
    case completed
    case failed

    var color: Color {
        switch self {
        case .running:   return Color(hex: "F59E0B")
        case .completed: return Color(hex: "10B981")
        case .failed:    return Color(hex: "EF4444")
        }
    }

    var label: String {
        switch self {
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }
}

// MARK: - HelixWorkflowRun

struct HelixWorkflowRun: Codable, Identifiable {
    @DocumentID var id: String?
    var workflowId: String
    var workspaceId: String
    var status: RunStatus
    var stepResults: [StepResult]
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
}

// MARK: - HelixEdge

struct HelixEdge: Identifiable {
    var id: String { "\(sourceId)->\(targetId)" }
    var sourceId: String
    var targetId: String
    var label: String?
}
