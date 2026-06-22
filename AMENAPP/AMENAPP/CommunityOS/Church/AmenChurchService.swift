// AmenChurchService.swift
// AMEN Community OS — Church OS (Phase 3 / Agent A8)
//
// Canonical Church OS service layer:
//   - Fetch church profiles from Firestore
//   - Church search (Firestore prefix query; Algolia upgrade path stubbed)
//   - Follow / unfollow via AmenEdgeService (edges collection)
//   - Church Passport management (stamps + home church)
//   - Nearby church geo-queries (Firestore lat/lng bounding box + client-side sort)
//   - Visit readiness summary
//
// Rules:
//   - @MainActor / async-await only — no Combine
//   - Soft-delete only (isDeleted = true)
//   - memberCount / followersCount / visitCount NEVER exposed in any UI
//   - Location gracefully degrades: methods that accept a nil location fall back
//     to text-only results rather than throwing

import Foundation
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

// MARK: - AmenChurchService

@MainActor
final class AmenChurchService: ObservableObject {

    // MARK: - Published state

    @Published var church: ChurchOSProfile?
    @Published var nearbyChurches: [ChurchOSProfile] = []
    @Published var passport: ChurchPassport?
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private let edgeService = AmenEdgeService()

    // MARK: - fetchChurch

    /// Fetches a single church profile by Firestore document ID.
    func fetchChurch(id: String) async throws {
        isLoading = true
        defer { isLoading = false }
        error = nil

        let doc = try await db.collection("churches").document(id).getDocument()
        guard let data = doc.data(), !(data["isDeleted"] as? Bool ?? false) else {
            throw ChurchOSError.notFound(id)
        }
        church = Self.parseProfile(doc: doc, data: data)
    }

    // MARK: - searchChurches

    /// Searches churches by name query and optional filters.
    /// Uses Firestore prefix range query on the `name` field.
    /// Algolia upgrade: replace the Firestore query with an Algolia call while keeping this signature.
    func searchChurches(
        query: String,
        near location: CLLocationCoordinate2D?,
        denomination: String?,
        style: ServiceStyle?
    ) async throws -> [ChurchOSProfile] {
        isLoading = true
        defer { isLoading = false }
        error = nil

        var firestoreQuery: Query = db.collection("churches")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isActive", isEqualTo: true)

        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let end = query + "\u{f8ff}"
            firestoreQuery = firestoreQuery
                .whereField("name", isGreaterThanOrEqualTo: query)
                .whereField("name", isLessThanOrEqualTo: end)
        }

        if let denomination {
            firestoreQuery = firestoreQuery.whereField("denomination", isEqualTo: denomination)
        }

