import Foundation
import FirebaseFirestore

// MARK: - ChurchSurface

struct ChurchSurface: ProRoleSurface {
    let role: ProRole = .church
    let priority: Int = 40

    private let roleFlags: ProfileRoleFlags

    init(roleFlags: ProfileRoleFlags) {
        self.roleFlags = roleFlags
    }

    func currentInsight(for userId: String) async -> ProInsight? {
        guard let churchId = roleFlags.churchId, !churchId.isEmpty else {
            return nil
        }

        do {
            let docRef = Firestore.firestore()
                .collection("churches")
                .document(churchId)
                .collection("attendance")
                .document("latest")

            let snapshot = try await docRef.getDocument()

            if snapshot.exists, let data = snapshot.data() {
                let totalCount = data["totalCount"] as? Int ?? 0
                let newArrivals = data["newArrivals"] as? Int ?? 0
                return ProInsight(
                    line: "Sunday attendance: \(totalCount) — \(newArrivals) new this week",
                    deepLinkPath: "amen://church-hub/\(churchId)"
                )
            } else {
                return ProInsight(
                    line: "Track your congregation's growth",
                    deepLinkPath: "amen://church-hub"
                )
            }
        } catch {
            return nil
        }
    }
}
