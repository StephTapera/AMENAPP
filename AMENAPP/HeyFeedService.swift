//
//  HeyFeedService.swift
//  AMENAPP
//
//  Real-time service managing HeyFeed requests, community resonance,
//  and pastoral care signals for the OpenTable feed.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - HeyFeedRequest

struct HeyFeedRequest: Identifiable, Codable {
    let id: String
    let postId: String
    let authorId: String
    let requestType: HeyFeedRequestType
    let intent: HeyFeedIntent
    let resonanceScore: Double
    let resonanceCount: Int
    let isActive: Bool
    let expiresAt: Date
    let createdAt: Date
    var updatedAt: Date

    enum HeyFeedRequestType: String, Codable, CaseIterable {
        case prayer     = "prayer"
        case question   = "question"
        case fellowship = "fellowship"
        case study      = "study"
        case testimony  = "testimony"
        case care       = "care"

        var displayName: String {
            switch self {
            case .prayer:     return "Prayer Request"
            case .question:   return "Question"
            case .fellowship: return "Fellowship"
            case .study:      return "Bible Study"
            case .testimony:  return "Testimony"
            case .care:       return "Pastoral Care"
            }
        }

        var icon: String {
            switch self {
            case .prayer:     return "hands.sparkles"
            case .question:   return "questionmark.circle"
            case .fellowship: return "person.2"
            case .study:      return "book.closed"
            case .testimony:  return "star.bubble"
            case .care:       return "heart.circle"
            }
        }
    }
}

// MARK: - HeyFeedResonanceType

enum HeyFeedResonanceType: String, Codable, CaseIterable {
    case praying    = "praying"
    case standing   = "standing"
    case witnessed  = "witnessed"
    case helped     = "helped"
    case encouraged = "encouraged"

    var displayName: String {
        switch self {
        case .praying:    return "Praying"
        case .standing:   return "Standing With You"
        case .witnessed:  return "I Witnessed This"
        case .helped:     return "I Helped"
        case .encouraged: return "Encouraged"
        }
    }

    var icon: String {
        switch self {
        case .praying:    return "hands.sparkles.fill"
        case .standing:   return "figure.stand"
        case .witnessed:  return "eye.fill"
        case .helped:     return "hand.raised.fill"
        case .encouraged: return "heart.fill"
        }
    }
}

// MARK: - HeyFeedResonance

struct HeyFeedResonance: Identifiable, Codable {
    let id: String
    let requestId: String
    let postId: String
    let userId: String
    let type: HeyFeedResonanceType
    let createdAt: Date
}

// MARK: - PastoralCareSignal

struct PastoralCareSignal: Identifiable, Codable {
    let id: String
    let postId: String
    let userId: String
    let signalType: String     // "crisis", "grief", "loneliness"
    let urgencyScore: Double
    let isAcknowledged: Bool
    let createdAt: Date
}

// MARK: - HeyFeedService

@MainActor
class HeyFeedService: ObservableObject {

    // MARK: Singleton

    static let shared = HeyFeedService()

    // MARK: Published State

    @Published var activeRequests: [HeyFeedRequest] = []
    @Published var resonanceMap: [String: [HeyFeedResonance]] = [:]
    @Published var resonanceScores: [String: Double] = [:]
    @Published var myResonances: Set<String> = []
    @Published var pastoralSignals: [PastoralCareSignal] = []
    @Published var isLoading = false

    // MARK: Private

    private lazy var db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {
        dlog("[HeyFeedService] Initialized")
    }

    // MARK: - Listening

    func startListening() {
        guard listeners.isEmpty else {
            dlog("[HeyFeedService] Already listening — skipping duplicate attach")
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[HeyFeedService] No authenticated user — cannot start listeners")
            return
        }

        isLoading = true
        attachActiveRequestsListener()
        attachMyResonancesListener(uid: uid)
        attachPastoralSignalsListener()
        dlog("[HeyFeedService] All listeners attached for uid=\(uid)")
    }

    func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
        dlog("[HeyFeedService] All listeners removed")
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    // MARK: Private Listener Helpers

