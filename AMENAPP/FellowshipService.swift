//
//  FellowshipService.swift
//  AMENAPP
//
//  Reads `fellowshipSuggestions` documents for the current user.
//  The Cloud Function `fellowshipMatcher` writes these when it detects
//  a deep spiritual theme overlap between two users' prayers/testimonies.
//
//  Usage: observe `suggestions` from any view that wants to surface matches.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Model

struct FellowshipSuggestion: Identifiable, Codable {
    @DocumentID var id: String?
    var userId1: String
    var userId2: String
    var recipientUserId: String
    var partnerUserId: String
    var partnerDisplayName: String
    var theme: String
    var conversationStarter: String
    var matchScore: Int
    var opentableURL: String
    var status: SuggestionStatus
    var createdAt: Date?

    enum SuggestionStatus: String, Codable {
        case pending   = "pending"
        case viewed    = "viewed"
        case dismissed = "dismissed"
    }

    enum CodingKeys: String, CodingKey {
        case id, userId1, userId2, recipientUserId, partnerUserId,
             partnerDisplayName, theme, conversationStarter,
             matchScore, opentableURL, status, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decodeIfPresent(String.self,            forKey: .id)
        userId1             = try c.decode(String.self,                     forKey: .userId1)
        userId2             = try c.decode(String.self,                     forKey: .userId2)
        recipientUserId     = try c.decode(String.self,                     forKey: .recipientUserId)
        partnerUserId       = try c.decode(String.self,                     forKey: .partnerUserId)
        partnerDisplayName  = try c.decodeIfPresent(String.self,            forKey: .partnerDisplayName) ?? "Someone"
        theme               = try c.decodeIfPresent(String.self,            forKey: .theme) ?? ""
        conversationStarter = try c.decodeIfPresent(String.self,            forKey: .conversationStarter) ?? ""
        matchScore          = try c.decodeIfPresent(Int.self,               forKey: .matchScore) ?? 0
        opentableURL        = try c.decodeIfPresent(String.self,            forKey: .opentableURL) ?? ""
        status              = try c.decodeIfPresent(SuggestionStatus.self,  forKey: .status) ?? .pending
        createdAt           = try c.decodeIfPresent(Date.self,              forKey: .createdAt)
    }
}

// MARK: - Service

@MainActor
final class FellowshipService: ObservableObject {
    static let shared = FellowshipService()
    private init() {}

    @Published var suggestions: [FellowshipSuggestion] = []
    @Published var isLoading = false

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    // MARK: - Start / Stop

    /// Attach a real-time listener for the current user's fellowship suggestions.
    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stopListening()
        isLoading = true

        listener = db.collection("fellowshipSuggestions")
            .whereField("recipientUserId", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    dlog("FellowshipService: listener error — \(error.localizedDescription)")
                    return
                }
                self.suggestions = (snapshot?.documents ?? []).compactMap { doc in
                    try? doc.data(as: FellowshipSuggestion.self)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Actions

    /// Mark a suggestion as viewed (idempotent).
    func markViewed(_ suggestion: FellowshipSuggestion) {
        guard let docId = suggestion.id else { return }
        db.collection("fellowshipSuggestions").document(docId)
            .updateData(["status": "viewed"]) { error in
                if let error { dlog("FellowshipService: markViewed error — \(error)") }
            }
    }

    /// Dismiss a suggestion so it no longer appears.
    func dismiss(_ suggestion: FellowshipSuggestion) {
        guard let docId = suggestion.id else { return }
        db.collection("fellowshipSuggestions").document(docId)
            .updateData(["status": "dismissed"]) { error in
                if let error { dlog("FellowshipService: dismiss error — \(error)") }
            }
        suggestions.removeAll { $0.id == docId }
    }

    /// Open the pre-built OpenTable URL for this suggestion.
    func openOpenTable(for suggestion: FellowshipSuggestion) {
        guard let url = URL(string: suggestion.opentableURL) else { return }
        UIApplication.shared.open(url)
        markViewed(suggestion)
    }
}
