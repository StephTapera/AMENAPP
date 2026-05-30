import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// Detects when multiple Amen users are at the same event or location,
// then offers to create ephemeral live spaces for shared content.
@MainActor
final class SmartGatheringDetectionService: ObservableObject {
    static let shared = SmartGatheringDetectionService()

    @Published private(set) var detectedNearbyGatherings: [NearbyGathering] = []
    @Published private(set) var activeEphemeralSpaces: [EphemeralLiveSpace] = []
    @Published private(set) var isDetecting = false

    private lazy var db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")
    private var spacesListener: ListenerRegistration?

    private init() {}

    // Detect nearby gatherings for the user's broad area
    func detectNearbyGatherings(broadArea: String) async {
        guard !broadArea.isEmpty else { return }
        isDetecting = true
        defer { isDetecting = false }

        do {
            let result = try await functions.httpsCallable("detectNearbyGatherings").call([
                "broadArea": broadArea,
                "limit": 5
            ])
            guard let data = result.data as? [String: Any],
                  let rows = data["gatherings"] as? [[String: Any]] else { return }

            detectedNearbyGatherings = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let typeString = row["type"] as? String,
                      let type = AmenGatheringType(rawValue: typeString),
                      let broadLoc = row["broadLocation"] as? String else { return nil }
                return NearbyGathering(
                    id: id,
                    type: type,
                    broadLocation: broadLoc,
                    participantCount: row["participantCount"] as? Int ?? 0,
                    isOpenToJoin: row["isOpenToJoin"] as? Bool ?? true,
                    title: row["title"] as? String ?? type.displayName,
                    startsAt: nil,
                    isAnonymized: true
                )
            }
        } catch {
            detectedNearbyGatherings = []
        }
    }

    // Create a temporary live space for a detected gathering
    func createEphemeralSpace(for gathering: NearbyGathering) async throws -> EphemeralLiveSpace {
        guard let uid = Auth.auth().currentUser?.uid else { throw EphemeralSpaceError.notAuthenticated }

        let result = try await functions.httpsCallable("createEphemeralLiveSpace").call([
            "gatheringId": gathering.id,
            "title": gathering.title,
            "broadLocation": gathering.broadLocation,
            "creatorUID": uid
        ])

        guard let data = result.data as? [String: Any],
              let id = data["spaceId"] as? String else {
            throw EphemeralSpaceError.creationFailed
        }

        let space = EphemeralLiveSpace(
            id: id,
            title: gathering.title,
            triggerEnvironment: gathering.type.rawValue,
            broadLocation: gathering.broadLocation,
            memberUIDs: [uid],
            isActive: true,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(6 * 3600),
            postCount: 0,
            hasDiscussion: true,
            hasMediaPool: true
        )
        activeEphemeralSpaces.insert(space, at: 0)
        return space
    }

    func startListeningForActiveSpaces(broadArea: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        spacesListener = db.collection("ephemeral_spaces")
            .whereField("memberUIDs", arrayContains: uid)
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                Task { @MainActor in
                    self.activeEphemeralSpaces = docs.compactMap {
                        try? Firestore.Decoder().decode(EphemeralLiveSpace.self, from: $0.data())
                    }
                    .filter { !$0.isExpired }
                }
            }
    }

    func stopListening() {
        spacesListener?.remove()
        spacesListener = nil
    }

    deinit {
        spacesListener?.remove()
    }
}

enum EphemeralSpaceError: LocalizedError {
    case notAuthenticated
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in to create a shared space."
        case .creationFailed:   return "Could not create the shared space."
        }
    }
}
