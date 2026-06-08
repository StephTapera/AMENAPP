import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

struct AlgorithmSignal {
    let factor: String
    let weight: Double
    let description: String
}

struct AlgorithmExplanation {
    let postId: String
    let signals: [AlgorithmSignal]
    let humanReadableSummary: String
}

@MainActor final class AlgorithmTransparencyService: ObservableObject {
    static let shared = AlgorithmTransparencyService()
    private init() {}

    private var explanationCache: [String: AlgorithmExplanation] = [:]

    func fetchExplanation(for postId: String) async throws -> AlgorithmExplanation {
        guard AMENFeatureFlags.shared.algorithmTransparencyEnabled else {
            return AlgorithmExplanation(
                postId: postId,
                signals: [],
                humanReadableSummary: "Algorithm transparency is currently unavailable."
            )
        }
        if let cached = explanationCache[postId] {
            dlog("[AlgorithmTransparencyService] cache hit postId=\(postId)")
            return cached
        }
        dlog("[AlgorithmTransparencyService] fetchExplanation postId=\(postId)")
        let payload: [String: Any] = ["postId": postId]
        do {
            let result = try await Functions.functions().httpsCallable("getAlgorithmExplanation").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "AlgorithmTransparency", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let summary = data["humanReadableSummary"] as? String ?? ""
            let signalDicts = data["signals"] as? [[String: Any]] ?? []
            let signals: [AlgorithmSignal] = signalDicts.compactMap { dict in
                guard let factor = dict["factor"] as? String,
                      let weight = dict["weight"] as? Double,
                      let description = dict["description"] as? String else { return nil }
                return AlgorithmSignal(factor: factor, weight: weight, description: description)
            }
            let explanation = AlgorithmExplanation(postId: postId, signals: signals, humanReadableSummary: summary)
            explanationCache[postId] = explanation
            return explanation
        } catch {
            dlog("[AlgorithmTransparencyService] fetchExplanation error: \(error)")
            throw error
        }
    }
}
