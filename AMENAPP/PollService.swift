//
//  PollService.swift
//  AMENAPP
//
//  Feature 24: Interactive Polls — "Which scripture speaks to you today?"
//  Scripture polls, prayer topic votes, "Are you struggling with this too?"
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PollService: ObservableObject {
    static let shared = PollService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Models

    struct Poll: Identifiable, Codable {
        let id: String
        let postId: String
        let question: String
        let options: [PollOption]
        let totalVotes: Int
        let createdAt: Date
        let expiresAt: Date?
        var userVotedOptionId: String?

        var isExpired: Bool {
            guard let expires = expiresAt else { return false }
            return Date() > expires
        }
    }

    struct PollOption: Identifiable, Codable {
        let id: String
        let text: String
        var voteCount: Int
        let scriptureRef: String? // Optional scripture reference

        var percentage: Float {
            0 // Computed by caller with total
        }
    }

    // MARK: - Vote

    func vote(postId: String, optionId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Atomic transaction: increment vote count + record user vote
        let postRef = db.collection("posts").document(postId)

        try await db.runTransaction { transaction, _ in
            let doc = try transaction.getDocument(postRef)
            guard var pollData = doc.data()?["poll"] as? [String: Any],
                  var options = pollData["options"] as? [[String: Any]] else {
                return nil
            }

            // Check if already voted
            let voters = pollData["voters"] as? [String: String] ?? [:]
            guard voters[uid] == nil else { return nil } // Already voted

            // Increment the chosen option
            for i in 0..<options.count {
                if options[i]["id"] as? String == optionId {
                    let count = options[i]["voteCount"] as? Int ?? 0
                    options[i]["voteCount"] = count + 1
                }
            }

            let totalVotes = (pollData["totalVotes"] as? Int ?? 0) + 1

            pollData["options"] = options
            pollData["totalVotes"] = totalVotes

            var updatedVoters = voters
            updatedVoters[uid] = optionId
            pollData["voters"] = updatedVoters

            transaction.updateData(["poll": pollData], forDocument: postRef)
            return nil
        }
    }

    // MARK: - Create Poll on Post

    func attachPoll(
        to postId: String,
        question: String,
        options: [(text: String, scriptureRef: String?)],
        expiresIn: TimeInterval? = nil
    ) async throws {
        let pollOptions = options.map { option -> [String: Any] in
            var dict: [String: Any] = [
                "id": UUID().uuidString,
                "text": option.text,
                "voteCount": 0,
            ]
            if let ref = option.scriptureRef {
                dict["scriptureRef"] = ref
            }
            return dict
        }

        var pollData: [String: Any] = [
            "question": question,
            "options": pollOptions,
            "totalVotes": 0,
            "voters": [:],
            "createdAt": Timestamp(date: Date()),
        ]

        if let expiresIn {
            pollData["expiresAt"] = Timestamp(date: Date().addingTimeInterval(expiresIn))
        }

        try await db.collection("posts").document(postId).updateData([
            "poll": pollData,
        ])
    }
}
