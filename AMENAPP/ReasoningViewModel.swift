// ReasoningViewModel.swift — AMEN App
// View model for Reasoning Native Discussions

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class ReasoningViewModel: ObservableObject {
    @Published var discussion: Discussion = .empty
    @Published var nodes: [DiscussionNode] = []
    @Published var isLoadingFrame = false
    @Published var isPostingNode = false
    @Published var manipulationFlags: [String] = []

    let postId: String
    let postText: String
    private let db = Firestore.firestore()
    private var discussionListener: ListenerRegistration?
    private var nodesListener: ListenerRegistration?

    init(postId: String, postText: String) {
        self.postId = postId
        self.postText = postText
    }

    // Returns nodes at a specific depth level whose parent is parentId
    func children(of parentId: String?) -> [DiscussionNode] {
        nodes.filter { $0.parentNodeId == parentId }
    }

    var rootNodes: [DiscussionNode] { nodes.filter { $0.parentNodeId == nil || $0.parentNodeId == "" } }

    // MARK: - Load or Create Discussion

    func loadOrCreate() async {
        // Check if discussion exists for this post
        let snap = try? await db.collection("discussions")
            .whereField("originalPostId", isEqualTo: postId)
            .limit(to: 1)
            .getDocuments()

        if let doc = snap?.documents.first,
           let disc = try? doc.data(as: Discussion.self) {
            discussion = disc
            startListeningToNodes(discussionId: doc.documentID)
        } else {
            // Create new — generate AI frame
            await generateDiscussionFrame()
        }
    }

    private func generateDiscussionFrame() async {
        isLoadingFrame = true
        defer { isLoadingFrame = false }

        let system = """
        You are a neutral discussion facilitator for a Christian social app. \
        Given a post, generate: \
        1. The core claim being made \
        2. The strongest argument FOR this claim (steel-man) \
        3. The strongest argument AGAINST this claim (steel-man) \
        4. Whether this is primarily a factual, values, or mixed disagreement \
        Respond ONLY with valid JSON: \
        {"claim":"...","steelManFor":"...","steelManAgainst":"...","factualVsValues":"factual|values|mixed"}
        """
        let payload: [String: Any] = [
            "systemPrompt": system,
            "userMessage": "Analyze this post: \"\(postText.prefix(500))\"",
            "maxTokens": 600
        ]

        guard let result = try? await Functions.functions().httpsCallable("bereanChatProxy").call(payload),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let claim       = json["claim"] as? String ?? postText.prefix(100).description
        let steelFor    = json["steelManFor"] as? String ?? ""
        let steelAgainst = json["steelManAgainst"] as? String ?? ""
        let fvv         = json["factualVsValues"] as? String ?? "mixed"

        let ref = db.collection("discussions").document()
        try? await ref.setData([
            "originalPostId": postId,
            "claim": claim,
            "aiSteelManFor": steelFor,
            "aiSteelManAgainst": steelAgainst,
            "aiFactualVsValues": fvv,
            "viewUpdateCount": 0,
            "participantIds": [],
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ])

        discussion = Discussion(
            originalPostId: postId, claim: claim,
            aiSteelManFor: steelFor, aiSteelManAgainst: steelAgainst,
            aiFactualVsValues: fvv, viewUpdateCount: 0,
            participantIds: [], status: .open
        )
        startListeningToNodes(discussionId: ref.documentID)
    }

    private func startListeningToNodes(discussionId: String) {
        guard nodesListener == nil else { return }
        nodesListener = db.collection("discussionNodes")
            .whereField("discussionId", isEqualTo: discussionId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    SwiftUI.withAnimation(.easeInOut(duration: 0.2)) {
                        self?.nodes = snap?.documents.compactMap {
                            try? $0.data(as: DiscussionNode.self)
                        } ?? []
                    }
                }
            }
    }

    // MARK: - Pre-screen argument for manipulation

    func screenArgument(_ text: String) async {
        manipulationFlags = []
        let system = """
        You are a logical integrity checker. Identify any logical fallacies in this argument. \
        Return ONLY a JSON array of strings, each naming a detected fallacy. \
        If none, return []. Examples: ["ad_hominem","strawman","appeal_to_emotion"]. \
        Maximum 3 flags. Be conservative — only flag clear violations.
        """
        guard let result = try? await Functions.functions()
            .httpsCallable("bereanChatProxy")
            .call(["systemPrompt": system, "userMessage": text, "maxTokens": 100]),
              let dict = result.data as? [String: Any],
              let raw = dict["text"] as? String,
              let data = raw.data(using: .utf8),
              let flags = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return }
        manipulationFlags = flags
    }

    // MARK: - Post argument node

    func postNode(claim: String, evidence: [String], type: DiscussionNode.NodeType, parentId: String?) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let discussionId = discussion.id else { return }
        isPostingNode = true
        defer { isPostingNode = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let depth = parentId == nil ? 0 : (nodes.first { $0.id == parentId }?.depth ?? 0) + 1
        try? await db.collection("discussionNodes").addDocument(data: [
            "discussionId": discussionId,
            "authorId": uid,
            "parentNodeId": parentId as Any,
            "claim": claim,
            "evidence": evidence,
            "nodeType": type.rawValue,
            "aiManipulationFlags": manipulationFlags,
            "votes": 0,
            "depth": depth,
            "createdAt": FieldValue.serverTimestamp()
        ])

        if type == .viewUpdate {
            try? await db.collection("discussions").document(discussionId)
                .updateData(["viewUpdateCount": FieldValue.increment(Int64(1))])
        }
    }

    // MARK: - Upvote

    func upvote(nodeId: String) async {
        try? await db.collection("discussionNodes").document(nodeId)
            .updateData(["votes": FieldValue.increment(Int64(1))])
    }

    deinit {
        discussionListener?.remove()
        nodesListener?.remove()
    }
}
