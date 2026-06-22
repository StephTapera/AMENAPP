// BereanContextInjector.swift — Features/Intelligence/BereanContext
// Provides a single call-site API for injecting life-graph context into a Berean prompt string.
//
// Usage:
//   let enriched = await BereanContextInjector.enrich(prompt: "Help me understand grief")
//
// Free users: returns the prompt unchanged.
// Premium + graphToBerean: prepends a compact context preamble built from recent signals.

import Foundation

enum BereanContextInjector {

    // MARK: - Public API

    /// Enriches a Berean prompt with contextual signals. Safe to call from any concurrency context.
    /// Returns the original prompt if the feature is off, unaccessible, or packet is unavailable.
    static func enrich(prompt: String) async -> String {
        guard let packet = await BereanContextRAGService.shared.buildPacket(),
              !packet.signals.isEmpty else {
            return prompt
        }

        let preamble = buildPreamble(from: packet)
        return preamble + "\n\n---\n\n" + prompt
    }

    // MARK: - Preamble builder

    private static func buildPreamble(from packet: BereanContextPacket) -> String {
        var lines = [
            "[AMEN Life Context — user granted permission to use this. Use it to personalize your response.]"
        ]
        for signal in packet.signals {
            let age = ageLabel(for: signal.occurredAt)
            var line = "• \(signal.signalType) (\(signal.subjectNodeType), \(age))"
            if !signal.payloadSnippet.isEmpty {
                line += ": \(signal.payloadSnippet)"
            }
            lines.append(line)
        }
        lines.append("[End context — \(packet.provenanceLabel)]")
        return lines.joined(separator: "\n")
    }

    private static func ageLabel(for date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case 0:        return "today"
        case 1:        return "yesterday"
        case 2...6:    return "\(days) days ago"
        case 7...13:   return "last week"
        default:       return "\(days / 7) weeks ago"
        }
    }
}
