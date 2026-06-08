import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

struct CommunityCorrection: Identifiable {
    let id: String
    let postId: String
    let text: String
    let sourceURL: String?
    let submittedBy: String
    let upvotes: Int
    let isAccepted: Bool
}

@MainActor final class CommunityCorrectionService: ObservableObject {
    static let shared = CommunityCorrectionService()
    private init() {}

    private let db = Firestore.firestore()

    func submitCorrection(for postId: String, correctionText: String, sourceURL: String?) async throws {
        guard AMENFeatureFlags.shared.communityCorrectionEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        dlog("[CommunityCorrectionService] submitCorrection postId=\(postId)")
        var data: [String: Any] = [
            "postId": postId,
            "text": correctionText,
            "submittedBy": uid,
            "upvotes": 0,
            "isAccepted": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let url = sourceURL { data["sourceURL"] = url }
        do {
            try await db.collection("posts").document(postId).collection("corrections").addDocument(data: data)
        } catch {
            dlog("[CommunityCorrectionService] submitCorrection error: \(error)")
            throw error
        }
    }

    func fetchCorrections(for postId: String) async throws -> [CommunityCorrection] {
        guard AMENFeatureFlags.shared.communityCorrectionEnabled else { return [] }
        dlog("[CommunityCorrectionService] fetchCorrections postId=\(postId)")
        do {
            let snapshot = try await db.collection("posts").document(postId)
                .collection("corrections")
                .order(by: "upvotes", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { doc -> CommunityCorrection? in
                let d = doc.data()
                guard let text = d["text"] as? String,
                      let submittedBy = d["submittedBy"] as? String else { return nil }
                return CommunityCorrection(
                    id: doc.documentID,
                    postId: postId,
                    text: text,
                    sourceURL: d["sourceURL"] as? String,
                    submittedBy: submittedBy,
                    upvotes: d["upvotes"] as? Int ?? 0,
                    isAccepted: d["isAccepted"] as? Bool ?? false
                )
            }
        } catch {
            dlog("[CommunityCorrectionService] fetchCorrections error: \(error)")
            throw error
        }
    }

    func voteOnCorrection(correctionId: String, upvote: Bool) async throws {
        guard AMENFeatureFlags.shared.communityCorrectionEnabled else { return }
        dlog("[CommunityCorrectionService] voteOnCorrection id=\(correctionId) upvote=\(upvote)")
        let payload: [String: Any] = ["correctionId": correctionId, "upvote": upvote]
        do {
            try await Functions.functions().httpsCallable("voteOnCommunityCorrection").call(payload)
        } catch {
            dlog("[CommunityCorrectionService] voteOnCorrection error: \(error)")
            throw error
        }
    }
}
