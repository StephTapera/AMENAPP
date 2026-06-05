// AmenPrayerService.swift
// AMEN App — CommunityOS / Prayer OS (Phase 2 — Agent A7)
//
// Firestore-backed service for prayer requests and rooms.
//
// Privacy rules enforced here:
//   - ownerUidEncrypted is NEVER written by the client.
//     The Cloud Function `recordPrayer` sets it server-side.
//   - prayerCount is private — the client creates a praysFor edge via
//     AmenEdgeService; the CF handles the counter increment.
//   - Anonymous requests: displayAuthorName = "Anonymous", churchRef = nil,
//     spaceRef = nil — the CF canonicalises these before writing.
//   - All deletions are soft-delete only (isDeleted = true).
//   - Reminders are local UNUserNotificationCenter notifications; opt-in only.
//
// Collections:
//   /prayers/{prayerId}              — AmenPrayerRequest documents
//   /prayers/{id}/followUps/{fid}    — AmenPrayerFollowUp sub-collection
//   /prayerRooms/{roomId}            — AmenPrayerRoom documents
//   /edges/{edgeId}                  — praysFor edges (via AmenEdgeService)

import Foundation
import FirebaseFirestore
import UserNotifications

@MainActor
final class AmenPrayerService: ObservableObject {

    // MARK: - Published State

    @Published var prayerRequests: [AmenPrayerRequest] = []
    @Published var rooms: [AmenPrayerRoom] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private let edgeService = AmenEdgeService()

    private var prayersCollection: CollectionReference {
        db.collection("prayers")
    }

    private var roomsCollection: CollectionReference {
        db.collection("prayerRooms")
    }

    // MARK: - createPrayerRequest

    /// Creates a new prayer request in Firestore.
    ///
    /// Anonymous rules:
    ///   - When isAnonymous == true, `displayAuthorName` is sent as "Anonymous"
    ///     and `churchRef` / `spaceRef` are cleared client-side.
    ///   - `ownerUidEncrypted` is NEVER set from the client.
    ///     The server Cloud Function sets it after receiving the write.
    ///
    /// - Returns: The new Firestore document ID.
    func createPrayerRequest(
        title: String,
        body: String,
        privacy: PrayerPrivacyLevel,
        isAnonymous: Bool,
        churchRef: String?,
        spaceRef: String?,
        tags: [String],
        creatorId: String,
        provenance: SpawnProvenance?
    ) async throws -> String {
        let docRef = prayersCollection.document()
        let docId = docRef.documentID

        // Identity shielding: strip identity fields for anonymous requests.
        let authorName  = isAnonymous ? "Anonymous" : ""
        let churchField = isAnonymous ? nil : churchRef
        let spaceField  = isAnonymous ? nil : spaceRef

        var payload: [String: Any] = [
            "id":                docId,
            "_type":             "prayer",
            "title":             title,
            "body":              body,
            "privacyLevel":      privacy.rawValue,
            "isAnonymous":       isAnonymous,
            // ownerUidEncrypted is NEVER set here — CF sets it server-side.
            "displayAuthorName": authorName,
            "tags":              tags,
            "prayerCount":       0,
            "followUps":         [] as [Any],
            "isAnswered":        false,
            "reminderScheduled": false,
            "createdBy":         creatorId,
            "createdAt":         FieldValue.serverTimestamp(),
            "updatedAt":         FieldValue.serverTimestamp(),
            "isDeleted":         false
        ]

        if let church = churchField { payload["churchRef"] = church }
        if let space  = spaceField  { payload["spaceRef"]  = space }

        if let prov = provenance {
            payload["provenance"] = [
                "sourceType":    prov.sourceType,
                "sourceRef":     prov.sourceRef as Any,
                "sourceOwnerId": prov.sourceOwnerId as Any,
                "intent":        prov.intent,
                "createdAt":     FieldValue.serverTimestamp()
            ]
        }

        try await docRef.setData(payload)
        return docId
    }

    // MARK: - loadPrayerRequests

