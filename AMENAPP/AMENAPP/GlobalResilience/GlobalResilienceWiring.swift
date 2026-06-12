// GlobalResilienceWiring.swift
// AMEN — Global Resilience System
//
// Single call-site entry point that bootstraps every Global Resilience service
// at app launch. Call GlobalResilienceWiring.wire() once from either:
//
//   AMENAPPApp.init()
//   — or —
//   AppDelegate.application(_:didFinishLaunchingWithOptions:)
//
// Also inject the three environment objects into the root view hierarchy:
//
//   ContentView()
//       .environmentObject(CapabilityMonitor.shared)
//       .environmentObject(LowDataModeManager.shared)
//       .environmentObject(GlobalResilienceFeatureFlags.shared)

import SwiftUI
import FirebaseFunctions

// MARK: - GlobalResilienceWiring

enum GlobalResilienceWiring {

    /// Bootstrap all Global Resilience services.
    ///
    /// Safe to call multiple times — each service uses a lazy singleton and is
    /// idempotent on repeated invocations. The Remote Config fetch is re-issued
    /// on every call, which is intentional: new sessions should always try to
    /// pull fresh flag values.
    static func wire() {

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
// ── AMENAPPApp.init() ──────────────────────────────────────────────────────────
//
//   init() {
//       // … existing init code …
//       GlobalResilienceWiring.wire()
//   }
//
// ── AMENAPPApp body (WindowGroup) ─────────────────────────────────────────────
//
//   var body: some Scene {
//       WindowGroup {
//           AccountStatusGate {
//               ContentView()
//                   // … existing modifiers …
//                   .environmentObject(CapabilityMonitor.shared)
//                   .environmentObject(LowDataModeManager.shared)
//                   .environmentObject(GlobalResilienceFeatureFlags.shared)
//           }
//       }
//   }
//
// ── AppDelegate.application(_:didFinishLaunchingWithOptions:) (alternative) ───
//
//   func application(
//       _ application: UIApplication,
//       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//   ) -> Bool {
//       // … existing setup …
//       GlobalResilienceWiring.wire()
//       return true
//   }
// ──────────────────────────────────────────────────────────────────────────────
