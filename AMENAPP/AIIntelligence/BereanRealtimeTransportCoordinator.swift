import Foundation

enum BereanRealtimeTransportMode: String, Sendable {
    case webSocketFallback
}

struct BereanRealtimeTransportCapabilities: Sendable {
    let mode: BereanRealtimeTransportMode
    let supportsNativeWebRTC: Bool
    let supportsWebSocketFallback: Bool
}

final class BereanRealtimeTransportCoordinator {
    static let shared = BereanRealtimeTransportCoordinator()

    let capabilities = BereanRealtimeTransportCapabilities(
        mode: .webSocketFallback,
        supportsNativeWebRTC: false,
        supportsWebSocketFallback: true
    )

    func makeTransport() -> BereanRealtimeWebSocketTransport {
        BereanRealtimeWebSocketTransport()
    }
}
