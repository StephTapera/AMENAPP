// GlobalResilienceWiring.swift
// AMEN — Global Resilience System
//
// Single call-site entry point that bootstraps every Global Resilience service
// at app launch. Call GlobalResilienceWiring.wire() once from:
//
//   AppDelegate.application(_:didFinishLaunchingWithOptions:)
//   — AFTER FirebaseApp.configure() —
//
// Also inject the three environment objects into the root view hierarchy:
//
//   ContentView()
//       .environmentObject(CapabilityMonitor.shared)
//       .environmentObject(LowDataModeManager.shared)
//       .environmentObject(GlobalResilienceFeatureFlags.shared)

import SwiftUI
import FirebaseCore
import FirebaseFunctions

// MARK: - GlobalResilienceWiring

enum GlobalResilienceWiring {

    /// Bootstrap all Global Resilience services.
    ///
    /// Must be called from AppDelegate AFTER FirebaseApp.configure().
    /// Calling before configure() is a programming error — it will assert in
    /// DEBUG and return without wiring anything in RELEASE.
    @MainActor
    static func wire() {
        // Crash fence: Firestore and Remote Config both throw if FirebaseApp.configure()
        // has not been called. Do not move this call to AMENAPPApp.init() — the
        // AppDelegate runs configure() first, but AMENAPPApp.init() executes before it.
        guard FirebaseApp.app() != nil else {
            assertionFailure("[GlobalResilienceWiring] wire() called before FirebaseApp.configure()")
            return
        }

        // 1. Fetch all 12 Remote Config feature flags asynchronously.
        //    Flags default to false (safe-off) until the first successful fetch.
        Task {
            await GlobalResilienceFeatureFlags.shared.fetchAll()
        }

        // 2. Trigger CapabilityMonitor initialization via its lazy singleton.
        //    The singleton starts NWPathMonitor, thermal KVO, and low-power observers
        //    immediately on first access. The @MainActor init is safe here because
        //    wire() is called from the main thread (app init / didFinishLaunching).
        _ = CapabilityMonitor.shared

        // 3. Restart any uploads that were pending when the previous app session ended.
        //    ResumableUploadManager queries the background URLSession for active tasks
        //    and re-enqueues only the ones that are no longer running.
        ResumableUploadManager.shared.resumePendingUploads()

        // 4. Start the CrisisBulletin Firestore listener so bulletins are available
        //    without a network round-trip the first time a view requests them.
        CrisisBulletinService.shared.startListening()

        // 5. Start the NWPathMonitor inside MessageOutbox so queued outgoing messages
        //    are flushed automatically when connectivity is restored.
        MessageOutbox.shared.startNetworkObservation()
    }
}

// MARK: - CALL SITE INSTRUCTIONS
//
// ── AppDelegate.application(_:didFinishLaunchingWithOptions:) ─────────────────
//
//   func application(
//       _ application: UIApplication,
//       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//   ) -> Bool {
//       // App Check provider factory MUST be set before configure()
//       AppCheck.setAppCheckProviderFactory(...)
//       FirebaseApp.configure()           // ← configure() FIRST
//       GlobalResilienceWiring.wire()     // ← wire() AFTER
//       return true
//   }
//
// ── Do NOT call from AMENAPPApp.init() ───────────────────────────────────────
//
//   AMENAPPApp.init() executes BEFORE AppDelegate.didFinishLaunchingWithOptions,
//   so Firebase is not yet configured when init() runs. The guard in wire()
//   will catch this if it ever regresses and produce a clear assertionFailure.
//
// ──────────────────────────────────────────────────────────────────────────────
