// IntelligenceBriefViewModel.swift
// AMEN Living Intelligence
//
// Drives IntelligenceBriefView. Reads the current brief from Firestore.
// Formation invariant: refreshBrief() does NOT re-rank; it re-reads the same stored brief.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class IntelligenceBriefViewModel: ObservableObject {
    @Published var state: IntelligenceUIState = .loading
    @Published var cards: [IntelligenceCard] = []
    @Published var isStale: Bool = false
    @Published var lastRefreshed: Date?

    private let db = Firestore.firestore()

    // MARK: - Load

    /// Reads the current intelligence brief from Firestore.
    /// Formation invariant: does NOT call a Cloud Function — only reads what the server wrote.
    func loadBrief() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            state = .error("You must be signed in to view your brief.")
            return
        }

        state = .loading

        do {
            let doc = try await db
                .collection("users")
                .document(uid)
                .collection("intelligence_brief")
                .document("current")
                .getDocument()

            guard doc.exists, let data = doc.data() else {
                state = .empty
                return
            }

            let decoded = try parseCards(from: data)
            // Filter: only show cards backed by a verified entity
            let verified = decoded.filter { $0.backingEntity.verified }

            if verified.isEmpty {
                state = .empty
            } else {
                // Enforce MAX_CARDS_PER_BRIEF = 7
                let capped = Array(verified.prefix(7))
                // Sort by tier display order, then by rankScore descending
                cards = capped.sorted {
                    if $0.tier.displayOrder != $1.tier.displayOrder {
                        return $0.tier.displayOrder < $1.tier.displayOrder
                    }
                    return $0.rankScore > $1.rankScore
                }
                lastRefreshed = Date()
                isStale = false
                state = .populated
            }
        } catch let error as NSError where error.domain == FirestoreErrorDomain
                    && error.code == FirestoreErrorCode.unavailable.rawValue {
            // Offline: serve stale brief if available
            if !cards.isEmpty {
                isStale = true
                state = .offlineStale
            } else {
                state = .error("You're offline and no cached brief is available.")
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Refresh (re-render same brief — formation invariant: no new ranking)

    /// Re-reads the same stored brief. Does NOT trigger a new CF execution.
    func refreshBrief() async {
        await loadBrief()
    }

    // MARK: - Action side-effects

    func handleAction(_ action: CardAction, on card: IntelligenceCard) {
        Task {
            await markCardActedOn(card.id)
        }
    }

    // MARK: - Loop Closing

    func markCardActedOn(_ cardId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("intelligence_brief")
                .document("actedOnCards")
                .setData([cardId: FieldValue.serverTimestamp()], merge: true)
        } catch {
            // Non-critical persistence — fail silently
        }
    }

    // MARK: - Parsing

    private func parseCards(from data: [String: Any]) throws -> [IntelligenceCard] {
        guard let rawCards = data["cards"] as? [[String: Any]], !rawCards.isEmpty else {
            return []
        }

        let jsonData = try JSONSerialization.data(withJSONObject: rawCards)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([IntelligenceCard].self, from: jsonData)
    }
}
