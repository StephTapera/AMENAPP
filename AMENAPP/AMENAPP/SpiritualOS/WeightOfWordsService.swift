import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class WeightOfWordsService: ObservableObject {
    static let shared = WeightOfWordsService()

    @Published var currentScore: WeightOfWordsScore?
    @Published var isScoring = false

    private init() {}

    func score(text: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isScoring = true
        defer { isScoring = false }

        do {
            let callable = Functions.functions().httpsCallable("scoreWeightOfWords")
            let result = try await callable.call(["text": text])

            if let data = result.data as? [String: Any],
               let labelRaw = data["scoreLabel"] as? String,
               let label = WordWeightLabel(rawValue: labelRaw) {
                let flagStrings = (data["flags"] as? [String] ?? []).compactMap { WordWeightFlag(rawValue: $0) }
                currentScore = WeightOfWordsScore(
                    id: nil,
                    userId: uid,
                    sourceText: text,
                    scoreLabel: label,
                    scoreValue: data["scoreValue"] as? Double ?? 0.5,
                    flags: flagStrings,
                    suggestedRewrite: data["suggestedRewrite"] as? String
                )
            }
        } catch {
            // Client fallback: neutral score
            currentScore = WeightOfWordsScore(
                id: nil, userId: uid, sourceText: text,
                scoreLabel: .light, scoreValue: 0.3, flags: [],
                suggestedRewrite: nil
            )
        }
    }

    func generateGracefulRewrite(for text: String) async -> String? {
        do {
            let callable = Functions.functions().httpsCallable("generateGracefulRewrite")
            let result = try await callable.call(["text": text])
            if let data = result.data as? [String: Any] {
                return data["rewrite"] as? String
            }
        } catch {
            dlog("⚠️ WeightOfWordsService.generateGracefulRewrite: \(error)")
        }
        return nil
    }

    func dismiss() { currentScore = nil }
}
