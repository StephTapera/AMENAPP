// AMEN — NIS Birth Context (C2)
// Silently captures location + time when a note is created.
// Writes notes/{noteId}/birthContext doc.
// Gated: AMENFeatureFlags.shared.nisBirthContextEnabled

import Foundation
import CoreLocation
import FirebaseFirestore
import FirebaseAuth

// MARK: - NISBirthContextService

/// Lane E — Wave 1.
/// Capture-on-creation service for NIS C2 (Birth Context).
/// Silently captures location + timestamp at note creation time and writes
/// `notes/{noteId}/birthContext`. Server-side enrichment
/// (schedule-aware church matching) happens in birthContextEnricher.ts.
///
/// Rules:
///   1. No-op when `AMENFeatureFlags.shared.nisBirthContextEnabled` is false.
///   2. Never requests location permission — only reads a pre-granted fix.
///   3. Location read has a 5-second timeout; proceeds without it if unavailable.
///   4. Fire-and-forget: callers use `Task { await ... }` — never awaited by UI.
final class NISBirthContextService: NSObject {

    // MARK: Singleton

    static let shared = NISBirthContextService()

    // MARK: Private

    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()

    // Continuation for the one-shot location fetch (nil when not in-flight).
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    /// Capture birth context for a newly created note.
    /// - Parameters:
    ///   - noteId: Firestore document ID of the note.
    ///   - authorUID: UID of the author.
    ///
    /// This method is a no-op when `nisBirthContextEnabled` is false.
    /// Must be called as `Task { await NISBirthContextService.shared.capture(...) }`.
    func capture(noteId: String, authorUID: String) async {
        guard await AMENFeatureFlags.shared.nisBirthContextEnabled else { return }

        let createdAt = Date()
        let location = await readLocationWithTimeout()

        var payload: [String: Any] = [
            "createdAt": Timestamp(date: createdAt),
            "locationMatched": false,
            "confidence": 0.0,
        ]

        if let loc = location {
            payload["latitude"]  = loc.coordinate.latitude
            payload["longitude"] = loc.coordinate.longitude
        }

        // churchId, churchName, seriesId are nil at capture time —
        // enrichment happens server-side in birthContextEnricher.ts.

        do {
            try await db
                .collection("notes")
                .document(noteId)
                .setData(payload, merge: true)
            dlog("[NISBirthContextService] birthContext written for note \(noteId)")
        } catch {
            // Non-fatal — NIS data is best-effort.
            dlog("[NISBirthContextService] write failed for note \(noteId): \(error.localizedDescription)")
        }
    }

    // MARK: - Location (private)

    /// Returns the device's current location only if permission was already granted.
    /// Applies a 5-second timeout. Returns nil on timeout or permission denial.
    private func readLocationWithTimeout() async -> CLLocation? {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            dlog("[NISBirthContextService] location permission not granted (\(status.rawValue)) — skipping.")
            return nil
        }

        // If a recent cached fix is available, use it directly.
        if let cached = locationManager.location,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy <= 500,
           -cached.timestamp.timeIntervalSinceNow < 60 {
            return cached
        }

        // Request a one-shot update with a 5-second timeout.
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()

            // Enforce 5-second timeout.
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                // If continuation was not yet resumed, deliver nil and clean up.
                if let pending = locationContinuation {
                    locationContinuation = nil
                    locationManager.stopUpdatingLocation()
                    pending.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension NISBirthContextService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let cont = locationContinuation else { return }
        locationContinuation = nil
        manager.stopUpdatingLocation()
        cont.resume(returning: locations.first)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let cont = locationContinuation else { return }
        locationContinuation = nil
        dlog("[NISBirthContextService] location error: \(error.localizedDescription)")
        cont.resume(returning: nil)
    }

    // Do NOT implement didChangeAuthorization — we never request permission.
}
