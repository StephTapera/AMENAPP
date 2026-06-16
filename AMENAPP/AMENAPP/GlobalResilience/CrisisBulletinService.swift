// CrisisBulletinService.swift
// AMEN — Global Resilience System
//
// Real-time Firestore listener for active crisis bulletins.
// Collection: /crisisBulletins
// Query: expiresAt > now, ordered by severity (serverside severity ordering is
//        done via a numeric field; client re-sorts by severity weight after fetch).
//
// All published bulletins — including expired ones surfaced in the listener
// window — are vended through `activeBulletins`. CrisisBulletinCard is
// responsible for rendering the "(Expired)" badge when expiresAt < Date().
//
// Feature-gated by GlobalResilienceFeatureFlags.shared.crisisBulletinsEnabled.
// When the flag is off the listener is not started and activeBulletins is empty.
//
// Usage:
//   await GlobalResilienceFeatureFlags.shared.fetchAll()
//   CrisisBulletinService.shared.startListening()

import SwiftUI
import FirebaseFirestore

// MARK: - CrisisBulletinService

@MainActor
final class CrisisBulletinService: ObservableObject {

    // MARK: Shared instance

    static let shared = CrisisBulletinService()

    // MARK: Published state

    /// Bulletins active at query time, sorted by descending severity weight.
    /// Expired items that arrive during a live listener session are included;
    /// CrisisBulletinCard renders the "(Expired)" badge for them.
    @Published var activeBulletins: [CrisisBulletin] = []

    // MARK: Private state

    private var listenerRegistration: ListenerRegistration?
    // lazy so Firestore.firestore() is not called until startListening() first
    // accesses db — by that point FirebaseApp.configure() has already run in
    // AppDelegate and Firestore is ready. An eager `let` here crashes if the
    // singleton is touched before Firebase is configured.
    private lazy var db = Firestore.firestore()

    // MARK: Init

    private init() {}

    // MARK: - Public API

    /// Attaches a real-time Firestore listener on /crisisBulletins where
    /// expiresAt is greater than now, ordered by severity descending (mapped
    /// to a numeric weight client-side after mapping).
    ///
    /// Calling this more than once is safe — any previous listener is removed
    /// before a new one is created.
    ///
    /// No-ops silently when `crisisBulletinsEnabled` is false.
    func startListening() {
        guard GlobalResilienceFeatureFlags.shared.crisisBulletinsEnabled else {
            return
        }

        // Remove any previous registration before attaching a new one.
        stopListening()

        let now = Timestamp(date: Date())

        let query = db.collection("crisisBulletins")
            .whereField("expiresAt", isGreaterThan: now)
            .order(by: "expiresAt", descending: false)

        listenerRegistration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                print("[CrisisBulletinService] Listener error: \(error.localizedDescription)")
                return
            }

            guard let snapshot else { return }

            let bulletins: [CrisisBulletin] = snapshot.documents.compactMap { doc in
                Self.bulletin(from: doc)
            }

            // Sort descending by severity weight so critical items appear first.
            self.activeBulletins = bulletins.sorted {
                Self.severityWeight($0.severity) > Self.severityWeight($1.severity)
            }
        }
    }

    /// Detaches the Firestore listener and clears the published array.
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        activeBulletins = []
    }

    // MARK: - Private helpers

    /// Maps a Firestore document to a CrisisBulletin value.
    /// Returns nil when any required field is missing or malformed.
    private static func bulletin(from doc: QueryDocumentSnapshot) -> CrisisBulletin? {
        let data = doc.data()

        guard
            let title = data["title"] as? String, !title.isEmpty,
            let bodyText = data["bodyText"] as? String,
            let severity = data["severity"] as? String,
            let regionScope = data["regionScope"] as? String,
            let expiresAtTimestamp = data["expiresAt"] as? Timestamp
        else {
            print("[CrisisBulletinService] Skipping malformed document: \(doc.documentID)")
            return nil
        }

        let lowDataOnly = data["lowDataOnly"] as? Bool ?? false
        let publishedByOrgId = data["publishedByOrgId"] as? String ?? ""

        return CrisisBulletin(
            id: doc.documentID,
            title: title,
            bodyText: bodyText,
            severity: severity,
            regionScope: regionScope,
            expiresAt: expiresAtTimestamp.dateValue(),
            lowDataOnly: lowDataOnly,
            publishedByOrgId: publishedByOrgId
        )
    }

    /// Returns a numeric weight for a severity string so bulletins can be sorted
    /// with the most urgent items first.
    ///
    /// Unknown severity values are treated as "info" (weight 0) so new severity
    /// tiers added server-side do not crash the client.
    private static func severityWeight(_ severity: String) -> Int {
        switch severity {
        case "emergency": return 3
        case "critical":  return 2
        case "warning":   return 1
        default:          return 0  // "info" + unknown
        }
    }
}
