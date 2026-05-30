import SwiftUI

// MARK: - AmenMediaVisibilityCoordinator
//
// Autoplay-on-scroll coordinator.
// Each media card reports its global-frame visibility;
// the coordinator picks the most-visible playable card (≥50% on screen)
// and asks AmenMediaPlaybackCoordinator to autoplay it muted.
//
// Respects:
//   • UserDefaults "amen.autoplayMedia" (default true)
//   • Low Power Mode (skips autoplay)
//   • One card plays app-wide (delegated to AmenMediaPlaybackCoordinator)

@MainActor
final class AmenMediaVisibilityCoordinator: ObservableObject {
    static let shared = AmenMediaVisibilityCoordinator()

    // Fraction (0–1) of each tracked card currently on screen.
    private var visibilityMap: [String: CGFloat] = [:]

    // Registered playable attachments, keyed by id.
    private var registeredAttachments: [String: AmenMediaAttachment] = [:]

    // Debounce task — prevents evaluating on every scroll pixel.
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Autoplay gating

    var autoplayEnabled: Bool {
        guard UserDefaults.standard.object(forKey: "amen.autoplayMedia") as? Bool ?? true
        else { return false }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        return true
    }

    // MARK: - Registration

    /// Register a playable attachment so the coordinator can autoplay it.
    /// Non-playable attachments are silently ignored.
    func register(attachment: AmenMediaAttachment) {
        guard attachment.playable != nil else { return }
        registeredAttachments[attachment.id] = attachment
    }

    func unregister(id: String) {
        registeredAttachments.removeValue(forKey: id)
        visibilityMap.removeValue(forKey: id)
    }

    // MARK: - Visibility Reporting

    /// Called by AmenMediaVisibilityModifier whenever a card's global frame changes.
    func report(id: String, frame: CGRect) {
        let fraction = visibleFraction(for: frame)
        let previous = visibilityMap[id] ?? 0
        visibilityMap[id] = fraction
        guard abs(fraction - previous) > 0.04 else { return }
        scheduleEvaluation()
    }

    // MARK: - Private

    private func scheduleEvaluation() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)  // 180 ms debounce
            guard !Task.isCancelled, let self else { return }
            self.evaluate()
        }
    }

    private func evaluate() {
        guard autoplayEnabled else { return }

        let playable = visibilityMap.filter { registeredAttachments[$0.key] != nil }

        guard let (topID, topFraction) = playable.max(by: { $0.value < $1.value }),
              topFraction >= 0.5 else {
            // Nothing sufficiently visible — pause if we started autoplay.
            let coordinator = AmenMediaPlaybackCoordinator.shared
            if coordinator.isPlaying {
                coordinator.pause()
            }
            return
        }

        let coordinator = AmenMediaPlaybackCoordinator.shared

        // Already playing the right card — nothing to do.
        if coordinator.activeAttachmentID == topID, coordinator.isPlaying { return }

        guard let attachment = registeredAttachments[topID] else { return }

        coordinator.setMuted(true)
        coordinator.play(attachment)
    }

    private func visibleFraction(for frame: CGRect) -> CGFloat {
        let screen = UIScreen.main.bounds
        let intersection = frame.intersection(screen)
        guard !intersection.isNull, frame.height > 0 else { return 0 }
        return min(1, intersection.height / frame.height)
    }
}
