import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProofOfHumanService: ObservableObject {

    static let shared = ProofOfHumanService()
    @Published private(set) var currentScore: ProofOfHumanScore?
    private let db = Firestore.firestore()
    private var cache: [String: (score: ProofOfHumanScore, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600

    private init() {}

    func getScore(for userId: String) async -> ProofOfHumanScore? {
        guard AMENFeatureFlags.shared.proofOfHumanEnabled else { return nil }
        if let cached = cache[userId], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.score
        }
        do {
            let doc = try await db.collection("users").document(userId).collection("trust").document("humanScore").getDocument()
            if let score = try? doc.data(as: ProofOfHumanScore.self) {
                cache[userId] = (score, Date())
                if userId == Auth.auth().currentUser?.uid {
                    currentScore = score
                }
                return score
            }
        } catch {
            dlog("[ProofOfHumanService] fetch failed: \(error.localizedDescription)")
        }
        return nil
    }
}
