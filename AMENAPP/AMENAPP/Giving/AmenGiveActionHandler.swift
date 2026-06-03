// AmenGiveActionHandler.swift
// AMENAPP — Giving
//
// Stub: wires the .give AmenAction to the smart notification system.
//
// TODO: wire to real post model / GivingOrganization when a native in-app
// give flow (StoreKit or Stripe) is introduced. The current architecture
// routes directly to the org's external donation URL via GivingOrgDetailView
// and GiveConfirmationSheet, which bypasses this handler.
//
// WHEN WIRING:
//   1. Replace the TODO placeholders below with the real org/ministry data.
//   2. Call `AmenGiveActionHandler.shared.initiateGive(for:)` from the give
//      button's tap handler instead of opening the external URL directly.
//   3. Move the `UIApplication.shared.open(url)` call into the deferred Task
//      inside `apply` so the URL only opens after the undo window elapses and
//      the user hasn't cancelled.

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
    // TODO: wire to real GivingOrganization / ministry model
    @Published private(set) var isPendingGive: Bool = false

    // MARK: - Initiate Give

    /// Call this from the give button's tap handler in lieu of opening the external URL.
    ///
    /// - Parameters:
    ///   - ministryName: Display name of the org/ministry receiving the gift.
    ///   - orgId: Firestore document ID of the GivingOrganization.
    ///   - donationUrl: External URL to open after the undo window elapses (if not cancelled).
    func initiateGive(
        ministryName: String,      // TODO: wire to real GivingOrganization
        orgId: String,             // TODO: wire to real GivingOrganization.id
        donationUrl: URL?          // TODO: wire to real GivingOrganization.donationUrl
    ) {
        // Capture for use in closures
        var cancellationTask: Task<Void, Never>?
        var wasCancelled = false

        AmenNotifications.fire(NotifContext(
            action: .give,
            actorName: ministryName,
            toneColors: (Color(hex: "#C9A84C"), Color(hex: "#F4D03F")),
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
                    // TODO: replace with native StoreKit / Stripe charge when available.
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
