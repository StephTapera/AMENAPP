import Foundation

final class BereanRealtimeTransportCoordinator {
    static let shared = BereanRealtimeTransportCoordinator()

    func makeTransport() -> BereanRealtimeWebSocketTransport {
        BereanRealtimeWebSocketTransport()
    }
}
