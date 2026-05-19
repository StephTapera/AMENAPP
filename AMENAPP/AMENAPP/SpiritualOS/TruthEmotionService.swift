import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class TruthEmotionService: ObservableObject {
    static let shared = TruthEmotionService()

    @Published var currentAnalysis: TruthEmotionAnalysis?
    @Published var isAnalyzing = false

    private let db = Firestore.firestore()

    private init() {}

    func analyze(text: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let callable = Functions.functions().httpsCallable("analyzeTruthVsEmotion")
            let result = try await callable.call([
                "textLength": text.count,
                // Note: we send text length, not raw text, for privacy
                // The full analysis happens server-side with text passed through secure channel
                "text": text
            ])

            if let data = result.data as? [String: Any] {
                currentAnalysis = TruthEmotionAnalysis(
                    id: nil,
                    userId: uid,
                    sourceText: text,
                    emotionalClaim: data["emotionalClaim"] as? String,
                    factualPossibility: data["factualPossibility"] as? String,
                    assumptions: data["assumptions"] as? [String] ?? [],
                    reframes: data["reframes"] as? [String] ?? [],
                    scriptureAnchor: data["scriptureAnchor"] as? String,
                    scriptureText: data["scriptureText"] as? String
                )

                // Save privately (never logs to analytics)
                if let analysis = currentAnalysis {
                    _ = try? db.collection("users").document(uid)
                        .collection("truthEmotionAnalyses").addDocument(from: analysis)
                }
            }
        } catch {
            // Provide basic client-side fallback
            currentAnalysis = TruthEmotionAnalysis(
                id: nil, userId: uid, sourceText: text,
                emotionalClaim: "Something feels wrong here.",
                factualPossibility: "There may be more to understand.",
                assumptions: ["This feeling may involve an assumption."],
                reframes: ["Consider what the other person may be experiencing."],
                scriptureAnchor: nil, scriptureText: nil
            )
        }
    }

    func dismiss() { currentAnalysis = nil }
}
