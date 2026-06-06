// AmenLiveActivityContract.swift
// AMENAPP — ActivityKit Live Activity contract (NATIVE PHASE — future)
//
// ⚠️  NATIVE PHASE ONLY — This file defines the data contract for the
//     Live Activity / Dynamic Island integration for Amen Live sessions.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HUMAN GATE — Required before this contract can be wired to ActivityKit:
//
//   1. Add the ActivityKit framework to the AMENWidgetExtension target in Xcode:
//        AMENWidgetExtension → Build Phases → Link Binary With Libraries
//        → + → ActivityKit.framework
//
//   2. Add NSSupportsLiveActivities = YES to AMENAPP/Info.plist
//
//   3. Request ActivityKit authorization in the app lifecycle (AMENAPPApp.swift):
//        import ActivityKit
//        Activity<AmenLiveActivityAttributes>.requestAuthorization()
//
//   4. Add this file to AMENWidgetExtension target membership
//      (File Inspector → Target Membership → check AMENWidgetExtension)
//      OR move it to a shared Swift Package / framework.
//
//   5. Implement AmenLiveWidget (see AmenLiveActivityView.swift) using this contract
//      and register it in the AMENWidgetExtension WidgetBundle.
//
//   6. Call Activity<AmenLiveActivityAttributes>.request(...) when a live session
//      starts in the main app (e.g. from AmenLiveViewModel or AmenLiveService).
//
//   7. Dynamic Island compact / minimal / expanded layouts need to be designed
//      and implemented in AmenLiveActivityView.swift. The UI is NOT defined here.
//      This file defines the data model only.
//
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// NOTE: This file does NOT import ActivityKit.
// ActivityKit is only available in the widget extension target.
// Import it in AmenLiveActivityView.swift (AMENWidgetExtension target only).
//
// Relationship to existing contracts:
//   - AmenLiveActivityAttributes.swift — already exists; defines the full
//     ActivityKit attributes struct with ContentState, phases, and tier icons.
//     That file is the canonical ActivityKit contract for the existing
//     Living Intelligence card system.
//   - THIS file defines a parallel contract scoped to AmenLive sessions
//     (prayer events, sermon streams, community moments, etc.) — a distinct
//     surface from the Intelligence brief system.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import Foundation

// MARK: - AmenLiveActivityAttributes (contract definition)

/// Data model for the Amen Live Activity. Mirrors ActivityAttributes protocol shape
/// without importing ActivityKit (the import happens in the widget extension target only).
///
/// Static data: set once at Activity.request() time, does not change.
/// Dynamic data (ContentState): updated via activity.update() or remote APNs push.
///
/// Formation invariants enforced:
///   - NO spectacle counters in ContentState
///   - Finite: every Activity.request() call must set staleDate = session.scheduledEndAt
///   - Phase labels are status words, never metrics
struct AmenLiveActivityContract {

    // MARK: - Static attributes (set at launch, immutable)

    /// Firestore document ID of the AmenLiveSession (amen_live_sessions/{id}).
    let sessionId: String

    /// AmenLiveType raw value: "PRAYER_EVENT" | "SERMON_STREAM" |
    /// "COMMUNITY_MOMENT" | "VOLUNTEER_MOBILIZATION" | "CRISIS_RESPONSE"
    let sessionType: String

    /// Human-readable host name (e.g. "Grace Community Church").
    let hostName: String

    /// Session title displayed in the Live Activity.
    let sessionTitle: String

    // MARK: - ContentState (dynamic, updated via ActivityKit)

    /// Dynamic state that can be pushed to the Live Activity via
    /// activity.update() or a remote APNs push payload.
    ///
    /// Formation invariants — deliberately absent:
    ///   NO: attendeeCount, viewerCount, prayerCount, watcherCount
    ///   NO: spectacle counters of any kind
    struct ContentState: Codable, Hashable, Sendable {

        /// Current lifecycle phase of the live session.
        let phase: LiveSessionPhase

        /// Optional current action description shown in the Live Activity.
        /// Examples: "Prayer request shared", "Scripture reading", "Q&A open"
        /// NEVER a count. NEVER a metric.
        let currentAction: String?

        /// Approximate minutes remaining. Optional — only set when scheduledEndAt is known.
        /// Displayed as "~N min left" — not a countdown timer (avoids anxiety patterns).
        let minutesRemaining: Int?

