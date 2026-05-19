import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class MomentInterceptionService: ObservableObject {
    static let shared = MomentInterceptionService()

    @Published var shouldShowOverlay = false
    @Published var currentTrigger: MomentTriggerType?
    @Published var currentRiskScore: Double = 0.0

    private let db = Firestore.firestore()
    // Throttle: only show overlay at most once per 3 minutes
    private var lastShownAt: Date?
    private let minimumIntervalSeconds: TimeInterval = 180

    private init() {}

    // Call from composer view — throttled client-side evaluation
    func evaluate(text: String, surface: String, typingBehavior: TypingBehavior) async {
        guard canShowOverlay() else { return }

        let triggers = detectTriggers(text: text, surface: surface, behavior: typingBehavior)
        guard !triggers.isEmpty else { return }

        let riskScore = Double(triggers.count) / 5.0

        // Only intercept when risk is meaningful
        guard riskScore > 0.4 else { return }

        do {
            let callable = Functions.functions().httpsCallable("evaluateMomentRisk")
            let result = try await callable.call([
                "textLength": text.count,
                "surface": surface,
                "triggers": triggers.map { $0.rawValue },
                "hourOfDay": Calendar.current.component(.hour, from: Date())
            ])

            if let data = result.data as? [String: Any],
               let serverRisk = data["riskScore"] as? Double,
               serverRisk > 0.5 {
                currentTrigger = triggers.first
                currentRiskScore = serverRisk
                shouldShowOverlay = true
                lastShownAt = Date()
            }
        } catch {
            // Client fallback
            if riskScore > 0.6 {
                currentTrigger = triggers.first
                currentRiskScore = riskScore
                shouldShowOverlay = true
                lastShownAt = Date()
            }
        }
    }

    func recordUserAction(_ action: MomentUserAction, triggerType: MomentTriggerType, source: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let event = MomentInterceptionEvent(
            id: nil,
            userId: uid,
            triggerType: triggerType,
            sourceSurface: source,
            riskScore: currentRiskScore,
            userAction: action
        )

        do {
            _ = try db.collection("users").document(uid)
                .collection("momentInterceptions").addDocument(from: event)
        } catch {
            dlog("⚠️ MomentInterceptionService.recordUserAction: \(error)")
        }

        shouldShowOverlay = false
        currentTrigger = nil
    }

    func dismissOverlay() {
        shouldShowOverlay = false
        currentTrigger = nil
    }

    // MARK: - Private

    private func canShowOverlay() -> Bool {
        guard let last = lastShownAt else { return true }
        return Date().timeIntervalSince(last) > minimumIntervalSeconds
    }

    private func detectTriggers(text: String, surface: String, behavior: TypingBehavior) -> [MomentTriggerType] {
        var triggers: [MomentTriggerType] = []
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 22 || hour <= 4 { triggers.append(.lateNightPosting) }
        if behavior.wordsPerMinute > 120 { triggers.append(.rapidTyping) }
        if behavior.deleteRewriteCount > 3 { triggers.append(.repeatedDeleteRewrite) }

        let lowered = text.lowercased()
        let angerWords = ["furious", "outraged", "how dare", "unbelievable", "disgusting", "shameful"]
        if angerWords.contains(where: { lowered.contains($0) }) { triggers.append(.highAngerScore) }

        let manipulationWords = ["god told me", "if you were really christian", "you have to", "the bible says you must"]
        if manipulationWords.contains(where: { lowered.contains($0) }) { triggers.append(.spiritualManipulationRisk) }

        return triggers
    }
}

// Passed in from the composer view
struct TypingBehavior {
    var wordsPerMinute: Double
    var deleteRewriteCount: Int
}
