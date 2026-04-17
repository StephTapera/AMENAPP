//
//  ActionThreadModels.swift
//  AMENAPP
//
//  Domain models for Action Threads — private, permissioned support workflows
//  attached to posts. A post remains a post; an Action Thread is an enhancement
//  layer that converts passive content into care-centered action.
//
//  Firestore path: posts/{postId}/actionThreads/{threadId}
//

import Foundation

// MARK: - Action Thread Type

/// The kind of support workflow this thread represents.
enum ActionThreadType: String, Codable, CaseIterable {
    case prayerCircle       = "prayer_circle"
    case checkIn            = "check_in"
    case mealSupport        = "meal_support"
    case scriptureSupport   = "scripture_support"
    case encouragementFlow  = "encouragement_flow"
    case careFollowup       = "care_followup"
    case crisisResource     = "crisis_support_resource_prompt"
    case customSupport      = "custom_support_flow"

    /// Human-readable label for internal logging / future UI.
    var displayName: String {
        switch self {
        case .prayerCircle:      return "Prayer Circle"
        case .checkIn:           return "Check-In"
        case .mealSupport:       return "Meal Support"
        case .scriptureSupport:  return "Scripture Support"
        case .encouragementFlow: return "Encouragement"
        case .careFollowup:      return "Care Follow-Up"
        case .crisisResource:    return "Crisis Resources"
        case .customSupport:     return "Support Flow"
        }
    }

    /// Whether this thread type should be treated with elevated sensitivity.
    var isSensitive: Bool {
        switch self {
        case .crisisResource, .careFollowup: return true
        default: return false
        }
    }
}

// MARK: - Visibility

/// Controls who can see the Action Thread's existence and participate.
enum ActionThreadVisibility: String, Codable {
    case ownerOnly      = "owner_only"       // Only the thread creator
    case participants   = "participants"      // Creator + explicitly added participants
    case postFollowers  = "post_followers"    // Anyone who follows the post author
    case mutuals        = "mutuals"           // Mutual followers of the post author
}

// MARK: - Execution State

/// Lifecycle of an individual action step within a thread.
enum ActionStepState: String, Codable {
    case pending      = "pending"
    case inProgress   = "in_progress"
    case completed    = "completed"
    case skipped      = "skipped"
    case expired      = "expired"
    case cancelled    = "cancelled"
}

/// Overall thread lifecycle.
enum ActionThreadState: String, Codable {
    case suggested    = "suggested"    // AI suggested, not yet approved by user
    case draft        = "draft"        // User started but hasn't activated
    case active       = "active"       // Running
    case paused       = "paused"       // User paused
    case completed    = "completed"    // All steps done or user marked complete
    case archived     = "archived"     // Soft-deleted / hidden
    case expired      = "expired"      // TTL reached without completion
}

// MARK: - Care Sensitivity

/// How carefully the system should treat content in this thread.
enum CareSensitivityLevel: String, Codable {
    case standard   = "standard"     // Normal interactions
    case elevated   = "elevated"     // Emotionally sensitive topic
    case high       = "high"         // Potential crisis / grief / trauma
    case critical   = "critical"     // Active crisis — surface resources immediately
}

// MARK: - Support Intent

/// What the user (or system) intends this thread to accomplish.
struct SupportIntent: Codable, Equatable {
    let category: ActionThreadType
    let sensitivityLevel: CareSensitivityLevel
    let description: String?              // Optional user-provided description
    let detectedSignals: [String]?        // Signals that triggered the suggestion
    let confidence: Double                // 0.0–1.0 confidence of detection
    let sourcePostId: String?             // The post that triggered this intent
}

// MARK: - Participant

/// A user participating in an Action Thread with a specific role.
struct ActionThreadParticipant: Codable, Identifiable, Equatable {
    let id: String                        // Same as userId
    let userId: String
    let displayName: String
    let username: String?
    let profileImageURL: String?
    let role: ParticipantRole
    let joinedAt: Date
    var lastActiveAt: Date?
    var status: ParticipantStatus

    enum ParticipantRole: String, Codable {
        case owner       = "owner"        // Created the thread
        case coordinator = "coordinator"  // Can manage steps/participants
        case supporter   = "supporter"    // Active participant
        case observer    = "observer"     // Can see but not act
    }

    enum ParticipantStatus: String, Codable {
        case invited   = "invited"
        case active    = "active"
        case declined  = "declined"
        case removed   = "removed"
        case left      = "left"
    }
}

// MARK: - Action Step

/// A single actionable item within an Action Thread.
struct ActionStep: Codable, Identifiable, Equatable {
    let id: String
    let threadId: String
    let title: String
    let description: String?
    let type: StepType
    var state: ActionStepState
    let createdAt: Date
    var updatedAt: Date?
    var completedAt: Date?
    var completedBy: String?              // userId who completed it
    var assignedTo: String?               // userId responsible (optional)
    let scheduledFor: Date?               // When this step should happen
    let expiresAt: Date?                  // Auto-expire if not completed
    var sortOrder: Int

    enum StepType: String, Codable {
        case prayer       = "prayer"          // Pray for someone
        case checkIn      = "check_in"        // Follow-up check-in
        case mealDelivery = "meal_delivery"   // Coordinate meal
        case scripture    = "scripture"        // Share scripture
        case encouragement = "encouragement"  // Send encouragement
        case reminder     = "reminder"        // Scheduled reminder
        case resource     = "resource"        // Share a resource link
        case custom       = "custom"          // User-defined step
    }
}

