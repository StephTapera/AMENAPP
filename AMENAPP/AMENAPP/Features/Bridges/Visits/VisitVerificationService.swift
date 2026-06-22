import Foundation

struct PendingVisitConfirmation: Identifiable, Equatable {
    let id: String
    let churchId: String
    let churchName: String
    let detectedAt: Date

    init(
        id: String = UUID().uuidString,
        churchId: String,
        churchName: String,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.churchId = churchId
        self.churchName = churchName
        self.detectedAt = detectedAt
    }
}

@MainActor
final class VisitVerificationService: ObservableObject {
    static let shared = VisitVerificationService()

    @Published var pendingVisitConfirmation: PendingVisitConfirmation?

    private init() {}

    func requestConfirmation(churchId: String, churchName: String) {
        pendingVisitConfirmation = PendingVisitConfirmation(
            churchId: churchId,
            churchName: churchName
        )
    }

    func dismissVisit() {
        pendingVisitConfirmation = nil
    }

    func confirmVisit(_ visit: PendingVisitConfirmation) async {
        // The server-backed visit ledger can subscribe here when the geofence bridge is wired.
        if pendingVisitConfirmation?.id == visit.id {
            pendingVisitConfirmation = nil
        }
    }
}
