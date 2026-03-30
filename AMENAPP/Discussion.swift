// Discussion.swift — AMEN App
// Models for Reasoning Native Discussions and argument tree nodes

import Foundation
import FirebaseFirestore

// MARK: - Discussion

struct Discussion: Identifiable, Codable {
    @DocumentID var id: String?
    var originalPostId: String
    var claim: String
    var aiSteelManFor: String
    var aiSteelManAgainst: String
    var aiFactualVsValues: String       // "factual" | "values" | "mixed"
    var viewUpdateCount: Int
    var participantIds: [String]
    var status: DiscussionStatus
    var createdAt: Date?

    enum DiscussionStatus: String, Codable {
        case open, resolved
    }

    enum CodingKeys: String, CodingKey {
        case id, originalPostId, claim, aiSteelManFor, aiSteelManAgainst,
             aiFactualVsValues, viewUpdateCount, participantIds, status, createdAt
    }

    static let empty = Discussion(
        originalPostId: "",
        claim: "",
        aiSteelManFor: "",
        aiSteelManAgainst: "",
        aiFactualVsValues: "mixed",
        viewUpdateCount: 0,
        participantIds: [],
        status: .open,
        createdAt: nil
    )
}

// MARK: - DiscussionNode

struct DiscussionNode: Identifiable, Codable {
    @DocumentID var id: String?
    var discussionId: String
    var authorId: String
    var authorName: String?
    var authorPhotoURL: String?
    var parentNodeId: String?
    var claim: String
    var evidence: [String]
    var nodeType: NodeType
    var aiManipulationFlags: [String]
    var votes: Int
    var depth: Int                      // nesting level (0 = root)
    var createdAt: Date?

    enum NodeType: String, Codable {
        case argument, counterargument, evidence, viewUpdate

        var accentColor: String {
            switch self {
            case .argument: return "purple"
            case .counterargument: return "amber"
            case .evidence: return "green"
            case .viewUpdate: return "white"
            }
        }

        var label: String {
            switch self {
            case .argument: return "Argument"
            case .counterargument: return "Counterargument"
            case .evidence: return "Evidence"
            case .viewUpdate: return "I changed my view"
            }
        }

        var icon: String {
            switch self {
            case .argument: return "bubble.left.fill"
            case .counterargument: return "bubble.right.fill"
            case .evidence: return "doc.text.fill"
            case .viewUpdate: return "arrow.uturn.left.circle.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, discussionId, authorId, authorName, authorPhotoURL, parentNodeId,
             claim, evidence, nodeType, aiManipulationFlags, votes, depth, createdAt
    }
}
