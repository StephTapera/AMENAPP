//
//  FirebaseCallableHelper.swift
//  AMENAPP
//
//  Root cause: Firebase's HTTPSCallable.call(_:) spawns an internal `async let`
//  child task to bridge its callback-based API. `withTaskCancellationHandler`
//  does NOT prevent cancellation from propagating — the `onCancel` closure fires
//  as a side-effect but cancellation continues into `try await call(data)`,
//  reaching Firebase's internal async-let and triggering:
//  asyncLet_finish_after_task_completion → swift_Concurrency_fatalError → SIGABRT
//
//  Fix: run Firebase inside an UNSTRUCTURED Task (Task.init, not Task.detached).
//  Unstructured tasks do NOT participate in structured concurrency parent-child
//  cancellation. `Task.init` is correct here (not detached) because it inherits
//  the current actor, keeping Firebase calls on the right execution context.
//
//  Trade-off: Firebase network requests cannot be mid-flight cancelled. This is
//  intentional — Firebase's URLSession tasks manage their own lifecycle, and
//  partial cancellation of HTTPSCallable leaves server-side state ambiguous.
//  The outer `try await task.value` still respects cooperative cancellation at
//  the next suspension point after the Firebase call completes.
//

import Foundation
import FirebaseFunctions

extension Functions {
    /// Call a Cloud Function by name with a short timeout (default 15 s instead of
    /// the SDK default of 70 s).  On the user-facing Berean AI ask path a 70-second
    /// hang produces a blank screen; fail fast and let the caller show an error.
    ///
    /// - Parameters:
    ///   - name: The Cloud Function name (e.g. "bereanChatProxy").
    ///   - data: Optional request payload passed through to the callable.
    ///   - timeout: Maximum time to wait for a response (default 15 seconds).
    /// - Returns: The raw `HTTPSCallableResult` — caller casts `.data` as needed.
    @discardableResult
    func callWithTimeout(
        _ name: String,
        data: Any? = nil,
        timeout: TimeInterval = 15
    ) async throws -> HTTPSCallableResult {
        let callable = httpsCallable(name)
        callable.timeoutInterval = timeout
        return try await callable.call(data)
    }
}

extension HTTPSCallable {
    /// Call this Firebase Cloud Function safely, isolating it from Swift
    /// Concurrency task cancellation to prevent asyncLet_finish_after_task_completion,
    /// AND applying a short timeout so a poor-signal stall never hangs the UI for
    /// the 70-second SDK default.
    ///
    /// - Parameters:
    ///   - data: Optional request payload.
    ///   - timeout: Maximum seconds to wait (default 15 s).  Use 30 s for Berean LLM
    ///     calls, 15 s for moderation/safety calls, 10 s for read-only data calls.
    ///
    /// Replaces the broken `withTaskCancellationHandler { try await call(data) }` pattern
    /// which appeared to guard against cancellation but actually did nothing — the empty
    /// `onCancel` fired as a notification only, and cancellation continued propagating
    /// into Firebase's internal async-let, causing a fatal Swift Concurrency abort.
    @preconcurrency func safeCall(_ data: Any? = nil, timeout: TimeInterval = 15) async throws -> HTTPSCallableResult {
        // Apply the short timeout before handing off to the unstructured task.
        self.timeoutInterval = timeout
        // Task.init creates an UNSTRUCTURED task:
        //   - Inherits current actor (stays on MainActor if called from @MainActor)
        //   - Does NOT inherit the calling task's cancellation token (SE-0304)
        //   - Firebase's internal async-let runs to completion, safely unwinding
        //
        // When the outer task is cancelled while awaiting task.value:
        //   - The outer task throws CancellationError at the next check point
        //   - The inner Firebase task continues running and completes silently
        //   - No asyncLet_finish_after_task_completion crash
        let task = Task { @Sendable in
            try await self.call(data)
        }
        return try await task.value
    }
}
