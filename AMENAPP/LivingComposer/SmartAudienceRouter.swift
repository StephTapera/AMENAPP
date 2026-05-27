import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class SmartAudienceRouter: ObservableObject {
    static let shared = SmartAudienceRouter()

    @Published private(set) var availableRoutes: [AudienceRoute] = [.personalFeed()]
    @Published private(set) var selectedRouteIds: Set<String> = ["personal_feed"]
    @Published private(set) var isLoadingSpaces = false

    private lazy var db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func loadAvailableRoutes(context: PostingContext, locationContext: LocationContext) async {
        isLoadingSpaces = true
        defer { isLoadingSpaces = false }

        let contextRoutes = ComposerContextEngine.shared.contextualAudienceRoutes
        var allRoutes = contextRoutes

        // Fetch user's community spaces from Firestore
        if let uid = Auth.auth().currentUser?.uid {
            let spaces = await fetchUserSpaces(uid: uid)
            for space in spaces {
                let route = AudienceRoute(
                    id: "space_\(space.id)",
                    type: .communitySpace,
                    label: space.name,
                    subtitle: "Your space",
                    selected: false,
                    score: 0.75
                )
                if !allRoutes.contains(where: { $0.id == route.id }) {
                    allRoutes.append(route)
                }
            }
        }

        availableRoutes = allRoutes.sorted { $0.score > $1.score }

        // Auto-select personal feed always
        selectedRouteIds = ["personal_feed"]
    }

    func toggleRoute(id: String) {
        if selectedRouteIds.contains(id) {
            if id != "personal_feed" { // can't deselect personal feed
                selectedRouteIds.remove(id)
            }
        } else {
            selectedRouteIds.insert(id)
        }
    }

    func selectRoute(id: String) {
        selectedRouteIds.insert(id)
    }

    var selectedRoutes: [AudienceRoute] {
        availableRoutes.filter { selectedRouteIds.contains($0.id) }
    }

    // Build the payload for a multi-destination post
    func buildPostingDestinations() -> [String: Any] {
        var destinations: [String: Any] = [:]
        for route in selectedRoutes {
            switch route.type {
            case .personalFeed:    destinations["personalFeed"] = true
            case .nearbyEvent:     destinations["nearbyEvent"] = route.id
            case .communitySpace:  destinations["spaces"] = (destinations["spaces"] as? [String] ?? []) + [route.id.replacingOccurrences(of: "space_", with: "")]
            case .churchSpace:     destinations["churchSpace"] = true
            case .creatorFollowers: destinations["creatorFeed"] = true
            case .local:           destinations["localDiscovery"] = route.id
            case .global:          destinations["globalDiscovery"] = true
            case .privateCircle:   destinations["privateCircle"] = route.id
            }
        }
        return destinations
    }

    private func fetchUserSpaces(uid: String) async -> [MinimalSpace] {
        do {
            let snap = try await db.collection("spaces")
                .whereField("memberUIDs", arrayContains: uid)
                .limit(to: 10)
                .getDocuments()
            return snap.documents.compactMap { doc in
                let data = doc.data()
                guard let name = data["name"] as? String else { return nil }
                return MinimalSpace(id: doc.documentID, name: name)
            }
        } catch {
            return []
        }
    }
}

private struct MinimalSpace {
    let id: String
    let name: String
}
