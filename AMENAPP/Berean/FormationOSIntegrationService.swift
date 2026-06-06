// FormationOSIntegrationService.swift
// AMENAPP — Berean Intelligence OS
//
// Bridges the Berean Daily Formation companion to the Memory Graph and the
// Trust OS via AmenOSBridge.
//
// INVARIANT: CrisisCard entries (FormationCardKind.crisis) NEVER write memory
// nodes and NEVER call AmenOSBridge. Crisis routing is handled exclusively by
// Trust OS / SafetyOrchestrator.

import Foundation
import FirebaseFirestore

// MARK: - Service

@MainActor
final class FormationOSIntegrationService: ObservableObject {
    static let shared = FormationOSIntegrationService()

    private let memoryGraph = BereanMemoryGraphService.shared
    private let bridge      = AmenOSBridge.shared

    private init() {}

    // MARK: - Card Completion

    /// Records a formation card completion in the memory graph and notifies
    /// Trust OS when a streak is active.
    ///
    /// Crisis guard: if `entry.cardKind == .crisis` this method returns
    /// immediately without touching the memory graph or the bridge.
    func recordCardCompletion(uid: String, entry: BereanFormationEntry) async {
        // ABSOLUTE INVARIANT — crisis entries must never reach the memory graph.
        guard entry.cardKind != .crisis else { return }

        let node = BereanMemoryNode(
            uid: uid,
            kind: .formation,
            data: [
                "cardKind": entry.cardKind.rawValue,
                "streakDay": "\(entry.streakDay)"
            ],
            sensitivity: .normal
        )

        do {
            try await memoryGraph.addNode(node)
        } catch {
            // Non-fatal — formation progress is best-effort in the graph.
            return
        }

        // Notify Trust OS only when an active streak is present.
        if entry.streakDay > 0 {
            bridge.formationStreakActive(uid: uid, streakDay: entry.streakDay)
        }
    }

    // MARK: - Streak

    /// Returns the current formation streak day count by examining completed
    /// formation nodes in the memory graph, counting consecutive days back from today.
    func currentStreakDay(uid: String) async -> Int {
        let nodes = await memoryGraph.fetchNodes(uid: uid, kinds: [.formation])

        // Collect the calendar dates on which a card was completed.
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())

        var completedDays = Set<Date>()
        for node in nodes {
            let nodeDate = calendar.startOfDay(for: Date(timeIntervalSince1970: node.createdAt))
            // Skip crisis nodes that somehow reached this layer (belt-and-suspenders).
            if node.data["cardKind"]?.uppercased() == FormationCardKind.crisis.rawValue { continue }
            completedDays.insert(nodeDate)
        }

        // Walk backwards from today counting consecutive days.
        var streak = 0
        var cursor = today
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    // MARK: - Weekly Summary

    /// Returns a human-readable summary of the last 7 days of completed formation
    /// cards. Summary is constructed purely from memory graph nodes — no AI involved.
    ///
    /// Example: "5 formations this week: 3 Scripture, 1 Prayer, 1 Challenge"
    func weeklyFormationSummary(uid: String) async -> String {
        let nodes = await memoryGraph.fetchNodes(uid: uid, kinds: [.formation])

        let calendar    = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        // Filter to the last 7 days, exclude crisis nodes.
        let recentNodes = nodes.filter { node in
            let nodeDate = Date(timeIntervalSince1970: node.createdAt)
            guard nodeDate >= sevenDaysAgo else { return false }
            return node.data["cardKind"]?.uppercased() != FormationCardKind.crisis.rawValue
        }

        guard !recentNodes.isEmpty else {
            return "No formations this week. Start your first card today."
        }

        // Tally by card kind.
        var counts: [String: Int] = [:]
        for node in recentNodes {
            let kindRaw = node.data["cardKind"] ?? "Unknown"
            // Capitalise first letter for display ("SCRIPTURE" → "Scripture").
            let display = kindRaw.prefix(1).uppercased() + kindRaw.dropFirst().lowercased()
            counts[display, default: 0] += 1
        }

        let total   = recentNodes.count
        let details = counts
            .sorted { $0.value > $1.value }
            .map { "\($0.value) \($0.key)" }
            .joined(separator: ", ")

        let plural = total == 1 ? "formation" : "formations"
        return "\(total) \(plural) this week: \(details)"
    }
}
