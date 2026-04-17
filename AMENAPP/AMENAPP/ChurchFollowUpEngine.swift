// ChurchFollowUpEngine.swift
// AMENAPP
//
// Orchestrates the 3-step post-visit follow-up growth loop:
//   Step 1 — Same day:    "How did it go?" → appends post-visit reflection note
//   Step 2 — Next day:    "What stayed with you?" → appends to same note thread
//   Step 3 — Day 3:       "Do you want to return or connect?" → return decision note
//
// All prompts are opt-in (triggered only after the user marks attended or reflects).
// Prompts are surfaced as in-app banners AND scheduled local notifications.
// Each step links back into ChurchReflectionService and ChurchInteractionService.

import Foundation
import FirebaseAuth

// MARK: - Follow-Up Step

enum ChurchFollowUpStep: Int, Codable, CaseIterable {
    case sameDay   = 0
    case nextDay   = 1
    case dayThree  = 2

    var daysOffset: Int {
        switch self {
        case .sameDay:  return 0
        case .nextDay:  return 1
        case .dayThree: return 3
        }
    }

    var promptTitle: String {
        switch self {
        case .sameDay:  return "How did it go?"
        case .nextDay:  return "What stayed with you?"
        case .dayThree: return "Ready to go back?"
        }
    }

    var promptBody: String {
        switch self {
        case .sameDay:
            return "Take a few minutes to reflect on your visit while it's fresh."
        case .nextDay:
            return "What from Sunday's service is still on your heart?"
        case .dayThree:
            return "Would you like to return, connect with someone, or share your experience?"
        }
    }

    var noteTemplate: ChurchVisitNoteTemplate {
        switch self {
        case .sameDay, .nextDay: return .postVisitReflection
        case .dayThree:          return .returnDecision
        }
    }

    var icon: String {
        switch self {
        case .sameDay:  return "heart.text.clipboard"
        case .nextDay:  return "bubble.left"
        case .dayThree: return "arrow.uturn.backward.circle"
        }
    }
}

// MARK: - Follow-Up State (per church)

struct ChurchFollowUpState: Codable, Equatable {
    let churchId: String
    let churchName: String
    var completedSteps: Set<Int>       // Step rawValues that have been dismissed/completed
    var attendedAt: Date

    var nextPendingStep: ChurchFollowUpStep? {
        for step in ChurchFollowUpStep.allCases {
            guard !completedSteps.contains(step.rawValue) else { continue }
            let dueDate = Calendar.current.date(
                byAdding: .day, value: step.daysOffset, to: attendedAt
            ) ?? attendedAt
            // Only surface if the due date has passed (or is today)
            if dueDate <= Date().addingTimeInterval(3600) {
                return step
            }
        }
        return nil
    }

    var isComplete: Bool {
        completedSteps.count == ChurchFollowUpStep.allCases.count
    }
}

// MARK: - ChurchFollowUpEngine

@MainActor
final class ChurchFollowUpEngine: ObservableObject {

    static let shared = ChurchFollowUpEngine()

    // MARK: - Published State

    /// Active follow-up prompt to surface in-app (nil if none pending)
    @Published private(set) var activePendingPrompt: (state: ChurchFollowUpState, step: ChurchFollowUpStep)?

    // MARK: - Private

    private var followUpStates: [String: ChurchFollowUpState] = [:]  // keyed by churchId

    private init() {}

    // MARK: - Register Attendance

    /// Call when the user marks a church as attended.
    /// Begins the follow-up sequence and schedules local notifications.
    func registerAttendance(for church: Church) {
        let state = ChurchFollowUpState(
            churchId: church.id.uuidString,
            churchName: church.name,
            completedSteps: [],
            attendedAt: Date()
        )
        followUpStates[church.id.uuidString] = state

        // Schedule same-day reflect prompt (3h after now)
        ChurchVisitReminderService.shared.scheduleReflectPrompt(
            for: church,
            serviceDate: Date(),
            durationMinutes: 0      // attended now — offset from current time
        )

        // Schedule next-day follow-up at 9AM
        ChurchVisitReminderService.shared.scheduleFollowUpReminder(for: church)

        refreshActivePendingPrompt()
    }

    // MARK: - Check for Pending Prompts

    /// Call from view on appear to check if any follow-up is ready to surface.
    func checkPendingPrompts() {
        refreshActivePendingPrompt()
    }

    // MARK: - Complete Step

    /// Marks a follow-up step as completed (user tapped the prompt).
    /// Optionally creates a note if template is specified.
    @discardableResult
    func completeStep(
        _ step: ChurchFollowUpStep,
        for churchId: String,
        createNote: Bool = true
    ) async -> ChurchNote? {
        guard var state = followUpStates[churchId] else { return nil }
        state.completedSteps.insert(step.rawValue)
        followUpStates[churchId] = state

        var createdNote: ChurchNote? = nil

        if createNote {
            createdNote = try? await ChurchReflectionService.shared.createNoteFromTemplate(
                template: step.noteTemplate,
                churchId: churchId,
                churchName: state.churchName
            )
        }

        // Advance interaction phase if appropriate
        if step == .dayThree {
            ChurchInteractionService.shared.transitionToReflected(
                churchId: churchId,
                reflectionId: createdNote?.id
            )
        }

        refreshActivePendingPrompt()
        return createdNote
    }

    // MARK: - Dismiss Step (skip without creating note)

    func dismissStep(_ step: ChurchFollowUpStep, for churchId: String) {
        guard var state = followUpStates[churchId] else { return }
        state.completedSteps.insert(step.rawValue)
        followUpStates[churchId] = state
        refreshActivePendingPrompt()
    }

    // MARK: - Private

    private func refreshActivePendingPrompt() {
        for (_, state) in followUpStates {
            if let step = state.nextPendingStep {
                activePendingPrompt = (state, step)
                return
            }
        }
        activePendingPrompt = nil
    }
}