        /// Set to true when the session has ended. Triggers the .ended phase
        /// and prompts ActivityKit to end the activity after a short delay.
        let isEnded: Bool
    }

    // MARK: - LiveSessionPhase

    /// Lifecycle phases for an Amen Live session in the Live Activity.
    /// Must reach .ended — no infinite loops.
    enum LiveSessionPhase: String, Codable, Hashable, Sendable {
        /// Session is active and ongoing.
        case active = "ACTIVE"

        /// Session is starting (within 15 minutes of scheduledStartAt).
        case starting = "STARTING"

        /// Session is in its closing minutes.
        case closing = "CLOSING"

        /// Session has ended. Activity should be dismissed.
        case ended = "ENDED"

        /// Human-readable status label shown in the Live Activity.
        /// Never a count. Never a metric.
        var displayLabel: String {
            switch self {
            case .active:   return "Live"
            case .starting: return "Starting Soon"
            case .closing:  return "Closing"
            case .ended:    return "Ended"
            }
        }

        /// SF Symbol name for the phase indicator in the Live Activity.
        var symbolName: String {
            switch self {
            case .active:   return "circle.fill"
            case .starting: return "clock.fill"
            case .closing:  return "checkmark.circle.fill"
            case .ended:    return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - AmenLiveActivityBridge (main-app side)

/// Utilities for launching and updating an Amen Live Activity from the main app.
///
/// ⚠️ All methods in this struct are stubs — they require the HUMAN GATE steps
/// above to be completed before they can be wired to ActivityKit.
///
/// After completing the HUMAN GATE:
///   1. Import ActivityKit in AmenLiveActivityBridge.swift (or a separate file)
///   2. Replace the stub bodies with real Activity<AmenLiveActivityAttributes>.request()
///      and activity.update() calls
///   3. Add @available(iOS 16.2, *) guards

struct AmenLiveActivityBridge {

    /// Stub: start a Live Activity for the given session.
    ///
    /// Production implementation:
    ///   let attributes = AmenLiveActivityAttributes(
    ///       sessionId: session.id,
    ///       sessionType: session.type.rawValue,
    ///       hostName: session.hostName,
    ///       sessionTitle: session.title
    ///   )
    ///   let initialState = AmenLiveActivityAttributes.ContentState(
    ///       phase: .starting,
    ///       currentAction: nil,
    ///       minutesRemaining: scheduledDurationMinutes,
    ///       isEnded: false
    ///   )
    ///   let staleDate = session.scheduledEndAt.map { Date(timeIntervalSince1970: $0) }
    ///   let activity = try Activity<AmenLiveActivityAttributes>.request(
    ///       attributes: attributes,
    ///       contentState: initialState,
    ///       pushType: .token   // enable remote APNs push updates
    ///   )
    ///   // Store activity.id to update/end later
    static func startActivity(for session: AmenLiveSession) {
        // HUMAN GATE: implement after adding ActivityKit + NSSupportsLiveActivities
        print("[AmenLiveActivityBridge] startActivity stub — HUMAN GATE not yet completed")
    }

    /// Stub: update the phase/action of an active Live Activity.
    ///
    /// Production implementation:
    ///   let updatedState = AmenLiveActivityAttributes.ContentState(
    ///       phase: phase,
    ///       currentAction: currentAction,
    ///       minutesRemaining: minutesRemaining,
    ///       isEnded: false
    ///   )
    ///   await activity.update(using: updatedState)
    static func updateActivity(sessionId: String, phase: AmenLiveActivityContract.LiveSessionPhase, currentAction: String?) {
        // HUMAN GATE: implement after completing ActivityKit wiring
        print("[AmenLiveActivityBridge] updateActivity stub — HUMAN GATE not yet completed")
    }

    /// Stub: end the Live Activity for the given session.
    ///
    /// Production implementation:
    ///   let finalState = AmenLiveActivityAttributes.ContentState(
    ///       phase: .ended,
    ///       currentAction: nil,
    ///       minutesRemaining: nil,
    ///       isEnded: true
    ///   )
    ///   await activity.end(using: finalState, dismissalPolicy: .after(Date.now.addingTimeInterval(30)))
    static func endActivity(sessionId: String) {
        // HUMAN GATE: implement after completing ActivityKit wiring
        print("[AmenLiveActivityBridge] endActivity stub — HUMAN GATE not yet completed")
    }
}