        let snapshot = try await firestoreQuery.limit(to: 50).getDocuments()
        var results: [ChurchOSProfile] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            return Self.parseProfile(doc: doc, data: data)
        }

        // ServiceStyle filter is client-side (nested array field)
        if let style {
            results = results.filter { profile in
                profile.campuses.contains { campus in
                    campus.serviceTimes.contains { $0.serviceStyle == style }
                }
            }
        }

        if let location {
            results = results.sorted { a, b in
                distanceMiles(from: location, to: a) < distanceMiles(from: location, to: b)
            }
        }

        return results
    }

    // MARK: - followChurch

    /// Creates a `follows` edge (user → church) and a convenience record in /churchFollowers.
    func followChurch(churchId: String, userId: String) async throws {
        _ = try await edgeService.createEdge(
            fromRef:    "/users/\(userId)",
            fromType:   .user,
            toRef:      "/churches/\(churchId)",
            toType:     .church,
            edgeType:   .follows,
            createdBy:  userId,
            visibility: "private"
        )

        try await db
            .collection("churchFollowers")
            .document(userId)
            .collection("churches")
            .document(churchId)
            .setData([
                "churchId":   churchId,
                "userId":     userId,
                "followedAt": FieldValue.serverTimestamp(),
                "isDeleted":  false
            ])
    }

    // MARK: - unfollowChurch

    /// Soft-deletes the follows edge and the convenience churchFollowers record.
    func unfollowChurch(churchId: String, userId: String) async throws {
        let edgesSnap = try await db.collection("edges")
            .whereField("fromRef", isEqualTo: "/users/\(userId)")
            .whereField("toRef", isEqualTo: "/churches/\(churchId)")
            .whereField("edgeType", isEqualTo: "follows")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        let batch = db.batch()
        for doc in edgesSnap.documents {
            batch.updateData(["isDeleted": true], forDocument: doc.reference)
        }

        let convRef = db
            .collection("churchFollowers")
            .document(userId)
            .collection("churches")
            .document(churchId)
        batch.updateData(["isDeleted": true], forDocument: convRef)

        try await batch.commit()
    }

    // MARK: - checkInToService

    /// Records a service check-in by creating a ChurchPassport stamp.
    func checkInToService(churchId: String, serviceTimeId: String, userId: String) async throws {
        let churchDoc = try? await db.collection("churches").document(churchId).getDocument()
        let churchName = churchDoc?.data()?["name"] as? String ?? "Church"
        try await addPassportStamp(
            churchId:   churchId,
            churchName: churchName,
            date:       Date(),
            notes:      "Service check-in",
            userId:     userId
        )
    }

    // MARK: - loadPassport

    /// Loads a user's ChurchPassport from Firestore.
    func loadPassport(userId: String) async throws {
        isLoading = true
        defer { isLoading = false }
        error = nil

        let doc = try await db.collection("churchPassports").document(userId).getDocument()

        if let data = doc.data() {
            passport = Self.parsePassport(doc: doc, data: data)
        } else {
            passport = ChurchPassport(
                id:             userId,
                userId:         userId,
                stamps:         [],
                currentChurchId: nil,
                homeChurchId:   nil,
                isPrivate:      true,
                visitCount:     0,
                createdAt:      Date(),
                updatedAt:      Date()
            )
        }
    }

    // MARK: - addPassportStamp

    /// Adds a new stamp to the user's ChurchPassport. Creates the document if absent.
    func addPassportStamp(
        churchId: String,
        churchName: String,
        date: Date,
        notes: String?,
        userId: String
    ) async throws {
        let stamp = ChurchPassportStamp(
            churchId:   churchId,
            churchName: churchName,
            visitDate:  date,
            notes:      notes,
            isPrivate:  true
        )

        let passportRef = db.collection("churchPassports").document(userId)
        let existing = try? await passportRef.getDocument()
        var stamps: [[String: Any]] = existing?.data()?["stamps"] as? [[String: Any]] ?? []

        let stampData: [String: Any] = [
            "id":         stamp.id,
            "churchId":   stamp.churchId,
            "churchName": stamp.churchName,
            "visitDate":  Timestamp(date: stamp.visitDate),
            "isPrivate":  stamp.isPrivate
        ]
        var mutable = stampData
        if let n = stamp.notes { mutable["notes"] = n }
        stamps.append(mutable)

        // visitCount stored but never surfaced in UI (PRIVATE)
        try await passportRef.setData([
            "id":         userId,
            "userId":     userId,
            "stamps":     stamps,
            "isPrivate":  true,
            "visitCount": stamps.count,
            "updatedAt":  FieldValue.serverTimestamp()
        ], merge: true)

        try await loadPassport(userId: userId)
    }

    // MARK: - getNearbyChurches

    /// Returns churches within radiusMiles of location, sorted by distance.
    /// Uses bounding-box lat/lng query; no GeoHash required at this scale.
    func getNearbyChurches(
        location: CLLocationCoordinate2D,
        radiusMiles: Double
    ) async throws -> [ChurchOSProfile] {
        isLoading = true
        defer { isLoading = false }
        error = nil

        let latDelta = radiusMiles / 69.0
        let lngDelta = radiusMiles / (69.0 * cos(location.latitude * .pi / 180))
        let minLat = location.latitude - latDelta
        let maxLat = location.latitude + latDelta
        let minLng = location.longitude - lngDelta
        let maxLng = location.longitude + lngDelta

        let snapshot = try await db.collection("churches")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isActive", isEqualTo: true)
            .whereField("latitude", isGreaterThanOrEqualTo: minLat)
            .whereField("latitude", isLessThanOrEqualTo: maxLat)
            .limit(to: 100)
            .getDocuments()

        var results: [ChurchOSProfile] = snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let lng = data["longitude"] as? Double,
                  lng >= minLng, lng <= maxLng else { return nil }
            return Self.parseProfile(doc: doc, data: data)
        }

        results = results.sorted { a, b in
            distanceMiles(from: location, to: a) < distanceMiles(from: location, to: b)
        }

        nearbyChurches = results
        return results
    }

    // MARK: - getVisitReadiness

    /// Returns first-timer tips, today's service time, parking, and accessibility info.
    func getVisitReadiness(churchId: String) async throws -> VisitReadiness {
        let doc = try? await db.collection("churches").document(churchId).getDocument()

        var profile: ChurchOSProfile?
        if let d = doc, let data = d.data() {
            profile = Self.parseProfile(doc: d, data: data)
        }

        let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1
        let serviceTimeToday = profile?.campuses
            .flatMap { $0.serviceTimes }
            .first { $0.dayOfWeek == todayWeekday }

        let readinessDoc = try? await db
            .collection("churches")
            .document(churchId)
            .collection("visitReadiness")
            .document("default")
            .getDocument()
        let rd = readinessDoc?.data() ?? [:]

        let churchData = doc?.data() ?? [:]
        let tips = rd["firstTimerTips"] as? [String] ?? [
            "Arrive 10 minutes early to get settled.",
            "Coffee and a warm welcome await you!",
            "Parking is free — ask an usher for directions."
        ]

        return VisitReadiness(
            churchId:           churchId,
            firstTimerTips:     tips,
            serviceTimeToday:   serviceTimeToday,
            parkingInfo:        rd["parkingInfo"] as? String ?? (churchData["parkingInfo"] as? String),
            childcareAvailable: rd["childcareAvailable"] as? Bool ?? false,
            accessibilityInfo:  rd["accessibilityInfo"] as? String
        )
    }

    // MARK: - Private parsing helpers

    static func parseProfile(doc: DocumentSnapshot, data: [String: Any]) -> ChurchOSProfile? {
        guard let name = data["name"] as? String else { return nil }

        let campusData = data["campuses"] as? [[String: Any]] ?? []
        let campuses: [ChurchCampus] = campusData.compactMap { cd in
            guard let campusId   = cd["id"] as? String,
                  let campusName = cd["name"] as? String else { return nil }
            let stData = cd["serviceTimes"] as? [[String: Any]] ?? []
            let times: [AmenServiceTime] = stData.compactMap { st in
                guard let stId      = st["id"] as? String,
                      let dow       = st["dayOfWeek"] as? Int,
                      let start     = st["startTime"] as? String,
                      let styleRaw  = st["serviceStyle"] as? String,
                      let style     = ServiceStyle(rawValue: styleRaw) else { return nil }
                return AmenServiceTime(
                    id:           stId,
                    dayOfWeek:    dow,
                    startTime:    start,
                    endTime:      st["endTime"] as? String,
                    location:     st["location"] as? String ?? "Main Campus",
                    isOnline:     st["isOnline"] as? Bool ?? false,
                    streamUrl:    st["streamUrl"] as? String,
                    serviceStyle: style
                )
            }
            return ChurchCampus(
                id:           campusId,
                name:         campusName,
                address:      cd["address"] as? String ?? "",
                city:         cd["city"] as? String ?? "",
                state:        cd["state"] as? String ?? "",
                zipCode:      cd["zipCode"] as? String ?? "",
                latitude:     cd["latitude"] as? Double,
                longitude:    cd["longitude"] as? Double,
                isPrimary:    cd["isPrimary"] as? Bool ?? false,
                serviceTimes: times,
                phoneNumber:  cd["phoneNumber"] as? String,
                websiteUrl:   cd["websiteUrl"] as? String
            )
        }

        let size = ChurchSize(rawValue: data["size"] as? String ?? "medium") ?? .medium

        return ChurchOSProfile(
            id:                   doc.documentID,
            name:                 name,
            denomination:         data["denomination"] as? String,
            bio:                  data["bio"] as? String ?? "",
            coverImageUrl:        data["coverImageUrl"] as? String ?? data["heroImageURL"] as? String,
            logoUrl:              data["logoUrl"] as? String ?? data["logoURL"] as? String,
            campuses:             campuses,
            size:                 size,
            foundedYear:          data["foundedYear"] as? Int,
            seniorPastorName:     data["seniorPastorName"] as? String,
            website:              data["website"] as? String ?? data["websiteURL"] as? String,
            socialLinks:          data["socialLinks"] as? [String: String] ?? [:],
            isVerified:           data["isVerified"] as? Bool ?? data["verifiedMinistry"] as? Bool ?? false,
            verificationBadge:    data["verificationBadge"] as? String,
            missionStatement:     data["missionStatement"] as? String,
            sermonSeriesRef:      data["sermonSeriesRef"] as? String,
            memberCount:          data["memberCount"] as? Int ?? 0,   // PRIVATE
            followersCount:       0,                                    // PRIVATE
            givingEnabled:        data["givingEnabled"] as? Bool ?? false,
            givingPlatformRef:    data["givingPlatformRef"] as? String,
            prayerRequestsEnabled: data["prayerRequestsEnabled"] as? Bool ?? true,
            churchNotesEnabled:   data["churchNotesEnabled"] as? Bool ?? true,
            createdBy:            data["createdBy"] as? String ?? "",
            createdAt:            (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt:            (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            isDeleted:            data["isDeleted"] as? Bool ?? false,
            isActive:             data["isActive"] as? Bool ?? true
        )
    }

    static func parsePassport(doc: DocumentSnapshot, data: [String: Any]) -> ChurchPassport? {
        guard let userId = data["userId"] as? String else { return nil }
        let stampsData = data["stamps"] as? [[String: Any]] ?? []
        let stamps: [ChurchPassportStamp] = stampsData.compactMap { sd in
            guard let stampId    = sd["id"] as? String,
                  let churchId   = sd["churchId"] as? String,
                  let churchName = sd["churchName"] as? String else { return nil }
            return ChurchPassportStamp(
                id:           stampId,
                churchId:     churchId,
                churchName:   churchName,
                churchLogoUrl: sd["churchLogoUrl"] as? String,
                visitDate:    (sd["visitDate"] as? Timestamp)?.dateValue() ?? Date(),
                notes:        sd["notes"] as? String,
                isPrivate:    sd["isPrivate"] as? Bool ?? true
            )
        }
        return ChurchPassport(
            id:              doc.documentID,
            userId:          userId,
            stamps:          stamps,
            currentChurchId: data["currentChurchId"] as? String,
            homeChurchId:    data["homeChurchId"] as? String,
            isPrivate:       data["isPrivate"] as? Bool ?? true,
            visitCount:      data["visitCount"] as? Int ?? stamps.count,  // PRIVATE
            createdAt:       (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt:       (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Distance helper

    func distanceMiles(from coord: CLLocationCoordinate2D, to profile: ChurchOSProfile) -> Double {
        let primary = profile.campuses.first { $0.isPrimary } ?? profile.campuses.first
        guard let lat = primary?.latitude, let lng = primary?.longitude else { return .infinity }
        let from = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let to   = CLLocation(latitude: lat, longitude: lng)
        return from.distance(from: to) / 1609.344
    }
}

// MARK: - ChurchOSError

enum ChurchOSError: LocalizedError {
    case notFound(String)
    case unauthorized
    case firestoreError(Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Church \"\(id)\" could not be found."
        case .unauthorized:
            return "You don't have permission to access this church."
        case .firestoreError(let err):
            return err.localizedDescription
        }
    }
}
