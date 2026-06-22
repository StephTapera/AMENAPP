// ContextBus.swift
// AMEN — Central signal emission + subscription hub
//
// Invariants (FROZEN — do not weaken):
//  • crisisSurfaceOpened (tierCeiling .s) NEVER reaches the network
//  • All consent edges default OFF except activityToRhythm
//  • Ring buffer is capped at 500 signals (evict oldest)
//  • Signals requiring a consent edge are silently dropped if that edge is disabled
//  • Server forward is fire-and-forget; failures are non-fatal

import Foundation
import FirebaseFirestore
import FirebaseAuth

actor ContextBus {

    // MARK: - Singleton

    static let shared = ContextBus()

    // MARK: - Internal state

    private var ringBuffer: [ContextSignal] = []
    private let ringBufferCapacity = 500

    private var forwardedCount: Int = 0

    /// Active subscriptions keyed by an opaque subscriber UUID.
    private var subscriptions: [UUID: Subscription] = [:]

    private struct Subscription {
        let types: Set<SignalType>
        let continuation: AsyncStream<ContextSignal>.Continuation
    }

    // MARK: - Init

    private init() {}

    // MARK: - Emit

    /// Emits a signal through the bus. See invariants at the top of this file.
    func emit(_ signal: ContextSignal) async {
        // INVARIANT: device-only tier (.s) — deliver locally only, never forward.
        if signal.tierCeiling == .s {
            fanOut(signal)
            return
        }

        // Consent check — drop silently if edge is disabled.
        if let edge = signal.consentEdgeRequired {
            guard await consentAllows(edge) else { return }
        }

        // Append to ring buffer, evicting oldest if at capacity.
        appendToRingBuffer(signal)

        // Fan out to local subscribers.
        fanOut(signal)

        // Tier .c / .p: enqueue server forward (fire and forget).
        Task {
            await serverForward(signal)
        }
    }

    // MARK: - Subscribe

    /// Returns an AsyncStream that yields every ContextSignal whose type is in `types`.
    /// The stream runs until the caller cancels its task.
    func subscribe(to types: [SignalType]) -> AsyncStream<ContextSignal> {
        let subscriberID = UUID()
        let typeSet = Set(types)

        let (stream, continuation) = AsyncStream<ContextSignal>.makeStream()

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscription(id: subscriberID) }
        }

        subscriptions[subscriberID] = Subscription(types: typeSet, continuation: continuation)
        return stream
    }

    // MARK: - Pending forward count

    /// Number of signals in the ring buffer that have not yet been confirmed forwarded.
    var pendingForwardCount: Int {
        ringBuffer.count - forwardedCount
    }

    // MARK: - Private helpers

    private func consentAllows(_ edge: ConsentEdge) async -> Bool {
        await MainActor.run { ConsentStore.shared.isEnabled(edge) }
    }

    private func appendToRingBuffer(_ signal: ContextSignal) {
        if ringBuffer.count >= ringBufferCapacity {
            ringBuffer.removeFirst()
        }
        ringBuffer.append(signal)
    }

    private func fanOut(_ signal: ContextSignal) {
        for subscription in subscriptions.values {
            guard subscription.types.contains(signal.type) else { continue }
            subscription.continuation.yield(signal)
        }
    }

    private func removeSubscription(id: UUID) {
        subscriptions.removeValue(forKey: id)
    }

    // MARK: - Server forward

    /// Posts a signal to Firestore. Only called for tier .c / .p.
    /// Fire-and-forget — failures are logged but non-fatal.
    private func serverForward(_ signal: ContextSignal) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let signalIDString = signal.id.uuidString
        let ref = db
            .collection("contextSignals")
            .document(uid)
            .collection("signals")
            .document(signalIDString)

        var data: [String: Any] = [
            "id": signalIDString,
            "type": signal.type.rawValue,
            "tierCeiling": signal.tierCeiling.rawValue,
            "occurredAt": Timestamp(date: signal.occurredAt),
            "decayHalfLifeDays": signal.decayHalfLifeDays
        ]

        if let edge = signal.consentEdgeRequired {
            data["consentEdgeRequired"] = edge.rawValue
        }

        data["payload"] = signal.payload.mapValues { anyCodableToAny($0) }
        data["subjectRefs"] = signal.subjectRefs.map {
            ["nodeType": $0.nodeType.rawValue, "nodeID": $0.nodeID]
        }

        do {
            try await ref.setData(data, merge: false)
            forwardedCount += 1
        } catch {
            // Non-fatal — signal may be retried on next session.
        }
    }

    // MARK: - AnyCodableValue → Any conversion for Firestore

    private func anyCodableToAny(_ value: AnyCodableValue) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let arr): return arr.map { anyCodableToAny($0) }
        case .dictionary(let dict): return dict.mapValues { anyCodableToAny($0) }
        case .null: return NSNull()
        }
    }
}
