import CoreMotion
import SwiftUI

@MainActor
final class HeroMotionProxy: ObservableObject {
    @Published var offsetX: CGFloat = 0
    @Published var offsetY: CGFloat = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion, let self else { return }
            let roll = max(-0.14, min(0.14, CGFloat(motion.attitude.roll)))
            let pitch = max(-0.14, min(0.14, CGFloat(motion.attitude.pitch)))
            let scale: CGFloat = 57.14 // maps ±0.14 rad to ±8 pt
            self.offsetX = -roll * scale
            self.offsetY = -pitch * scale
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        offsetX = 0
        offsetY = 0
    }
}
