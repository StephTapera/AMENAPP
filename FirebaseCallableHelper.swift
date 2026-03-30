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

import FirebaseFunctions

extension HTTPSCallable {
    /// Call this Firebase Cloud Function safely, isolating it from Swift
    /// Concurrency task cancellation to prevent asyncLet_finish_after_task_completion.
    ///
    /// Replaces the broken `withTaskCancellationHandler { try await call(data) }` pattern
    /// which appeared to guard against cancellation but actually did nothing — the empty
    /// `onCancel` fired as a notification only, and cancellation continued propagating
    /// into Firebase's internal async-let, causing a fatal Swift Concurrency abort.
    func safeCall(_ data: Any? = nil) async throws -> HTTPSCallableResult {
        // Task.init creates an UNSTRUCTURED task:
        //   - Inherits current actor (stays on MainActor if called from @MainActor)
        //   - Does NOT inherit the calling task's cancellation token (SE-0304)
        //   - Firebase's internal async-let runs to completion, safely unwinding
        //
        // When the outer task is cancelled while awaiting task.value:
        //   - The outer task throws CancellationError at the next check point
        //   - The inner Firebase task continues running and completes silently
        //   - No asyncLet_finish_after_task_completion crash
        let task = Task {
            try await self.call(data)
        }
        return try await task.value
    }
}
