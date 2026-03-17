/// WriteOpTracer.swift
/// AMENAPP
///
/// Lightweight instrumentation for write operations (Firestore + RTDB).
/// Tracks idempotency keys, retry counts, and final outcomes.
/// Also provides a crash-breadcrumb ring-buffer (last 50 user actions).
///
/// All state is in-memory and DEBUG-only.  In Release builds every call is
/// a typed no-op inlined away by the compiler.
///
/// Usage — write ops:
///   let token = WriteOpTracer.begin("createPost", key: idempotencyKey)
///   // ... perform write ...
///   WriteOpTracer.succeed(token, docId: docRef.documentID)
///   // or on failure:
///   WriteOpTracer.fail(token, error: error)
///
/// Usage — breadcrumbs:
///   Breadcrumb.record("tapped_post_button")
///   Breadcrumb.record("opened_chat", meta: ["convId": id])

import Foundation

// MARK: - Breadcrumb Ring Buffer

/// Records the last 50 user actions.  Call `Breadcrumb.record()` from
/// tap handlers, view lifecycle, and key transitions so that crash logs
/// include actionable context.
struct Breadcrumb {

    let action: String
    let meta: [String: String]
    let timestamp: Date

    // Thread-safe ring buffer — writes serialised on dedicated queue
    private static let queue = DispatchQueue(label: "com.amen.breadcrumbs", qos: .utility)
    private static var buffer: [Breadcrumb] = []
    private static let maxCount = 50

    /// Record a user action or lifecycle event.
    static func record(_ action: String, meta: [String: String] = [:]) {
        #if DEBUG
        let crumb = Breadcrumb(action: action, meta: meta, timestamp: Date())
        queue.async {
            buffer.append(crumb)
            if buffer.count > maxCount {
                buffer.removeFirst(buffer.count - maxCount)
            }
        }
        #endif
    }

    /// Return a copy of the current breadcrumb trail (newest last).
    static func trail() -> [Breadcrumb] {
        #if DEBUG
        return queue.sync { buffer }
        #else
        return []
        #endif
    }

    /// Dump the trail to console — call from a crash handler or debug menu.
    static func dump() {
        #if DEBUG
        let crumbs = trail()
        print("[Breadcrumb] ===== Last \(crumbs.count) actions =====")
        for (idx, crumb) in crumbs.enumerated() {
            let ts = ISO8601DateFormatter().string(from: crumb.timestamp)
            let metaStr = crumb.meta.isEmpty ? "" : " \(crumb.meta)"
            print("[Breadcrumb] \(idx + 1). \(ts)  \(crumb.action)\(metaStr)")
        }
        #endif
    }
}

// MARK: - Write-Op Tracing

#if DEBUG

/// A handle returned by WriteOpTracer.begin().
struct WriteOpToken {
    let opName: String
    let idempotencyKey: String
    let retryCount: Int
    let startTime: CFAbsoluteTime
}

/// Tracks in-flight and completed write operations.
/// Thread-safe: all mutations go through the internal serial queue.
@MainActor
final class WriteOpTracer {

    static let shared = WriteOpTracer()

    private var inflight: [String: WriteOpToken] = [:]  // key → token
    private var completed: [(token: WriteOpToken, outcome: String, elapsed: Double)] = []
    private let maxCompleted = 100

    private init() {}

    // MARK: - API

    /// Begin tracing a write op.  Returns a token to pass to succeed/fail.
    static func begin(_ opName: String, key: String, retryCount: Int = 0) -> WriteOpToken {
        let token = WriteOpToken(
            opName: opName,
            idempotencyKey: key,
            retryCount: retryCount,
            startTime: CFAbsoluteTimeGetCurrent()
        )
        Task { @MainActor in
            shared.inflight[key] = token
            print("[WriteOp] START  \(opName)  key=\(key.prefix(20))… retry=\(retryCount)")
        }
        Breadcrumb.record("write_op_start", meta: ["op": opName, "retry": "\(retryCount)"])
        return token
    }

    /// Mark op succeeded.
    static func succeed(_ token: WriteOpToken, docId: String? = nil) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - token.startTime) * 1000
        let outcome = docId.map { "OK docId=\($0)" } ?? "OK"
        Task { @MainActor in
            shared.inflight.removeValue(forKey: token.idempotencyKey)
            shared.record(token: token, outcome: outcome, elapsed: elapsed)
            print("[WriteOp] OK     \(token.opName)  \(String(format: "%.0f", elapsed))ms  \(docId.map { "docId=\($0.prefix(12))…" } ?? "")")
        }
        Breadcrumb.record("write_op_ok", meta: ["op": token.opName, "ms": String(format: "%.0f", elapsed)])
    }

    /// Mark op failed.
    static func fail(_ token: WriteOpToken, error: Error) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - token.startTime) * 1000
        let outcome = "FAIL \(error.localizedDescription)"
        Task { @MainActor in
            shared.inflight.removeValue(forKey: token.idempotencyKey)
            shared.record(token: token, outcome: outcome, elapsed: elapsed)
            print("[WriteOp] FAIL   \(token.opName)  \(String(format: "%.0f", elapsed))ms  error=\(error.localizedDescription)")
        }
        Breadcrumb.record("write_op_fail", meta: ["op": token.opName, "err": error.localizedDescription.prefix(60).description])
    }

    // MARK: - Debug Dump

    /// Dump all inflight and recently completed ops.
    static func dumpAll() {
        Task { @MainActor in
            print("[WriteOp] ===== In-flight (\(shared.inflight.count)) =====")
            for (key, token) in shared.inflight {
                let age = (CFAbsoluteTimeGetCurrent() - token.startTime) * 1000
                print("[WriteOp]   \(token.opName)  key=\(key.prefix(20))…  age=\(String(format: "%.0f", age))ms  retry=\(token.retryCount)")
            }
            print("[WriteOp] ===== Completed (last \(shared.completed.count)) =====")
            for entry in shared.completed.suffix(20) {
                print("[WriteOp]   \(entry.token.opName)  \(String(format: "%.0f", entry.elapsed))ms  \(entry.outcome.prefix(80))")
            }
        }
    }

    // MARK: - Private

    private func record(token: WriteOpToken, outcome: String, elapsed: Double) {
        completed.append((token, outcome, elapsed))
        if completed.count > maxCompleted {
            completed.removeFirst(completed.count - maxCompleted)
        }
    }
}

#else

// Release-build no-ops — compiler eliminates all call sites.

struct WriteOpToken {}

@inline(__always) func _writeOpBegin(_ opName: String, key: String, retryCount: Int = 0) -> WriteOpToken { WriteOpToken() }
@inline(__always) func _writeOpSucceed(_ token: WriteOpToken, docId: String? = nil) {}
@inline(__always) func _writeOpFail(_ token: WriteOpToken, error: Error) {}

// Provide the same call-site API so callers compile identically in both configs.
final class WriteOpTracer {
    static func begin(_ opName: String, key: String, retryCount: Int = 0) -> WriteOpToken { WriteOpToken() }
    static func succeed(_ token: WriteOpToken, docId: String? = nil) {}
    static func fail(_ token: WriteOpToken, error: Error) {}
    static func dumpAll() {}
}

#endif
