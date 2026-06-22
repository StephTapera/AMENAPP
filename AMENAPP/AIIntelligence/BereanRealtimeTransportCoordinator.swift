import Foundation

@MainActor
final class BereanRealtimeTransportCoordinator {
    static let shared = BereanRealtimeTransportCoordinator()

    // Release gate markers: supportsNativeWebRTC: false, supportsWebSocketFallback: true.
    static let supportsNativeWebRTC = false
    static let supportsWebSocketFallback = true

    var webSocketFallback: BereanRealtimeWebSocketTransport {
        BereanRealtimeWebSocketTransport()
    }

    func makeTransport() -> BereanRealtimeWebSocketTransport {
        webSocketFallback
    }
}
