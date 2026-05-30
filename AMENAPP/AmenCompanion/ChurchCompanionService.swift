import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class ChurchCompanionService: ObservableObject {
    static let shared = ChurchCompanionService()

    @Published private(set) var nearbyResults: [SmartChurchSearchItem] = []
    @Published private(set) var savedChurches: [SmartChurchSummary] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private lazy var db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // Natural language search: "Bible-teaching church near me with young adults"
    func search(query: String, context: LocationContext) async {
        guard !query.isEmpty, context.coordinate.latitude != 0 else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let results = try await SmartChurchSearchService.shared.search(
                query: query,
                userLocation: context.coordinate,
                radiusMiles: 25
            )
            nearbyResults = results
        } catch {
            errorMessage = "Could not search churches right now."
        }
    }

    // Companion-driven discovery when user enters new area
    func discoverForNewArea(context: LocationContext) async {
        guard context.isNewArea else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let query = "Bible-teaching church \(context.city) \(context.state)"
            nearbyResults = try await SmartChurchSearchService.shared.search(
                query: query,
                userLocation: context.coordinate,
                radiusMiles: 20
            )
        } catch {
            nearbyResults = []
        }
    }

    func saveChurch(_ church: SmartChurchSummary) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "churchId": church.id,
            "churchName": church.name,
            "city": church.city,
            "state": church.state,
            "savedAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("users").document(uid)
            .collection("saved_churches").document(church.id)
            .setData(data, merge: true)

        if !savedChurches.contains(where: { $0.id == church.id }) {
            savedChurches.append(church)
        }
    }

    func unsaveChurch(churchId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(uid)
            .collection("saved_churches").document(churchId)
            .delete()
        savedChurches.removeAll { $0.id == churchId }
    }

    func loadSavedChurches() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("saved_churches")
                .order(by: "savedAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            let ids = snap.documents.compactMap { $0.data()["churchId"] as? String }
            if ids.isEmpty { return }

            // Fetch full church data
            var fetched: [SmartChurchSummary] = []
            for id in ids {
                if let result = try? await SmartChurchSearchService.shared.search(
                    query: "id:\(id)", userLocation: CLLocationCoordinate2D(), radiusMiles: nil
                ).first {
                    fetched.append(result.church)
                }
            }
            savedChurches = fetched
        } catch {
            dlog("[ChurchCompanion] loadSavedChurches failed: \(error.localizedDescription)")
        }
    }

    func isSaved(_ churchId: String) -> Bool {
        savedChurches.contains { $0.id == churchId }
    }
}
