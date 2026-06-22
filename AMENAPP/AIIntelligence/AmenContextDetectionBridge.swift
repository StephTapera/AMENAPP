// AmenContextDetectionBridge.swift
// AMENAPP — Converts AmenTextContextDetectionResult → InsightChipModel[]
//
// Keeps the detection engine (Foundation-only actor) decoupled from the SwiftUI
// glass kit. Call `toInsightChips(from:)` on the main actor after awaiting
// `AmenSmartContextDetectionEngine.shared.detect(in:)`.
//
// InsightChipModel is defined in CommunicationOSGlassKit.swift.
// If a compiler circular-import error surfaces, move InsightChipModel into a
// dedicated AmenInsightChipModel.swift and import that in both files.

import Foundation

struct AmenContextDetectionBridge {

    // MARK: - Primary conversion

    /// Converts all detected signals into an ordered `[InsightChipModel]` array
    /// suitable for passing directly to `AmenGlassInsightBar`.
    ///
    /// Order: links → dates → music → tasks → memories → safety.
    /// Safety chips always appear last so they are never crowded out by routine detections.
    ///
    /// - Parameter result: Value returned by `AmenSmartContextDetectionEngine.detect(in:)`.
    /// - Returns: Flat ordered array of chips. Empty when `result.isEmpty`.
    static func toInsightChips(from result: AmenTextContextDetectionResult) -> [InsightChipModel] {
        var chips: [InsightChipModel] = []

        // Links
        for link in result.links {
            chips.append(InsightChipModel(
                id: UUID(),
                icon: "link",
                label: link.displayText,
                actionKey: "openLink:\(link.url.absoluteString)"
            ))
        }

        // Dates / calendar events
        for date in result.dates {
            chips.append(InsightChipModel(
                id: UUID(),
                icon: "calendar",
                label: date.displayText,
                actionKey: "createReminder:\(date.resolvedDate?.timeIntervalSince1970 ?? 0)"
            ))
        }

        // Music mentions
        for music in result.musicMentions {
            // Truncate long mention labels so they fit in a chip pill
            let shortLabel = music.mention.count > 32
                ? String(music.mention.prefix(29)) + "…"
                : music.mention
            chips.append(InsightChipModel(
                id: UUID(),
                icon: "music.note",
                label: shortLabel,
                actionKey: "attachMusic"
            ))
        }

        // Tasks / action items
        for task in result.tasks {
            chips.append(InsightChipModel(
                id: UUID(),
                icon: "checkmark.circle",
                label: task.phrase.localizedCapitalized,
                actionKey: "createTask:\(task.phrase)"
            ))
        }

        // Memory phrases
        for memory in result.memoryPhrases {
            chips.append(InsightChipModel(
                id: UUID(),
                icon: "bookmark",
                label: memory.phrase.localizedCapitalized,
                actionKey: "saveMemory:\(memory.phrase)"
            ))
        }

        // Safety signals — always last
        for signal in result.safetySignals {
            let icon: String
            switch signal.severity {
            case .info:    icon = "info.circle"
            case .warning: icon = "heart.fill"
            }
            chips.append(InsightChipModel(
                id: UUID(),
                icon: icon,
                label: signal.category.localizedCapitalized,
                actionKey: "safetyResource:\(signal.category)"
            ))
        }

        return chips
    }

    // MARK: - DetectedMessageContext conversion (used by BereanCommunicationHubView)

    static func toMessageContextItems(from result: AmenTextContextDetectionResult) -> [DetectedMessageContext] {
        var items: [DetectedMessageContext] = []
        for link in result.links {
            items.append(DetectedMessageContext(id: UUID(), type: .link, displayText: link.displayText, actionLabel: link.url.absoluteString))
        }
        for date in result.dates {
            items.append(DetectedMessageContext(id: UUID(), type: .date, displayText: date.displayText, actionLabel: "\(date.resolvedDate?.timeIntervalSince1970 ?? 0)"))
        }
        for music in result.musicMentions {
            items.append(DetectedMessageContext(id: UUID(), type: .music, displayText: music.mention, actionLabel: "attachMusic"))
        }
        for task in result.tasks {
            items.append(DetectedMessageContext(id: UUID(), type: .task, displayText: task.phrase.localizedCapitalized, actionLabel: "createTask:\(task.phrase)"))
        }
        for memory in result.memoryPhrases {
            items.append(DetectedMessageContext(id: UUID(), type: .memory, displayText: memory.phrase.localizedCapitalized, actionLabel: "saveMemory:\(memory.phrase)"))
        }
        return items
    }

    // MARK: - Filtered views

    /// Returns only chips of a given actionKey prefix for surfaces that only care
    /// about a subset (e.g. a calendar-aware reply view that only wants date chips).
    ///
    /// - Parameters:
    ///   - result: Full detection result.
    ///   - actionKeyPrefix: e.g. "createReminder", "openLink".
    static func chips(
        from result: AmenTextContextDetectionResult,
        matchingActionKeyPrefix actionKeyPrefix: String
    ) -> [InsightChipModel] {
        toInsightChips(from: result).filter { $0.actionKey.hasPrefix(actionKeyPrefix) }
    }
}