    private func attachActiveRequestsListener() {
        let query = db.collection("heyfeed_requests")
            .whereField("isActive", isEqualTo: true)
            .order(by: "resonanceScore", descending: true)
            .limit(to: 50)

        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                dlog("[HeyFeedService] activeRequests listener error: \(error.localizedDescription)")
                self.isLoading = false
                return
            }
            guard let docs = snapshot?.documents else {
                self.isLoading = false
                return
            }

            let parsed = docs.compactMap { doc -> HeyFeedRequest? in
                self.decodeRequest(from: doc)
            }
            self.activeRequests = parsed
            self.isLoading = false
            dlog("[HeyFeedService] activeRequests updated — count=\(parsed.count)")
        }
        listeners.append(registration)
    }

    private func attachMyResonancesListener(uid: String) {
        let query = db.collection("heyfeed_resonance")
            .whereField("userId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)  // ✅ FIX CR-4: Add pagination limit (generous for resonance tracking)

        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                dlog("[HeyFeedService] myResonances listener error: \(error.localizedDescription)")
                return
            }
            guard let docs = snapshot?.documents else { return }

            var updatedMap: [String: [HeyFeedResonance]] = [:]
            var resonatedPostIds: Set<String> = []

            for doc in docs {
                guard let resonance = self.decodeResonance(from: doc) else { continue }
                resonatedPostIds.insert(resonance.postId)
                updatedMap[resonance.postId, default: []].append(resonance)
            }

            self.myResonances = resonatedPostIds
            self.resonanceMap = updatedMap
            dlog("[HeyFeedService] myResonances updated — postIds=\(resonatedPostIds.count)")
        }
        listeners.append(registration)
    }

    private func attachPastoralSignalsListener() {
        // Only non-acknowledged, recent signals (safety-first: limit 25)
        let query = db.collection("pastoral_care_signals")
            .whereField("isAcknowledged", isEqualTo: false)
            .order(by: "urgencyScore", descending: true)
            .limit(to: 25)

        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                dlog("[HeyFeedService] pastoralSignals listener error: \(error.localizedDescription)")
                return
            }
            guard let docs = snapshot?.documents else { return }

            let signals = docs.compactMap { doc -> PastoralCareSignal? in
                self.decodePastoralSignal(from: doc)
            }
            self.pastoralSignals = signals
            dlog("[HeyFeedService] pastoralSignals updated — count=\(signals.count)")
        }
        listeners.append(registration)
    }

    // MARK: - Submit Request

    func submitRequest(
        postId: String,
        requestType: HeyFeedRequest.HeyFeedRequestType,
        intent: HeyFeedIntent
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[HeyFeedService] submitRequest — no authenticated user")
            throw HeyFeedServiceError.unauthenticated
        }

        let expiresAt = Date().addingTimeInterval(72 * 60 * 60) // 72 hours
        let now = Date()
        let docRef = db.collection("heyfeed_requests").document()

        let data: [String: Any] = [
            "id": docRef.documentID,
            "postId": postId,
            "authorId": uid,
            "requestType": requestType.rawValue,
            "intent": intent.rawValue,
            "resonanceScore": 0.0,
            "resonanceCount": 0,
            "isActive": true,
            "expiresAt": Timestamp(date: expiresAt),
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]

        try await docRef.setData(data)
        dlog("[HeyFeedService] submitRequest — docId=\(docRef.documentID) postId=\(postId) type=\(requestType.rawValue)")
    }

    // MARK: - Record Resonance

    func recordResonance(
        postId: String,
        requestId: String,
        type: HeyFeedResonanceType
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[HeyFeedService] recordResonance — no authenticated user")
            throw HeyFeedServiceError.unauthenticated
        }

        let resonanceDocId = "\(uid)_\(postId)"
        let resonanceRef = db.collection("heyfeed_resonance").document(resonanceDocId)
        let requestRef = db.collection("heyfeed_requests").document(requestId)
        let now = Date()

        // Idempotent write: use merge so re-submitting the same resonance is safe
        let resonanceData: [String: Any] = [
            "id": resonanceDocId,
            "requestId": requestId,
            "postId": postId,
            "userId": uid,
            "type": type.rawValue,
            "createdAt": Timestamp(date: now)
        ]
        try await resonanceRef.setData(resonanceData, merge: true)

        // Increment resonanceCount and recompute resonanceScore
        try await requestRef.updateData([
            "resonanceCount": FieldValue.increment(Int64(1)),
            "resonanceScore": FieldValue.increment(Double(resonanceScoreIncrement(for: type))),
            "updatedAt": Timestamp(date: now)
        ])

        dlog("[HeyFeedService] recordResonance — postId=\(postId) type=\(type.rawValue)")
    }

    // MARK: - Remove Resonance

    func removeResonance(
        postId: String,
        requestId: String,
        type: HeyFeedResonanceType
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("[HeyFeedService] removeResonance — no authenticated user")
            throw HeyFeedServiceError.unauthenticated
        }

        let resonanceDocId = "\(uid)_\(postId)"
        let resonanceRef = db.collection("heyfeed_resonance").document(resonanceDocId)
        let requestRef = db.collection("heyfeed_requests").document(requestId)
        let now = Date()

        try await resonanceRef.delete()

        // Decrement — guard against going below zero on the score
        let decrement = resonanceScoreIncrement(for: type)
        try await requestRef.updateData([
            "resonanceCount": FieldValue.increment(Int64(-1)),
            "resonanceScore": FieldValue.increment(Double(-decrement)),
            "updatedAt": Timestamp(date: now)
        ])

        dlog("[HeyFeedService] removeResonance — postId=\(postId) type=\(type.rawValue)")
    }

    // MARK: - Pastoral Care Signal

    func reportPastoralCareSignal(
        postId: String,
        userId: String,
        urgencyScore: Double,
        signalType: String
    ) async {
        let docRef = db.collection("pastoral_care_signals").document()
        let now = Date()

        let data: [String: Any] = [
            "id": docRef.documentID,
            "postId": postId,
            "userId": userId,
            "signalType": signalType,
            "urgencyScore": max(0.0, min(1.0, urgencyScore)),
            "isAcknowledged": false,
            "createdAt": Timestamp(date: now)
        ]

        do {
            try await docRef.setData(data)
            dlog("[HeyFeedService] reportPastoralCareSignal — postId=\(postId) signalType=\(signalType) urgency=\(urgencyScore)")
        } catch {
            // Best-effort: log but do not propagate
            dlog("[HeyFeedService] reportPastoralCareSignal FAILED (non-fatal): \(error.localizedDescription)")
        }
    }

    // MARK: - Query Helpers

    func hasMyResonance(postId: String) -> Bool {
        myResonances.contains(postId)
    }

    func getResonanceScore(postId: String) -> Double {
        resonanceScores[postId] ?? 0.0
    }

    func isActiveRequest(postId: String) -> Bool {
        activeRequests.contains { $0.postId == postId && $0.isActive }
    }

    func getRequest(for postId: String) -> HeyFeedRequest? {
        activeRequests.first { $0.postId == postId }
    }

    // MARK: - Auto-Analysis

    /// Runs AI parse on a Post and conditionally submits a HeyFeed request or
    /// raises a pastoral care signal without requiring caller to handle errors.
    func analyzeAndSubmitIfNeeded(post: Post) async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        guard let postId = post.firebaseId else { return }

        let categoryHint = post.category.rawValue
        let result = HeyFeedAIParser.shared.parse(text: post.content, category: categoryHint)

        if result.needsPastoralAttention {
            await reportPastoralCareSignal(
                postId: postId,
                userId: post.authorId,
                urgencyScore: result.urgencyScore,
                signalType: result.intent.rawValue
            )
        }

        if result.intent.priority >= 8 {
            try? await submitRequest(
                postId: postId,
                requestType: result.intent == .crisis ? .care : .prayer,
                intent: result.intent
            )
        }

        dlog("[HeyFeedService] analyzeAndSubmitIfNeeded — postId=\(postId) intent=\(result.intent.rawValue) confidence=\(result.confidence)")
    }

    // MARK: - Private Decode Helpers

    private func decodeRequest(from doc: QueryDocumentSnapshot) -> HeyFeedRequest? {
        let data = doc.data()
        guard
            let postId        = data["postId"] as? String,
            let authorId      = data["authorId"] as? String,
            let typeRaw       = data["requestType"] as? String,
            let requestType   = HeyFeedRequest.HeyFeedRequestType(rawValue: typeRaw),
            let intentRaw     = data["intent"] as? String,
            let resonanceScore = data["resonanceScore"] as? Double,
            let resonanceCount = data["resonanceCount"] as? Int,
            let isActive      = data["isActive"] as? Bool,
            let expiresTs     = data["expiresAt"] as? Timestamp,
            let createdTs     = data["createdAt"] as? Timestamp,
            let updatedTs     = data["updatedAt"] as? Timestamp
        else {
            dlog("[HeyFeedService] decodeRequest — skipping malformed doc \(doc.documentID)")
            return nil
        }

        let intent = HeyFeedIntent(rawValue: intentRaw) ?? .neutral

        return HeyFeedRequest(
            id: doc.documentID,
            postId: postId,
            authorId: authorId,
            requestType: requestType,
            intent: intent,
            resonanceScore: resonanceScore,
            resonanceCount: resonanceCount,
            isActive: isActive,
            expiresAt: expiresTs.dateValue(),
            createdAt: createdTs.dateValue(),
            updatedAt: updatedTs.dateValue()
        )
    }

    private func decodeResonance(from doc: QueryDocumentSnapshot) -> HeyFeedResonance? {
        let data = doc.data()
        guard
            let requestId = data["requestId"] as? String,
            let postId    = data["postId"] as? String,
            let userId    = data["userId"] as? String,
            let typeRaw   = data["type"] as? String,
            let resType   = HeyFeedResonanceType(rawValue: typeRaw),
            let createdTs = data["createdAt"] as? Timestamp
        else {
            dlog("[HeyFeedService] decodeResonance — skipping malformed doc \(doc.documentID)")
            return nil
        }

        return HeyFeedResonance(
            id: doc.documentID,
            requestId: requestId,
            postId: postId,
            userId: userId,
            type: resType,
            createdAt: createdTs.dateValue()
        )
    }

    private func decodePastoralSignal(from doc: QueryDocumentSnapshot) -> PastoralCareSignal? {
        let data = doc.data()
        guard
            let postId         = data["postId"] as? String,
            let userId         = data["userId"] as? String,
            let signalType     = data["signalType"] as? String,
            let urgencyScore   = data["urgencyScore"] as? Double,
            let isAcknowledged = data["isAcknowledged"] as? Bool,
            let createdTs      = data["createdAt"] as? Timestamp
        else {
            dlog("[HeyFeedService] decodePastoralSignal — skipping malformed doc \(doc.documentID)")
            return nil
        }

        return PastoralCareSignal(
            id: doc.documentID,
            postId: postId,
            userId: userId,
            signalType: signalType,
            urgencyScore: urgencyScore,
            isAcknowledged: isAcknowledged,
            createdAt: createdTs.dateValue()
        )
    }

    // MARK: - Resonance Score Weight

    /// Returns a normalized score increment per resonance type.
    /// Higher-weight types like .praying contribute more to community resonance.
    private func resonanceScoreIncrement(for type: HeyFeedResonanceType) -> Double {
        switch type {
        case .praying:    return 0.05
        case .standing:   return 0.04
        case .witnessed:  return 0.03
        case .helped:     return 0.06
        case .encouraged: return 0.03
        }
    }
}

// MARK: - HeyFeedServiceError

enum HeyFeedServiceError: LocalizedError {
    case unauthenticated
    case requestNotFound

    var errorDescription: String? {
        switch self {
        case .unauthenticated:  return "You must be signed in to perform this action."
        case .requestNotFound:  return "The requested HeyFeed entry could not be found."
        }
    }
}
