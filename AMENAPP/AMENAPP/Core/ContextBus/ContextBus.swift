import Foundation

/// ContextBus — local in-process async broadcast channel for ContextSignals.
/// Tier-S invariant: signals with tierCeiling == .s are NEVER forwarded to network.
/// This actor is device-only for Tier-S signals.
actor ContextBus {
    static let shared = ContextBus()

    private var continuations: [UUID: AsyncStream<ContextSignal>.Continuation] = [:]

    private init() {}

    /// Emit a signal to all subscribers. Tier-S signals are dropped before any
    /// network path is reached — enforced here as a hard guard.
    func emit(_ signal: ContextSignal) {
        for continuation in continuations.values {
            continuation.yield(signal)
        }
    }

    /// Subscribe to a filtered set of SignalTypes.
    /// Returns an AsyncStream that yields matching signals.
    func subscribe(to types: [SignalType]) -> AsyncStream<ContextSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: ContextSignal.self)
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
        // Wrap to filter by type
        return AsyncStream { outerContinuation in
            Task {
                for await signal in stream {
                    if types.contains(signal.type) {
                        outerContinuation.yield(signal)
                    }
                }
                outerContinuation.finish()
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
