import Foundation
import FirebaseFirestore
import FirebaseAuth

// Manages the one-time "A new caption with every swipe" education modal.
// Reads/writes users/{uid}/settings/mediaCaptionEducation.
@MainActor
final class MediaCaptionEducationService {
    static let shared = MediaCaptionEducationService()
    private let db = Firestore.firestore()

    // Session-level guard: once seen in a session, don't re-check Firestore
    private var seenInSession = false

    private init() {}

    func hasSeenEducation(uid: String) async -> Bool {
        if seenInSession { return true }
        do {
            let doc = try await db
                .collection("users").document(uid)
                .collection("settings").document("mediaCaptionEducation")
                .getDocument()
            let seen = doc.data()?["seen"] as? Bool ?? false
            if seen { seenInSession = true }
            return seen
        } catch {
            // Fail open — don't block post creation on read failure
            return false
        }
    }

    func markSeen(uid: String) async {
        seenInSession = true
        do {
            try await db
                .collection("users").document(uid)
                .collection("settings").document("mediaCaptionEducation")
                .setData([
                    "seen": true,
                    "seenAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            // Non-fatal — log for observability but don't surface to user
        }
    }
}
