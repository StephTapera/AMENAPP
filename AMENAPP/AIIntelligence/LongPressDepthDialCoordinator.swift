// LongPressDepthDialCoordinator.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 2)
//
// Manages DepthDialState for the long-press context.
// Bridges BereanIntentSwitchService with the depth dial so the auto-selected
// depth seeds the dial on first open, and manual overrides are persisted per-thread.
//
// Adaptive reach: records on-device tap frequency to inform thumb-zone migration.
// Records are stored only on-device, user-resettable, and never exported.

import Foundation
import Combine

@MainActor
final class LongPressDepthDialCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var dialState: DepthDialState

    // MARK: - Private Storage

    private let context: BereanObjectContext

    /// Per-thread depth override, persisted across sessions.
    /// Key: "lp_depth_<threadId>"
    private var overrideStorageKey: String {
        "lp_depth_\(dialState.threadId)"
    }

    /// Per-action adaptive reach records.
    /// Key: "lp_reach_<objectType>_<actionId>"
    private func reachStorageKey(actionId: String, objectType: LongPressObjectType) -> String {
        "lp_reach_\(objectType.rawValue)_\(actionId)"
    }

    // MARK: - Init

    init(context: BereanObjectContext) {
        self.context = context

        // Propose (mode × depth) from IntentSwitch using the payload text and thread ID.
        let proposal = BereanIntentSwitchService.shared.propose(
            for: context.payloadText ?? "",
            threadId: context.objectId
        )

        // If there is a persisted manual override for this thread, restore it.
        let storedOverrideKey = "lp_depth_\(context.objectId)"
        let storedRaw = UserDefaults.standard.string(forKey: storedOverrideKey)
        let restoredOverride = storedRaw.flatMap { BereanDepth(rawValue: $0) }

        self.dialState = DepthDialState(
            autoSelectedDepth: proposal.depth,
            manualOverride: restoredOverride,
            threadId: context.objectId
        )
    }

    // MARK: - Override Depth

    /// Sets a manual override on the dial and persists it for this thread.
    /// The effective depth becomes the override immediately.
    func overrideDepth(_ depth: BereanDepth) {
        dialState = DepthDialState(
            autoSelectedDepth: dialState.autoSelectedDepth,
            manualOverride: depth,
            threadId: dialState.threadId
        )
        // Persist the override so it survives session restarts for this thread.
        UserDefaults.standard.set(depth.rawValue, forKey: overrideStorageKey)
    }

    // MARK: - Reset to Auto

    /// Clears the manual override and restores the auto-selected depth.
    func resetToAuto() {
        dialState = DepthDialState(
            autoSelectedDepth: dialState.autoSelectedDepth,
            manualOverride: nil,
            threadId: dialState.threadId
        )
        UserDefaults.standard.removeObject(forKey: overrideStorageKey)
    }

    // MARK: - Adaptive Reach

    /// Records a tap for adaptive thumb-reach learning.
    /// On-device only; user-resettable; never exported.
    func recordTap(actionId: String, objectType: LongPressObjectType) {
        guard AMENFeatureFlags.shared.longPressAdaptiveReachEnabled else { return }

        let key = reachStorageKey(actionId: actionId, objectType: objectType)
        var record: AdaptiveReachRecord

        if let data = UserDefaults.standard.data(forKey: key),
           let existing = try? JSONDecoder().decode(AdaptiveReachRecord.self, from: data) {
            // Increment existing record.
            record = AdaptiveReachRecord(
                actionId: existing.actionId,
                objectType: existing.objectType,
                tapCount: existing.tapCount + 1,
                lastTappedAt: Date().timeIntervalSince1970,
                privacyZone: .functional
            )
        } else {
            // First tap for this action × type pair.
            record = AdaptiveReachRecord(
                actionId: actionId,
                objectType: objectType,
                tapCount: 1,
                lastTappedAt: Date().timeIntervalSince1970,
                privacyZone: .functional
            )
        }

        // Invariant: privacyZone is always .functional (lowest viable).
        guard record.privacyZone == .functional else {
            dlog("[LongPressDepthDialCoordinator][GUARDIAN] Adaptive reach record privacy zone violation — discarding.")
            return
        }

        if let encoded = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
