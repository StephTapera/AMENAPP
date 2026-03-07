/// PerfTracker.swift
/// AMENAPP
///
/// Lightweight, zero-overhead-in-release performance timing utility.
/// All measurement and logging compiles away completely in Release builds.
///
/// Usage:
///   let token = PerfTracker.begin("feed_load")
///   // ... work ...
///   PerfTracker.end(token)          // logs "[Perf] feed_load  123ms"
///
///   PerfTracker.measure("profile_open") {
///       // sync work
///   }
///
///   await PerfTracker.measureAsync("chat_open") {
///       await setupChat()
///   }

import Foundation

#if DEBUG

/// A single timing measurement.
struct PerfToken {
    let label: String
    let start: CFAbsoluteTime

    init(_ label: String) {
        self.label = label
        self.start = CFAbsoluteTimeGetCurrent()
    }
}

@inline(__always)
func PerfBegin(_ label: String) -> PerfToken {
    PerfToken(label)
}

@inline(__always)
func PerfEnd(_ token: PerfToken, threshold ms: Double = 0) {
    let elapsed = (CFAbsoluteTimeGetCurrent() - token.start) * 1000
    if elapsed >= ms {
        print("[Perf] \(token.label)\t\(String(format: "%.1f", elapsed))ms")
    }
}

@inline(__always)
func PerfMeasure(_ label: String, threshold ms: Double = 0, block: () -> Void) {
    let t = PerfBegin(label)
    block()
    PerfEnd(t, threshold: ms)
}

@inline(__always)
func PerfMeasureAsync(_ label: String, threshold ms: Double = 0, block: () async -> Void) async {
    let t = PerfBegin(label)
    await block()
    PerfEnd(t, threshold: ms)
}

// MARK: - Listener Counter (Debug only)

/// Thread-safe counter for tracking active Firestore/RTDB listener counts.
/// Use ListenerCounter.attach("notifications") / .detach("notifications") around
/// each addSnapshotListener / removeListener call.  In Debug builds this logs
/// attach/detach events and warns when a key exceeds the expected maximum.
@MainActor
final class ListenerCounter {
    static let shared = ListenerCounter()
    
    private var counts: [String: Int] = [:]
    
    /// Call when a listener is registered.  maxExpected defaults to 1 for singletons.
    func attach(_ key: String, maxExpected: Int = 1) {
        counts[key, default: 0] += 1
        let count = counts[key]!
        print("[Listener] + \(key) → \(count) active")
        if count > maxExpected {
            print("⚠️ [Listener] OVER LIMIT: \(key) has \(count) listeners (max \(maxExpected))")
        }
    }
    
    /// Call when a listener is removed.
    func detach(_ key: String) {
        let before = counts[key, default: 0]
        counts[key] = max(0, before - 1)
        print("[Listener] - \(key) → \(counts[key]!) active")
    }
    
    /// Dump current listener state to console.
    func dumpAll() {
        print("[Listener] === Active Listeners ===")
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) {
            let flag = count > 1 ? " ⚠️" : ""
            print("[Listener]   \(key): \(count)\(flag)")
        }
    }
}

#else

// In Release builds every call is a typed no-op that the compiler eliminates entirely.

struct PerfToken {}

@inline(__always) func PerfBegin(_ label: String) -> PerfToken { PerfToken() }
@inline(__always) func PerfEnd(_ token: PerfToken, threshold ms: Double = 0) {}
@inline(__always) func PerfMeasure(_ label: String, threshold ms: Double = 0, block: () -> Void) { block() }
@inline(__always) func PerfMeasureAsync(_ label: String, threshold ms: Double = 0, block: () async -> Void) async { await block() }

// Release-mode no-ops for ListenerCounter
@MainActor
final class ListenerCounter {
    static let shared = ListenerCounter()
    @inline(__always) func attach(_ key: String, maxExpected: Int = 1) {}
    @inline(__always) func detach(_ key: String) {}
    @inline(__always) func dumpAll() {}
}

#endif
