import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProofOfCareService: ObservableObject {

    static let shared = ProofOfCareService()
    @Published private(set) var currentScore: ProofOfCareScore?
    private let db = Firestore.firestore()
    private var cache: [String: (score: ProofOfCareScore, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600

    private init() {}

    func getScore(for userId: String) async -> ProofOfCareScore? {
        guard AMENFeatureFlags.shared.proofOfCareEnabled else { return nil }
        if let cached = cache[userId], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.score
        }
        do {
            let doc = try await db.collection("users").document(userId).collection("trust").document("careScore").getDocument()
            if let score = try? doc.data(as: ProofOfCareScore.self) {
                cache[userId] = (score, Date())
                if userId == Auth.auth().currentUser?.uid {
                    currentScore = score
                }
                return score
            }
        } catch {
            dlog("[ProofOfCareService] fetch failed: \(error.localizedDescription)")
        }
        return nil
    }
}
