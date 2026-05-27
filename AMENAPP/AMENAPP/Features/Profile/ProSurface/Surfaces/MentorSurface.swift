import Foundation
import FirebaseFirestore

// MARK: - MentorSurface

struct MentorSurface: ProRoleSurface {
    let role: ProRole = .mentor
    let priority: Int = 10

    func currentInsight(for userId: String) async -> ProInsight? {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("mentorCheckIns")
                .whereField("mentorId", isEqualTo: userId)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            let count = snapshot.documents.count

            if count > 0 {
                let noun = count == 1 ? "person" : "people"
                return ProInsight(
                    line: "\(count) \(noun) waiting for a check-in",
                    deepLinkPath: "amen://mentor-hub"
                )
            } else {
                return ProInsight(
                    line: "No new check-ins this week",
                    deepLinkPath: "amen://mentor-hub"
                )
            }
        } catch {
            return nil
        }
    }
}
