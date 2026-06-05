// DiscussionContextEngine.swift — AMEN App
import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class DiscussionContextEngine {
    static let shared = DiscussionContextEngine()
    private init() {}
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    var isEnabled: Bool { AMENFeatureFlags.shared.contextParticipationEnabled }

    func reportReadProgress(_ report: ReadProgressReport) async {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let callable = functions.httpsCallable("updateReadProgress")
        _ = try? await callable.call(["postId": report.postId, "uid": uid, "readFraction": report.fraction])
    }

    func reportAudioProgress(_ report: AudioProgressReport) async {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let callable = functions.httpsCallable("updateAudioProgress")
        _ = try? await callable.call(["postId": report.postId, "uid": uid, "audioFraction": report.fraction])
    }

    func reportCarouselProgress(_ report: CarouselProgressReport) async {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let callable = functions.httpsCallable("updateCarouselProgress")
        _ = try? await callable.call([
            "postId": report.postId, "uid": uid,
            "viewedSlides": report.viewed, "totalSlides": report.total
        ])
    }

    func getContextScore(postId: String) async -> ContextScore {
        guard isEnabled else { return ContextScore(score: 100, level: .full) }
        guard let uid = Auth.auth().currentUser?.uid else { return ContextScore(score: 100, level: .full) }
        let callable = functions.httpsCallable("getContextScore")
        guard let result = try? await callable.call(["postId": postId, "uid": uid]),
              let data = result.data as? [String: Any],
              let score = data["score"] as? Int else {
            return ContextScore(score: 100, level: .full)
        }
        return ContextScore(score: score, level: ContextLevel.from(score: score))
    }
}
