// AmenGiveActionHandler.swift
// AMENAPP — Giving
//
// Wires the .give AmenAction to the smart notification + undo system.
// Currently routes to the org's external donation URL; upgrade to native
// StoreKit / Stripe charge by replacing the UIApplication.open call when
// the native payment flow is introduced.

import SwiftUI
import FirebaseFirestore

// MARK: - AmenGiveActionHandler

/// Coordinates the .give smart-notification flow.
///
/// `apply` sets `isPendingGive = true` and schedules a deferred Firestore write.
/// `reverse` (user taps Undo within 6 s) cancels the deferred write and clears the flag.
///
/// The Firestore write (charge side) is intentionally NOT executed until the
/// full `undoWindow` (6.0 s) has elapsed without cancellation.
@MainActor
final class AmenGiveActionHandler: ObservableObject {

    static let shared = AmenGiveActionHandler()
    private init() {}

    // MARK: Published State
    @Published private(set) var isPendingGive: Bool = false

    // MARK: - Initiate Give

    /// Call this from the give button's tap handler in lieu of opening the external URL.
    ///
    /// - Parameters:
    ///   - ministryName: Display name of the org/ministry receiving the gift.
    ///   - orgId: Firestore document ID of the GivingOrganization.
    ///   - donationUrl: External URL to open after the undo window elapses (if not cancelled).
    func initiateGive(
        ministryName: String,
        orgId: String,
        donationUrl: URL?
    ) {
        // Capture for use in closures
        var cancellationTask: Task<Void, Never>?
        var wasCancelled = false

        AmenNotifications.fire(NotifContext(
            action: .give,
            actorName: ministryName,
            toneColors: (Color.accentColor, Color.accentColor.opacity(0.7)),
            undoWindow: 6.0,
            apply: {
                // Optimistic: show pending state immediately — DO NOT charge yet.
                self.isPendingGive = true

                // Schedule the deferred commit: open donation URL after window elapses.
                cancellationTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(6.0))
                    } catch {
                        // Task was cancelled (undo tapped) — exit without committing.
                        return
                    }

                    guard !wasCancelled, let self else { return }

                    await MainActor.run {
                        self.isPendingGive = false
                    }

                    // Commit: open donation page + write intent to Firestore.
                    if let url = donationUrl {
                        await MainActor.run {
                            UIApplication.shared.open(url)
                        }
                    }

                    // Record giving intent in Firestore (non-blocking, non-critical).
                    let record: [String: Any] = [
                        "orgId": orgId,
                        "ministryName": ministryName,
                        "intentAt": FieldValue.serverTimestamp()
                    ]
                    Task.detached {
                        try? await Firestore.firestore()
                            .collection("givingIntents")
                            .addDocument(data: record)
                    }
                }
            },
            reverse: {
                // User tapped Undo within the window — cancel the deferred commit.
                wasCancelled = true
                cancellationTask?.cancel()
                self.isPendingGive = false
            }
        ))
    }
}
