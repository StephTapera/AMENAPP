import CoreHaptics

@MainActor
final class BereanHapticCoordinator {
    static let shared = BereanHapticCoordinator()
    private var engine: CHHapticEngine?
    private init() {}

    func fireSentencePulse() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        ensureEngine()
        guard let engine else { return }
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.38)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08)
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: 0,
            duration: 0.01
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private func ensureEngine() {
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.engine = nil }
            }
        }
        try? engine?.start()
    }
}
