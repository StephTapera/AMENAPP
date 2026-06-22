// DecayEngine.swift — Features/Intelligence/Decay
// Applies exponential half-life decay to ContextSignals to produce time-weighted relevance scores.
//
// Formula: weight = 0.5^(daysSinceSignal / signal.decayHalfLifeDays)
// A signal that just occurred has weight 1.0; at exactly its half-life it has weight 0.5.
//
// Invariants:
//  • Free capability — no entitlement check needed
//  • Pure computation — no network, no persistence, no side effects
//  • weight is clamped to [0.0, 1.0]

import Foundation

// MARK: - WeightedSignal

struct WeightedSignal: Sendable {
    let signal: ContextSignal
    /// Exponential decay weight in [0.0, 1.0]; higher = more recent relative to half-life
    let weight: Double
}

// MARK: - DecayEngine

enum DecayEngine {

    // MARK: - Public API

    /// Returns signals from the ring buffer sorted by descending weight (most relevant first).
    /// Signals with weight below `threshold` are excluded.
    static func apply(
        to signals: [ContextSignal],
        asOf now: Date = Date(),
        threshold: Double = 0.05
    ) -> [WeightedSignal] {
        signals
            .map { signal in
                let days = now.timeIntervalSince(signal.occurredAt) / 86_400
                let halfLife = max(signal.decayHalfLifeDays, 0.1)   // guard against zero
                let weight = pow(0.5, days / halfLife)
                return WeightedSignal(signal: signal, weight: min(max(weight, 0.0), 1.0))
            }
            .filter { $0.weight >= threshold }
            .sorted { $0.weight > $1.weight }
    }

    /// Returns the highest-weight signal of a given type, or nil if none exceeds the threshold.
    static func topSignal(
        ofType type: SignalType,
        in signals: [ContextSignal],
        asOf now: Date = Date(),
        threshold: Double = 0.05
    ) -> WeightedSignal? {
        apply(to: signals, asOf: now, threshold: threshold)
            .first { $0.signal.type == type }
    }

    /// Aggregates total weight by signal type — useful for determining which domain dominates.
    static func dominantType(
        in signals: [ContextSignal],
        asOf now: Date = Date()
    ) -> SignalType? {
        let weighted = apply(to: signals, asOf: now, threshold: 0.0)
        let byType = Dictionary(grouping: weighted, by: { $0.signal.type })
            .mapValues { $0.reduce(0) { $0 + $1.weight } }
        return byType.max(by: { $0.value < $1.value })?.key
    }
}
