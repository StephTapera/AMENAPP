// TransportCoordinatorService.swift — AMEN IntegrationOS
// Actor that deep-links to Uber/Lyft and manages carpool requests.

import Foundation
import MapKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

actor TransportCoordinatorService {
    static let shared = TransportCoordinatorService()
    private init() {}

    private let db = Firestore.firestore()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_transport_enabled").boolValue }

    // MARK: - Deep Link to Rideshare

    func openRideshare(provider: TransportProvider, destination: MKMapItem) async {
        guard isEnabled else { return }
        await MainActor.run {
            let coord = destination.placemark.coordinate
            var urlString: String
            switch provider {
            case .uber:
                urlString = "uber://?action=setPickup&dropoff[latitude]=\(coord.latitude)&dropoff[longitude]=\(coord.longitude)&dropoff[nickname]=\(destination.name?.urlEncoded ?? "Destination")"
            case .lyft:
                urlString = "lyft://ridetype?id=lyft&destination[latitude]=\(coord.latitude)&destination[longitude]=\(coord.longitude)"
            case .appleMaps:
                destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                return
            }
            guard let url = URL(string: urlString) else { return }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                UIApplication.shared.open(provider.appStoreURL)
            }
        }
    }

    // MARK: - Carpool Requests

    func postCarpoolRequest(
        churchId: String,
        departureCoordinate: GeoPoint,
        departureTime: Date,
        seats: Int,
        notes: String?
    ) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        let request = CarpoolRequest(
            requesterId: uid,
            churchId: churchId,
            departureCoordinate: departureCoordinate,
            departureTime: departureTime,
            seats: seats,
            notes: notes,
            status: .open,
            createdAt: Date()
        )
        try db.collection("carpoolRequests").document(request.id).setData(from: request)
    }

    func fetchCarpoolRequests(for churchId: String) async throws -> [CarpoolRequest] {
        guard isEnabled else { return [] }
        let snapshot = try await db.collection("carpoolRequests")
            .whereField("churchId", isEqualTo: churchId)
            .whereField("status", isEqualTo: CarpoolStatus.open.rawValue)
            .order(by: "departureTime")
            .limit(to: 20)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: CarpoolRequest.self) }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