// MARK: - Action Suggestion

/// A system-generated suggestion for creating an Action Thread, presented privately
/// to the post author. Never auto-executed.
struct ActionSuggestion: Codable, Identifiable, Equatable {
    let id: String
    let postId: String
    let suggestedThreadType: ActionThreadType
    let intent: SupportIntent
    let suggestedSteps: [SuggestedStep]
    let createdAt: Date
    let expiresAt: Date                   // Suggestion expires and is cleaned up
    var status: SuggestionStatus
    let cooldownKey: String               // Dedup key: "{userId}_{postId}_{threadType}"

    enum SuggestionStatus: String, Codable {
        case pending    = "pending"       // Waiting for user to see
        case seen       = "seen"          // User saw but hasn't acted
        case accepted   = "accepted"      // User created a thread from this
        case dismissed  = "dismissed"     // User dismissed
        case expired    = "expired"       // TTL reached
    }

    struct SuggestedStep: Codable, Equatable {
        let title: String
        let type: ActionStep.StepType
        let scheduledOffset: TimeInterval?  // Seconds from thread creation
    }
}

// MARK: - Action Reminder

/// A scheduled follow-up notification tied to an Action Thread.
struct ActionReminder: Codable, Identifiable, Equatable {
    let id: String
    let threadId: String
    let stepId: String?                   // Optional link to specific step
    let recipientUserId: String
    let title: String
    let body: String
    let scheduledAt: Date
    var firedAt: Date?
    var status: ReminderStatus

    enum ReminderStatus: String, Codable {
        case scheduled  = "scheduled"
        case sent       = "sent"
        case cancelled  = "cancelled"
        case failed     = "failed"
    }
}

// MARK: - Permission Set

/// Fine-grained permissions for an Action Thread.
struct ActionThreadPermissionSet: Codable, Equatable {
    let canAddParticipants: Bool
    let canRemoveParticipants: Bool
    let canEditSteps: Bool
    let canCompleteSteps: Bool
    let canArchiveThread: Bool
    let canViewAuditLog: Bool
    let requiresOwnerApproval: Bool       // Steps need owner sign-off

    /// Default permissions for the thread owner.
    static let ownerDefaults = ActionThreadPermissionSet(
        canAddParticipants: true,
        canRemoveParticipants: true,
        canEditSteps: true,
        canCompleteSteps: true,
        canArchiveThread: true,
        canViewAuditLog: true,
        requiresOwnerApproval: false
    )

    /// Default permissions for a supporter participant.
    static let supporterDefaults = ActionThreadPermissionSet(
        canAddParticipants: false,
        canRemoveParticipants: false,
        canEditSteps: false,
        canCompleteSteps: true,
        canArchiveThread: false,
        canViewAuditLog: false,
        requiresOwnerApproval: false
    )

    /// Default permissions for an observer.
    static let observerDefaults = ActionThreadPermissionSet(
        canAddParticipants: false,
        canRemoveParticipants: false,
        canEditSteps: false,
        canCompleteSteps: false,
        canArchiveThread: false,
        canViewAuditLog: false,
        requiresOwnerApproval: false
    )
}

// MARK: - Audit Log Entry

/// Immutable record of a state change within an Action Thread.
struct ActionThreadAuditEntry: Codable, Identifiable, Equatable {
    let id: String
    let threadId: String
    let actorUserId: String
    let action: AuditAction
    let detail: String?                   // Human-readable detail
    let timestamp: Date
    let metadata: [String: String]?       // Arbitrary key-value context

    enum AuditAction: String, Codable {
        case threadCreated      = "thread_created"
        case threadActivated    = "thread_activated"
        case threadPaused       = "thread_paused"
        case threadCompleted    = "thread_completed"
        case threadArchived     = "thread_archived"
        case stepCreated        = "step_created"
        case stepCompleted      = "step_completed"
        case stepSkipped        = "step_skipped"
        case participantAdded   = "participant_added"
        case participantRemoved = "participant_removed"
        case participantLeft    = "participant_left"
        case reminderScheduled  = "reminder_scheduled"
        case reminderSent       = "reminder_sent"
        case permissionChanged  = "permission_changed"
        case suggestionAccepted = "suggestion_accepted"
        case suggestionDismissed = "suggestion_dismissed"
    }
}

// MARK: - Action Thread (Root Entity)

/// The root model for a support workflow attached to a post.
/// Firestore: posts/{postId}/actionThreads/{threadId}
struct ActionThread: Codable, Identifiable, Equatable {
    let id: String
    let postId: String                    // The post this thread is attached to
    let postAuthorId: String              // Denormalized for security rules
    let creatorUserId: String             // Who created this thread
    let type: ActionThreadType
    let visibility: ActionThreadVisibility
    var state: ActionThreadState
    let sensitivityLevel: CareSensitivityLevel
    let title: String?                    // Optional user-provided title
    let description: String?
    let intent: SupportIntent?            // The intent that generated this thread
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    let expiresAt: Date?                  // Auto-archive after this date
    var participantCount: Int
    var completedStepCount: Int
    var totalStepCount: Int

    /// Computed property: whether the thread is still actionable.
    var isActionable: Bool {
        state == .active || state == .paused
    }
}