    /// Loads prayer requests filtered by context and privacy level.
    ///
    /// Context rules:
    ///   - .personal(uid)   → createdBy == uid, any privacy level
    ///   - .church(ref)     → churchRef == ref, privacyLevel IN [church, public, anonymous]
    ///   - .space(ref)      → spaceRef == ref, privacyLevel IN [space, public, anonymous]
    ///   - .public           → privacyLevel IN [public, anonymous]
    ///
    /// All queries filter isDeleted == false. Sorted by createdAt DESC. Capped at `limit`.
    func loadPrayerRequests(context: PrayerContext, limit: Int = 50) async throws {
        isLoading = true
        defer { isLoading = false }

        let query: Query

        switch context {
        case .personal(let uid):
            query = prayersCollection
                .whereField("createdBy", isEqualTo: uid)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

        case .church(let ref):
            query = prayersCollection
                .whereField("churchRef", isEqualTo: ref)
                .whereField("isDeleted", isEqualTo: false)
                .whereField("privacyLevel", in: [
                    PrayerPrivacyLevel.church.rawValue,
                    PrayerPrivacyLevel.public.rawValue,
                    PrayerPrivacyLevel.anonymous.rawValue
                ])
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

        case .space(let ref):
            query = prayersCollection
                .whereField("spaceRef", isEqualTo: ref)
                .whereField("isDeleted", isEqualTo: false)
                .whereField("privacyLevel", in: [
                    PrayerPrivacyLevel.space.rawValue,
                    PrayerPrivacyLevel.public.rawValue,
                    PrayerPrivacyLevel.anonymous.rawValue
                ])
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

        case .public:
            query = prayersCollection
                .whereField("isDeleted", isEqualTo: false)
                .whereField("privacyLevel", in: [
                    PrayerPrivacyLevel.public.rawValue,
                    PrayerPrivacyLevel.anonymous.rawValue
                ])
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        }

        let snapshot = try await query.getDocuments()
        prayerRequests = snapshot.documents.compactMap { parsePrayerRequest($0) }
    }

    // MARK: - prayForRequest

    /// Records that `userId` is praying for the given request.
    ///
    /// Creates a `praysFor` edge via `AmenEdgeService`.
    /// The Cloud Function listens on edge creation and increments `prayerCount`
    /// server-side. The client never increments `prayerCount` directly.
    func prayForRequest(_ requestId: String, userId: String) async throws {
        _ = try await edgeService.createEdge(
            fromRef:    "/users/\(userId)",
            fromType:   .user,
            toRef:      "/prayers/\(requestId)",
            toType:     .prayer,
            edgeType:   .praysFor,
            createdBy:  userId,
            visibility: "private"          // praysFor edges are private (C1 §4c)
        )
    }

    // MARK: - addFollowUp

