import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class CommunityDiscernmentService: ObservableObject {
    static let shared = CommunityDiscernmentService()

    private let db = Firestore.firestore()

    private init() {}

    // Submit an anonymous signal (type only, no identifying data)
    func submitSignal(contentId: String, signalType: DiscernmentSignalType) async {
        guard Auth.auth().currentUser != nil else { return }

        do {
            let callable = Functions.functions().httpsCallable("aggregateDiscernmentSignals")
            _ = try await callable.call([
                "contentId": contentId,
                "signalType": signalType.rawValue
            ])
        } catch {
            dlog("⚠️ CommunityDiscernmentService.submitSignal: \(error)")
        }
    }

    // Fetch threshold-met signals for a content item (no user IDs exposed)
    func fetchSignals(for contentId: String) async -> [CommunityDiscernmentSignal] {
        do {
            let snapshot = try await db.collection("contentDiscernmentAggregates")
                .document(contentId)
                .collection("signals")
                .whereField("thresholdMet", isEqualTo: true)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: CommunityDiscernmentSignal.self) }
        } catch {
            return []
        }
    }

    // Request a Berean AI summary for confusing content (community-driven)
    func requestBereanSummary(contentId: String) async -> String? {
        do {
            let callable = Functions.functions().httpsCallable("generateCommunityDiscernmentSummary")
            let result = try await callable.call(["contentId": contentId])
            if let data = result.data as? [String: Any] {
                return data["summary"] as? String
            }
        } catch {
            dlog("⚠️ CommunityDiscernmentService.requestBereanSummary: \(error)")
        }
        return nil
    }
}
