import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class PostActionReflectionService: ObservableObject {
    static let shared = PostActionReflectionService()

    @Published var pendingReflection: PostActionReflection?

    private let db = Firestore.firestore()

    private init() {}

    func triggerReflection(for actionId: String, actionType: ReflectionActionType) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        pendingReflection = PostActionReflection(
            id: nil,
            userId: uid,
            sourceActionId: actionId,
            actionType: actionType,
            intentBefore: nil,
            outcomeReflection: nil,
            lessonLearned: nil,
            completedAt: nil
        )
    }

    func saveReflection(_ reflection: PostActionReflection) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let r = PostActionReflection(
            id: reflection.id,
            userId: uid,
            sourceActionId: reflection.sourceActionId,
            actionType: reflection.actionType,
            intentBefore: reflection.intentBefore,
            outcomeReflection: reflection.outcomeReflection,
            lessonLearned: reflection.lessonLearned,
            completedAt: Date()
        )

        do {
            _ = try db.collection("users").document(uid)
                .collection("postActionReflections").addDocument(from: r)
            pendingReflection = nil

            // Notify backend to update growth pattern (fire and forget)
            let callable = Functions.functions().httpsCallable("savePostActionReflection")
            _ = try? await callable.call([
                "sourceActionId": r.sourceActionId,
                "actionType": r.actionType.rawValue
            ])
        } catch {
            dlog("⚠️ PostActionReflectionService.saveReflection: \(error)")
        }
    }

    func dismissReflection() {
        pendingReflection = nil
    }
}
