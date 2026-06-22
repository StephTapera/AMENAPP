// SpacesViewModel.swift — AMEN App
// View model for SpacesDiscoveryView

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions
// AmenSpaceEntitlementService is in AMENAPP/AMENAPP/ConnectSpaces/Monetization/

@MainActor
class SpacesViewModel: ObservableObject {
    @Published var recommendedSpaces: [AMENSpace] = []
    @Published var allSpaces: [AMENSpace] = []
    @Published var joinedSpaceIds: Set<String> = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var selectedFilter: SpaceFilter = .forYou
    /// Set to true when a join attempt is blocked by the entitlement gate.
    /// Views should observe this to present a paywall sheet.
    @Published var showPaywall = false

    enum SpaceFilter: String, CaseIterable {
        case forYou = "For You"
        case newest = "Newest"
    }

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var filteredSpaces: [AMENSpace] {
        let base = searchText.isEmpty ? allSpaces : allSpaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.aiDetectedTopics.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        switch selectedFilter {
        case .forYou:  return base
        case .newest:  return base.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    func load() {
        guard listener == nil else { return }
        isLoading = true
        listener = db.collection("spaces")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    SwiftUI.withAnimation(.easeInOut(duration: 0.2)) {
                        self.allSpaces = snap?.documents.compactMap {
                            try? $0.data(as: AMENSpace.self)
                        } ?? []
                        self.recommendedSpaces = Array(self.allSpaces.prefix(6))
                    }
                }
            }
        loadJoinedSpaces()
    }

    func loadJoinedSpaces() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("spaceMemberships")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snap, _ in
                Task { @MainActor [weak self] in
                    let ids = snap?.documents.compactMap { $0.data()["spaceId"] as? String } ?? []
                    self?.joinedSpaceIds = Set(ids)
                }
            }
    }

    func toggleJoin(space: AMENSpace) async {
        guard let uid = Auth.auth().currentUser?.uid, let spaceId = space.id else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let docId = "\(uid)_\(spaceId)"
        let ref = db.collection("spaceMemberships").document(docId)
        let spaceRef = db.collection("spaces").document(spaceId)

        if joinedSpaceIds.contains(spaceId) {
            _ = SwiftUI.withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                joinedSpaceIds.remove(spaceId)
            }
            try? await ref.delete()
            try? await spaceRef.updateData(["memberCount": FieldValue.increment(Int64(-1))])
        } else {
            // Entitlement gate: verify server-side before writing to Firestore.
            // Free-tier users attempting to join a paid Space are shown a paywall
            // and the join is aborted without any Firestore write.
            let entitlement = await AmenSpaceEntitlementService()
                .checkEntitlement(userId: Auth.auth().currentUser?.uid ?? "", spaceId: spaceId)
            let hasEntitlement = entitlement?.isActive ?? false
            guard hasEntitlement else {
                showPaywall = true
                return
            }

            _ = SwiftUI.withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                joinedSpaceIds.insert(spaceId)
            }
            try? await ref.setData([
                "userId": uid, "spaceId": spaceId,
                "joinedAt": FieldValue.serverTimestamp(),
                "notificationsEnabled": true, "role": "member"
            ])
            try? await spaceRef.updateData(["memberCount": FieldValue.increment(Int64(1))])
        }
    }

    func createSpace(name: String, description: String, topics: [String]) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }
        let ref = db.collection("spaces").document()
        try await ref.setData([
            "name": name, "description": description,
            "aiDetectedTopics": topics, "memberCount": 1,
            "postCount": 0, "isAutoGenerated": false,
            "topPostIds": [], "weeklyActiveUsers": 1,
            "recentPosterPhotoURLs": [],
            "createdAt": FieldValue.serverTimestamp()
        ])
        // Auto-join creator
        do {
            try await db.collection("spaceMemberships")
                .document("\(uid)_\(ref.documentID)")
                .setData([
                    "userId": uid, "spaceId": ref.documentID,
                    "joinedAt": FieldValue.serverTimestamp(),
                    "notificationsEnabled": true, "role": "member"
                ])
        } catch {
            print("SpacesViewModel: failed to auto-join creator to space — \(error.localizedDescription)")
        }
        _ = await MainActor.run {
            joinedSpaceIds.insert(ref.documentID)
        }
        return ref.documentID
    }

    // AI generates name/description/topics from user's free-text description
    func aiGenerateSpaceDetails(from description: String) async throws -> (name: String, description: String, topics: [String]) {
        let system = """
        You are a community naming AI for AMEN, a Christian social app. \
        Given a user's description of a community they want to create, generate: \
        a short compelling name (2-4 words), a one-sentence description, \
        and 3-5 topic tags. Respond with ONLY valid JSON: \
        {"name":"...","description":"...","topics":["...","..."]}
        """
        let payload: [String: Any] = [
            "systemPrompt": system,
            "userMessage": "Create a community for: \(description)",
            "maxTokens": 200
        ]
        let result = try await Functions.functions().httpsCallable("bereanChatProxy").call(payload)
        guard let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let desc = json["description"] as? String,
              let topics = json["topics"] as? [String]
        else { throw URLError(.cannotParseResponse) }
        return (name, desc, topics)
    }

    deinit { listener?.remove() }
}

// MARK: - SpaceFeedViewModel

@MainActor
class SpaceFeedViewModel: ObservableObject {
    @Published var posts: [SpacePost] = []
    @Published var isLoading = false
    @Published var selectedContentType: SpacePost.ContentType? = nil

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var filtered: [SpacePost] {
        guard let type = selectedContentType else { return posts }
        return posts.filter { $0.contentType == type }
    }

    func startListening(spaceId: String) {
        guard listener == nil else { return }
        isLoading = true
        let query: Query = db.collection("spacePosts")
            .whereField("spaceId", isEqualTo: spaceId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)

        listener = query.addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                SwiftUI.withAnimation(.easeInOut(duration: 0.2)) {
                    self.posts = snap?.documents.compactMap {
                        try? $0.data(as: SpacePost.self)
                    } ?? []
                }
            }
        }
    }

    func postToSpace(spaceId: String, text: String?, mediaURLs: [String], type: SpacePost.ContentType) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ref = db.collection("spacePosts").document()
        try await ref.setData([
            "spaceId": spaceId, "authorId": uid,
            "contentType": type.rawValue,
            "textContent": text as Any,
            "mediaURLs": mediaURLs,
            "aiConfidenceScore": 0.9,
            "likes": 0, "comments": 0,
            "createdAt": FieldValue.serverTimestamp()
        ])
        do {
            try await db.collection("spaces").document(spaceId)
                .updateData(["postCount": FieldValue.increment(Int64(1))])
        } catch {
            print("SpacesViewModel: failed to increment space postCount — \(error.localizedDescription)")
        }
    }

    func stopListening() { listener?.remove(); listener = nil }
    deinit { listener?.remove() }
}
