// LivingMemoryService.swift
// AMENAPP
// Soul Engine — fetches semantically resonant content for the current user

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class LivingMemoryService: ObservableObject {
    @Published var resonantItems: [LivingMemoryItem] = []
    @Published var isLoading = false
    @Published var error: String?

    static let shared = LivingMemoryService()
    private let functions = Functions.functions()
    private init() {}

    // Fetch resonant content based on the user's most recent prayer post
    func loadResonantContent() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 1. Find the user's most recent prayer post
            let db = Firestore.firestore()
            let prayerSnap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .whereField("type", isEqualTo: "prayer")
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()

            guard let prayerDoc = prayerSnap.documents.first else {
                resonantItems = []
                return
            }

            // 2. Call findResonantContent Cloud Function
            let result = try await functions
                .httpsCallable("findResonantContent")
                .call([
                    "sourcePostId": prayerDoc.documentID,
                    "limit": 6,
                    "types": ["testimony", "prayer"],
                ])

            guard let dict = result.data as? [String: Any],
                  let rawResults = dict["results"] as? [[String: Any]] else {
                resonantItems = []
                return
            }

            resonantItems = rawResults.compactMap { LivingMemoryItem(dict: $0) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Mark a prayer as answered by a testimony
    func markAnswered(prayerPostId: String, testimonyPostId: String, note: String? = nil) async throws {
        var payload: [String: Any] = [
            "prayerPostId": prayerPostId,
            "testimonyPostId": testimonyPostId,
        ]
        if let note { payload["note"] = note }
        _ = try await functions.httpsCallable("markPrayerAnswered").safeCall(payload)
    }
}

// MARK: - Data model

struct LivingMemoryItem: Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorPhotoURL: String?
    let content: String
    let type: LivingMemoryItemType
    let createdAt: Date
    let resonanceScore: Double

    enum LivingMemoryItemType: String {
        case prayer, testimony, post
        var icon: String {
            switch self {
            case .prayer:    return "hands.sparkles.fill"
            case .testimony: return "star.fill"
            case .post:      return "text.bubble.fill"
            }
        }
        var label: String {
            switch self {
            case .prayer:    return "Prayer"
            case .testimony: return "Testimony"
            case .post:      return "Post"
            }
        }
    }

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let content = dict["content"] as? String else { return nil }
        self.id = id
        self.authorId  = dict["authorId"]  as? String ?? ""
        self.authorName = dict["authorName"] as? String ?? "Someone"
        self.authorPhotoURL = dict["authorPhotoURL"] as? String
        self.content = content
        let typeRaw = dict["type"] as? String ?? "post"
        self.type = LivingMemoryItemType(rawValue: typeRaw) ?? .post
        let ms = dict["createdAt"] as? Double ?? 0
        self.createdAt = ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : Date()
        self.resonanceScore = dict["resonanceScore"] as? Double ?? 0
    }
}