    /// Adds a follow-up update or testimony to a prayer request.
    /// Writes to the /prayers/{id}/followUps sub-collection.
    func addFollowUp(
        to requestId: String,
        type: AmenPrayerUpdateType,
        body: String,
        authorId: String
    ) async throws {
        let followUpRef = prayersCollection
            .document(requestId)
            .collection("followUps")
            .document()

        let payload: [String: Any] = [
            "id":               followUpRef.documentID,
            "prayerRequestId":  requestId,
            "authorId":         authorId,
            "type":             type.rawValue,
            "body":             body,
            "isTestimony":      type == .testimony,
            "createdAt":        FieldValue.serverTimestamp(),
            "isDeleted":        false
        ]

        try await followUpRef.setData(payload)

        // If marking as answered, also update the parent document.
        if type == .answered {
            try await prayersCollection.document(requestId).updateData([
                "isAnswered": true,
                "updatedAt":  FieldValue.serverTimestamp()
            ])
        }

        // If closing, mark the parent request as deleted-equivalent via soft flag.
        if type == .closeRequest {
            try await prayersCollection.document(requestId).updateData([
                "isDeleted": true,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        }
    }

    // MARK: - markAnswered

    /// Marks a prayer request as answered, with an optional note.
    /// Only the request owner (authorId == creatorId check at Firestore rules level)
    /// should be able to call this.
    func markAnswered(requestId: String, note: String?, authorId: String) async throws {
        var update: [String: Any] = [
            "isAnswered": true,
            "updatedAt":  FieldValue.serverTimestamp()
        ]
        if let note {
            update["answeredNote"] = note
        }
        try await prayersCollection.document(requestId).updateData(update)
    }

    // MARK: - softDelete

    /// Soft-deletes a prayer request. Hard delete is never performed client-side.
    func softDelete(requestId: String, authorId: String) async throws {
        try await prayersCollection.document(requestId).updateData([
            "isDeleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        // Update local state immediately.
        prayerRequests.removeAll { $0.id == requestId }
    }

    // MARK: - scheduleReminder

    /// Schedules a local UNUserNotificationCenter reminder for a prayer request.
    /// Opt-in only — the owner must explicitly call this.
    /// Uses local notifications only; no push (avoids notification-manipulation concern).
    func scheduleReminder(for requestId: String, date: Date) async throws {
        let center = UNUserNotificationCenter.current()

        // Request permission if not already granted.
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus != .denied else { return }

        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { return }
        }

        // Build the notification.
        let content = UNMutableNotificationContent()
        content.title = "Prayer Follow-Up"
        content.body  = "You set a reminder to follow up on this prayer request."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "prayer_reminder_\(requestId)",
            content: content,
            trigger: trigger
        )

        try await center.add(request)

        // Mark reminderScheduled on the Firestore document.
        try await prayersCollection.document(requestId).updateData([
            "reminderScheduled": true,
            "updatedAt":         FieldValue.serverTimestamp()
        ])
    }

    // MARK: - createRoom

    /// Creates a new prayer room document in /prayerRooms.
    /// - Returns: The new Firestore document ID.
    func createRoom(
        title: String,
        hostId: String,
        privacy: PrayerPrivacyLevel,
        scheduledAt: Date?
    ) async throws -> String {
        let docRef = roomsCollection.document()
        var payload: [String: Any] = [
            "id":               docRef.documentID,
            "title":            title,
            "hostId":           hostId,
            "coHostIds":        [] as [String],
            "participantIds":   [hostId],
            "privacyLevel":     privacy.rawValue,
            "isLive":           scheduledAt == nil,
            "prayerRequestRefs": [] as [String],
            "createdAt":        FieldValue.serverTimestamp(),
            "isDeleted":        false
        ]

        if let date = scheduledAt {
            payload["scheduledAt"] = Timestamp(date: date)
        }

        try await docRef.setData(payload)
        return docRef.documentID
    }

    // MARK: - loadRooms

    /// Loads live and scheduled prayer rooms (not deleted, sorted by createdAt DESC).
    func loadRooms(limit: Int = 20) async throws {
        let snapshot = try await roomsCollection
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        rooms = snapshot.documents.compactMap { parsePrayerRoom($0) }
    }

    // MARK: - Private Parsers

    private func parsePrayerRequest(_ doc: DocumentSnapshot) -> AmenPrayerRequest? {
        guard let data = doc.data(),
              let title       = data["title"]       as? String,
              let body        = data["body"]        as? String,
              let privacyRaw  = data["privacyLevel"] as? String,
              let privacy     = PrayerPrivacyLevel(rawValue: privacyRaw),
              let isAnonymous = data["isAnonymous"] as? Bool,
              let authorName  = data["displayAuthorName"] as? String,
              let isAnswered  = data["isAnswered"]  as? Bool,
              let createdBy   = data["createdBy"]   as? String,
              let isDeleted   = data["isDeleted"]   as? Bool
        else { return nil }

        let createdAt: Date
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }

        let updatedAt: Date
        if let ts = data["updatedAt"] as? Timestamp {
            updatedAt = ts.dateValue()
        } else {
            updatedAt = createdAt
        }

        return AmenPrayerRequest(
            id:                doc.documentID,
            title:             title,
            body:              body,
            privacyLevel:      privacy,
            isAnonymous:       isAnonymous,
            ownerUidEncrypted: nil,   // NEVER read from client; always nil here
            displayAuthorName: authorName,
            churchRef:         data["churchRef"] as? String,
            spaceRef:          data["spaceRef"]  as? String,
            tags:              data["tags"]       as? [String] ?? [],
            prayerCount:       0,     // private; not read from client
            followUps:         [],    // loaded separately from sub-collection
            isAnswered:        isAnswered,
            answeredNote:      data["answeredNote"] as? String,
            reminderScheduled: data["reminderScheduled"] as? Bool ?? false,
            provenance:        nil,   // provenance struct not needed for feed rendering
            createdBy:         createdBy,
            createdAt:         createdAt,
            updatedAt:         updatedAt,
            isDeleted:         isDeleted
        )
    }

    private func parsePrayerRoom(_ doc: DocumentSnapshot) -> AmenPrayerRoom? {
        guard let data = doc.data(),
              let title      = data["title"]      as? String,
              let hostId     = data["hostId"]     as? String,
              let privacyRaw = data["privacyLevel"] as? String,
              let privacy    = PrayerPrivacyLevel(rawValue: privacyRaw),
              let isLive     = data["isLive"]     as? Bool,
              let isDeleted  = data["isDeleted"]  as? Bool
        else { return nil }

        let createdAt: Date
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }

        let scheduledAt: Date?
        if let ts = data["scheduledAt"] as? Timestamp {
            scheduledAt = ts.dateValue()
        } else {
            scheduledAt = nil
        }

        let endedAt: Date?
        if let ts = data["endedAt"] as? Timestamp {
            endedAt = ts.dateValue()
        } else {
            endedAt = nil
        }

        return AmenPrayerRoom(
            id:                doc.documentID,
            title:             title,
            hostId:            hostId,
            coHostIds:         data["coHostIds"]        as? [String] ?? [],
            participantIds:    data["participantIds"]   as? [String] ?? [],
            privacyLevel:      privacy,
            isLive:            isLive,
            scheduledAt:       scheduledAt,
            endedAt:           endedAt,
            prayerRequestRefs: data["prayerRequestRefs"] as? [String] ?? [],
            createdAt:         createdAt,
            isDeleted:         isDeleted
        )
    }
}
