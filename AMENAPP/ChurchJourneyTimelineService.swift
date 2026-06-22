// ChurchJourneyTimelineService.swift
// AMENAPP
//
// Builds a milestone timeline from a ChurchInteraction's phase transitions
// and linked resources (notes, reflections, visit plans).

import Foundation

// MARK: - ChurchJourneyMilestone

struct ChurchJourneyMilestone: Identifiable {
    let id: String
    let phase: ChurchInteractionPhase
    let date: Date
    let description: String
    let icon: String
    let linkedId: String?       // noteId, visitPlanId, reflectionId

    /// Accent color name for the milestone
    var accentColorName: String {
        switch phase {
        case .discovered, .saved:      return "blue"
        case .interested, .planning:   return "purple"
        case .ready:                   return "orange"
        case .attended:                return "green"
        case .reflected:               return "gold"
        case .returned:                return "teal"
        }
    }
}

// MARK: - ChurchJourneyTimelineService

@MainActor
final class ChurchJourneyTimelineService {

    static let shared = ChurchJourneyTimelineService()

    private init() {}

    // MARK: - Build Timeline

    /// Converts a ChurchInteraction into an ordered list of milestones.
    func buildTimeline(from interaction: ChurchInteraction) -> [ChurchJourneyMilestone] {
        var milestones: [ChurchJourneyMilestone] = []

        let phaseData: [(ChurchInteractionPhase, Date?, String, String?)] = [
            (.discovered, interaction.discoveredAt,  "Discovered \(interaction.churchName)", nil),
            (.saved,      interaction.savedAt,       "Saved to your list",                   nil),
            (.interested, interaction.interestedAt,  "Explored details",                     nil),
            (.planning,   interaction.planningAt,    "Started planning a visit",              interaction.visitPlanId),
            (.ready,      interaction.readyAt,       "Ready to visit",                       nil),
            (.attended,   interaction.attendedAt,    "Attended a service",                    interaction.visitSessionId),
            (.reflected,  interaction.reflectedAt,   "Wrote a reflection",                   interaction.reflectionId),
            (.returned,   interaction.returnedAt,    "Returned for another visit",            nil),
        ]

        for (phase, date, description, linkedId) in phaseData {
            guard let date else { continue }
            milestones.append(ChurchJourneyMilestone(
                id: "\(interaction.churchId)_\(phase.rawValue)",
                phase: phase,
                date: date,
                description: description,
                icon: phase.icon,
                linkedId: linkedId
            ))
        }

        // Add note milestones
        for noteId in interaction.noteIds {
            milestones.append(ChurchJourneyMilestone(
                id: "note_\(noteId)",
                phase: .reflected,
                date: interaction.reflectedAt ?? interaction.updatedAt,
                description: "Created a church note",
                icon: "square.and.pencil",
                linkedId: noteId
            ))
        }

        // Sort chronologically
        return milestones.sorted { $0.date < $1.date }
    }

    // MARK: - Full Timeline

    /// Fetches the interaction and builds the full timeline for a church.
    func getFullTimeline(churchId: String) -> [ChurchJourneyMilestone] {
        guard let interaction = ChurchInteractionService.shared.interaction(for: churchId) else {
            return []
        }
        return buildTimeline(from: interaction)
    }
}
