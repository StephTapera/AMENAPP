import Foundation
import FirebaseAuth
import FirebaseFirestore

protocol CreatorAnalyticsServicing {
    func track(event: String, metadata: [String: String])
}

final class CreatorAnalyticsService: CreatorAnalyticsServicing {
    private let db = Firestore.firestore()

    func track(event: String, metadata: [String: String] = [:]) {
        guard let ownerID = Auth.auth().currentUser?.uid, !ownerID.isEmpty else { return }
        let dayKey = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let ref = db.collection("creatorUsageAnalytics").document(dayKey)
        ref.setData([
            "ownerID": ownerID,
            "lastEvent": event,
            "metadata": metadata,
            "updatedAt": Date()
        ], merge: true)
    }
}
