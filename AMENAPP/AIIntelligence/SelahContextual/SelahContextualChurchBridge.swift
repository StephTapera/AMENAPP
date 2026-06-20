import Foundation

// MARK: - Selah Contextual Church Bridge
// Turns the existing ChurchProximityEngine (geofence + service-time + calendar + motion
// fusion) into confidence for the In-the-Room cluster. This is the canonical example of
// the `externalConfidences` injection seam: a heavier, already-consented detector feeds
// the evaluator without the engine or provider reaching into CoreLocation/EventKit itself.
//
// Read-only: it never starts monitoring (the proximity engine is started by the Quiet-Mode
// subsystem when church features are active). When not at church, or the cluster is off, it
// contributes nothing — the evaluator's permission/flag/tolerance gates still have the final
// say, so no In-the-Room suggestion surfaces without the user's camera/calendar consent.

@MainActor
enum SelahContextualChurchBridge {

    /// Confidence (0–1) that the user is physically in a service, mapped onto the mic-free
    /// In-the-Room features. Empty unless the cluster is enabled and attendance is likely.
    static func inTheRoomConfidences() -> [SelahContextualFeature: Double] {
        guard SelahContextualFlags.isClusterEnabled(.inTheRoom) else { return [:] }

        let engine = ChurchProximityEngine.shared
        guard engine.attendanceState.isAttending else { return [:] }

        let confidence = min(max(engine.confidenceScore / 100.0, 0), 1)
        guard confidence > 0 else { return [:] }

        // Presence-keyed, mic-free features. The evaluator still requires .camera for
        // bulletin capture and .calendar + .groupMembership for small-group sync.
        return [
            .bulletinSlideCapture: confidence,
            .smallGroupLiveSync: confidence
        ]
    }
}
