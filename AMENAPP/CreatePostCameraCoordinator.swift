import Foundation
import SwiftUI
import UIKit

@MainActor
final class CreatePostCameraCoordinator: ObservableObject {
    @Published var isPresentingCamera = false
    @Published var attachedWitnessMedia: WitnessDraftAttachment?
    @Published var pendingErrorMessage: String?
    @Published var shouldRestoreFocusAfterDismiss = false

    private var restoreFocusOnDismiss = false

    func openCamera(restoreComposerFocus: Bool) {
        restoreFocusOnDismiss = restoreComposerFocus
        shouldRestoreFocusAfterDismiss = false
        isPresentingCamera = true
        WitnessCameraAnalytics.track("camera_opened", parameters: nil)
    }

    func dismissCamera() {
        isPresentingCamera = false
        if restoreFocusOnDismiss {
            shouldRestoreFocusAfterDismiss = true
        }
        restoreFocusOnDismiss = false
    }

    func clearRestoreRequest() {
        shouldRestoreFocusAfterDismiss = false
    }

    func attachCapturedMediaToDraft(_ attachment: WitnessDraftAttachment) {
        attachedWitnessMedia = attachment
        isPresentingCamera = false
        if restoreFocusOnDismiss {
            shouldRestoreFocusAfterDismiss = true
        }
        restoreFocusOnDismiss = false
    }

    func restoreDraftAttachment(_ attachment: WitnessDraftAttachment?) {
        attachedWitnessMedia = attachment
    }

    func removeAttachedMedia() {
        if let attachedWitnessMedia {
            WitnessMediaComposer.removeLocalAssets(for: attachedWitnessMedia)
        }
        attachedWitnessMedia = nil
    }

    func handleFailure(_ error: Error) {
        pendingErrorMessage = error.localizedDescription
        WitnessCameraAnalytics.track("witness_publish_failed", parameters: [
            "reason": error.localizedDescription
        ])
    }
}

enum WitnessCameraAnalytics {
    static func track(_ name: String, parameters: [String: Any]?) {
        dlog("📷 [WitnessCamera] \(name) \(parameters ?? [:])")
    }
}
