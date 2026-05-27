// AmenCarPlaySceneDelegate.swift
// AMEN — Berean Drive CarPlay
//
// CarPlay scene delegate — the entry point for all CarPlay lifecycle events.
// Registered in Info.plist under CPTemplateApplicationSceneSessionRoleApplication.
//
// Feature flag gating:
//   AMENFeatureFlags.shared.carPlayBereanEnabled must be true at connect time.
//   If false, the scene connects with a single "unavailable" list item and
//   logs the flag block — no crash, no partial UI.
//
// Entitlement requirement (NOT automatically granted):
//   com.apple.developer.carplay-audio      (required for CPNowPlayingTemplate)
//   com.apple.developer.carplay-communication (required for CPMessageListItem)
//   Both must be requested at https://developer.apple.com/contact/request/carplay
//   and added to your provisioning profile + entitlements file before shipping.
//
//   Without these entitlements the app will NOT appear in CarPlay on a real vehicle.
//   This scene delegate is safe to ship in the binary — it gracefully no-ops if
//   the entitlement is absent and the CarPlay scene is never connected.

import CarPlay
import UIKit

@MainActor
final class AmenCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var coordinator: BereanCarPlayCoordinator?
    private var interfaceController: CPInterfaceController?

    // MARK: - Scene Connected

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        dlog("🚗 [CarPlay] Scene connected")

        let flags = AMENFeatureFlags.shared

        guard flags.carPlayBereanEnabled else {
            dlog("🚩 [CarPlay] Feature flag disabled — showing unavailable screen")
            AMENAnalyticsService.shared.logCarPlay(.featureFlagBlocked, parameters: ["feature": "carplay_berean"])
            showUnavailableTemplate(in: interfaceController, reason: "Coming soon to Amen.")
            return
        }

        // Stand up the coordinator — it owns all services for this session
        let coord = BereanCarPlayCoordinator(interfaceController: interfaceController)
        self.coordinator = coord
        coord.start()
    }

    // MARK: - Scene Disconnected

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        dlog("🚗 [CarPlay] Scene disconnected")
        coordinator?.end()
        coordinator = nil
        self.interfaceController = nil
    }

    // MARK: - Unavailable Fallback

    private func showUnavailableTemplate(in interfaceController: CPInterfaceController, reason: String) {
        let item = CPListItem(text: "Berean Drive", detailText: reason)
        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Amen", sections: [section])
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }
}
