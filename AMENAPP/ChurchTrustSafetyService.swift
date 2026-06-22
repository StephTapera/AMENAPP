import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - ChurchTrustSafety Stubs

struct ChurchAdminProfile: Decodable {
    var uid: String
    var churchId: String
    var displayName: String?
    var email: String?
    var role: String?
    var isVerified: Bool?
}

struct ChurchVerificationRequest {
    var churchId: String
    var contactEmail: String
    var claimedDomain: String?
    var websiteProofURL: String?
    var livestreamProofURL: String?
    var notes: String?
}

struct ChurchAdminEditableProfile {
    struct ServiceTime {
        var dayOfWeek: Int
        var time: String
        var serviceType: String?
    }
    var churchId: String
    var displayDescription: String?
    var serviceTimes: [ServiceTime]
    var livestreamURL: String?
    var accessibilityInfo: [String: Any]
    var parkingInfo: String?
    var ministries: [String]
    var events: [String]
    var prayerNights: [String]
    var firstTimeVisitorInfo: String?
}

struct ChurchModerationQueueItem: Decodable {
    var id: String
    var churchId: String?
    var contentType: String?
    var contentId: String?
    var reportReason: String?
    var status: String?
}

struct ChurchModerationDecisionPayload {
    enum Decision: String {
        case approve, reject, escalate, dismiss
    }
    var queueItemId: String
    var decision: Decision
    var reasons: [String]
    var reviewerNote: String?
    var reversible: Bool
}

struct ChurchQualitySnapshot: Decodable {
    var score: Double?
    var completionRatio: Double?
    var flagCount: Int?
    var verifiedAt: Date?
}

@MainActor
final class ChurchTrustSafetyService {
    static let shared = ChurchTrustSafetyService()

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    private init() {}

    func loadAdminProfile(uid: String) async throws -> ChurchAdminProfile? {
        let snapshot = try await db.collection("church_admins").document(uid).getDocument()
        guard let data = snapshot.data() else { return nil }
        return try Firestore.Decoder().decode(ChurchAdminProfile.self, from: data)
    }

    func submitVerificationRequest(_ request: ChurchVerificationRequest) async throws {
        let callable = functions.httpsCallable("submitChurchVerificationRequest")
        _ = try await callable.call([
            "churchId": request.churchId,
            "contactEmail": request.contactEmail,
            "claimedDomain": request.claimedDomain as Any,
            "websiteProofURL": request.websiteProofURL as Any,
            "livestreamProofURL": request.livestreamProofURL as Any,
            "notes": request.notes as Any,
        ])
    }

    func submitChurchProfileUpdate(_ profile: ChurchAdminEditableProfile) async throws {
        let callable = functions.httpsCallable("submitChurchProfileUpdate")
        let serviceTimes = profile.serviceTimes.map { service in
            [
                "dayOfWeek": service.dayOfWeek,
                "time": service.time,
                "serviceType": service.serviceType as Any,
            ]
        }

        _ = try await callable.call([
            "churchId": profile.churchId,
            "displayDescription": profile.displayDescription as Any,
            "serviceTimes": serviceTimes,
            "livestreamURL": profile.livestreamURL as Any,
            "accessibilityInfo": profile.accessibilityInfo,
            "parkingInfo": profile.parkingInfo as Any,
            "ministries": profile.ministries,
            "events": profile.events,
            "prayerNights": profile.prayerNights,
            "firstTimeVisitorInfo": profile.firstTimeVisitorInfo as Any,
        ])
    }

    func fetchModerationQueue(churchId: String? = nil, limit: Int = 50) async throws -> [ChurchModerationQueueItem] {
        var query: Query = db.collection("moderation_queue").limit(to: limit)
        if let churchId, !churchId.isEmpty {
            query = query.whereField("churchId", isEqualTo: churchId)
        }

        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { document in
            try? Firestore.Decoder().decode(ChurchModerationQueueItem.self, from: document.data())
        }
    }

    func reviewModerationItem(_ payload: ChurchModerationDecisionPayload) async throws {
        let callable = functions.httpsCallable("reviewChurchModerationItem")
        _ = try await callable.call([
            "queueItemId": payload.queueItemId,
            "decision": payload.decision.rawValue,
            "reasons": payload.reasons,
            "reviewerNote": payload.reviewerNote as Any,
            "reversible": payload.reversible,
        ])
    }

    func requestLivestreamRefresh(churchId: String) async throws {
        let callable = functions.httpsCallable("refreshChurchLivestreamState")
        _ = try await callable.call(["churchId": churchId])
    }

    func loadQualitySnapshot(churchId: String) async throws -> ChurchQualitySnapshot? {
        let snapshot = try await db.collection("churches")
            .document(churchId)
            .collection("quality")
            .document("current")
            .getDocument()

        guard let data = snapshot.data() else { return nil }
        return try Firestore.Decoder().decode(ChurchQualitySnapshot.self, from: data)
    }
}
