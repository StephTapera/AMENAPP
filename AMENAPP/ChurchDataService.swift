//
//  ChurchDataService.swift
//  AMENAPP
//
//  Church data management and Google Places integration
//  One church = one ID across the app
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit

@MainActor
class ChurchDataService {
    static let shared = ChurchDataService()
    
    private let db = Firestore.firestore()
    private init() {}
    
    // MARK: - Church Lookup
    
    /// Get church by ID (from cache or Firestore)
    func getChurch(id: String) async throws -> ChurchEntity {
        let doc = try await db.collection("churches")
            .document(id)
            .getDocument()
        
        guard let data = doc.data() else {
            throw ChurchError.notFound
        }
        
        return try Firestore.Decoder().decode(ChurchEntity.self, from: data)
    }
    
    /// Search churches near location
    func searchChurches(
        query: String,
        near location: CLLocation,
        radius: Double = 25.0  // miles
    ) async throws -> [ChurchSearchResult] {
        
        // First, check Firestore for existing churches
        let firestoreResults = try await searchFirestore(query: query, near: location, radius: radius)
        
        // If we have good results, return them
        if firestoreResults.count >= 5 {
            return firestoreResults
        }
        
        // Supplement with Apple Maps (MKLocalSearch) results when Firestore has fewer than 5 hits
        let mapsResults = await searchAppleMaps(query: query, near: location, radius: radius)
        
        // Merge: keep Firestore results first (they have full church data), append Maps results
        // that don't duplicate a church already found in Firestore (matched by name proximity)
        var combined = firestoreResults
        let existingNames = Set(firestoreResults.map { $0.name.lowercased() })
        for result in mapsResults where !existingNames.contains(result.name.lowercased()) {
            combined.append(result)
        }
        combined.sort { ($0.distance ?? Double.infinity) < ($1.distance ?? Double.infinity) }
        return combined
    }
    
    private func searchFirestore(
        query: String,
        near location: CLLocation,
        radius: Double
    ) async throws -> [ChurchSearchResult] {
        
        // Simple name search (in production, use Algolia for better search)
        let snapshot = try await db.collection("churches")
            .whereField("name", isGreaterThanOrEqualTo: query)
            .whereField("name", isLessThan: query + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        var results: [ChurchSearchResult] = []
        
        for doc in snapshot.documents {
            if let church = try? Firestore.Decoder().decode(ChurchEntity.self, from: doc.data()) {
                let distance = church.distance(from: location)
                
                // Filter by radius
                if distance <= radius {
                    results.append(ChurchSearchResult(
                        id: church.id,
                        church: church,
                        name: church.name,
                        address: church.address,
                        city: church.city,
                        distance: distance,
                        placeId: church.placeId,
                        isExisting: true,
                        photoReference: nil
                    ))
                }
            }
        }
        
        // Sort by distance
        results.sort { ($0.distance ?? Double.infinity) < ($1.distance ?? Double.infinity) }
        
        return results
    }
    
    /// Search Apple Maps for churches near a location and convert to ChurchSearchResult
    private func searchAppleMaps(
        query: String,
        near location: CLLocation,
        radius: Double
    ) async -> [ChurchSearchResult] {
        let request = MKLocalSearch.Request()
        // Use query if non-empty; otherwise fall back to generic "church"
        request.naturalLanguageQuery = query.isEmpty ? "church" : "\(query) church"
        let radiusMeters = radius * 1609.34 // miles → meters
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
        
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }
        
        return response.mapItems.compactMap { item -> ChurchSearchResult? in
            guard let name = item.name else { return nil }
            let coord = item.location.coordinate
            let itemLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distanceMiles = location.distance(from: itemLocation) / 1609.34
            guard distanceMiles <= radius else { return nil }
            
            let address: String
            if #available(iOS 26, *) {
                address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? ""
            } else {
                address = [item.placemark.subThoroughfare, item.placemark.thoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
            }
            let city = item.placemark.locality ?? ""
            
            // Build a lightweight ChurchEntity from the Maps result (no Firestore ID yet)
            let churchId = "maps_\(item.placemark.countryCode ?? "")_\(name.replacingOccurrences(of: " ", with: "_").lowercased())"
            return ChurchSearchResult(
                id: churchId,
                church: nil,
                name: name,
                address: address,
                city: city,
                distance: distanceMiles,
                placeId: nil,
                isExisting: false,
                photoReference: nil
            )
        }
    }
    
    /// Get or create a ChurchEntity from an Apple Maps MKMapItem (used when user taps a Maps result)
    func getOrCreateChurch(fromMapItem item: MKMapItem) async throws -> ChurchEntity {
        let name = item.name ?? "Unknown Church"
        let coord = item.location.coordinate
        
        // Check Firestore for existing church with same name + approximate location
        let snapshot = try await db.collection("churches")
            .whereField("name", isEqualTo: name)
            .limit(to: 5)
            .getDocuments()
        
        for doc in snapshot.documents {
            if let existing = try? Firestore.Decoder().decode(ChurchEntity.self, from: doc.data()) {
                let existingLoc = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                let mapLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                // If within 0.1 miles, treat as the same church
                if existingLoc.distance(from: mapLoc) < 160 {
                    return existing
                }
            }
        }
        
        // Not found — create a new ChurchEntity from the MapItem
        let address: String
        if #available(iOS 26, *) {
            address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? ""
        } else {
            address = [item.placemark.subThoroughfare, item.placemark.thoroughfare]
                .compactMap { $0 }.joined(separator: " ")
        }
        
        let newId = UUID().uuidString
        let newChurch = ChurchEntity(
            id: newId,
            placeId: nil,
            name: name,
            address: address,
            city: item.placemark.locality ?? "",
            state: item.placemark.administrativeArea,
            zipCode: item.placemark.postalCode,
            country: item.placemark.countryCode ?? "US",
            coordinate: ChurchEntity.GeoPoint(
                latitude: coord.latitude,
                longitude: coord.longitude
            ),
            phoneNumber: item.phoneNumber,
            email: nil,
            website: item.url?.absoluteString,
            denomination: nil,
            photoURL: nil,
            logoURL: nil,
            serviceTimes: [],
            memberCount: 0,
            visitCount: 0,
            tipCount: 0,
            createdAt: Date(),
            updatedAt: Date(),
            source: .userSubmitted
        )
        
        let data = try Firestore.Encoder().encode(newChurch)
        try await db.collection("churches").document(newId).setData(data)
        
        return newChurch
    }
    
    /// Legacy: look up by placeId string (kept for backwards compatibility)
    func getOrCreateChurch(placeId: String) async throws -> ChurchEntity {
        let existingSnapshot = try await db.collection("churches")
            .whereField("placeId", isEqualTo: placeId)
            .limit(to: 1)
            .getDocuments()
        
        if let doc = existingSnapshot.documents.first,
           let church = try? Firestore.Decoder().decode(ChurchEntity.self, from: doc.data()) {
            return church
        }
        
        throw ChurchError.notFound
    }
    
    // MARK: - Church Tags
    
    /// Create church tag for post/note/comment
    func createTag(
        churchId: String,
        context: ChurchTag.TagContext,
        contextId: String,
        distance: Double?
    ) async throws -> ChurchTag {
        
        let church = try await getChurch(id: churchId)
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChurchError.notAuthenticated
        }
        
        let tag = ChurchTag(
            id: UUID().uuidString,
            churchId: churchId,
            churchName: church.name,
            city: church.city,
            distance: distance,
            taggedAt: Date(),
            taggedBy: userId,
            context: context,
            contextId: contextId
        )
        
        // Save tag
        let tagData = try Firestore.Encoder().encode(tag)
        try await db.collection("churchTags")
            .document(tag.id)
            .setData(tagData)
        
        // Increment church tag count
        try await db.collection("churches")
            .document(churchId)
            .updateData([
                "tagCount": FieldValue.increment(Int64(1))
            ])
        
        return tag
    }
    
    /// Get all tags for a specific context
    func getTags(
        context: ChurchTag.TagContext,
        contextId: String
    ) async throws -> [ChurchTag] {
        
        let snapshot = try await db.collection("churchTags")
            .whereField("context", isEqualTo: context.rawValue)
            .whereField("contextId", isEqualTo: contextId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? Firestore.Decoder().decode(ChurchTag.self, from: doc.data())
        }
    }
    
    // MARK: - User Relations
    
    /// Set user's relationship with church
    func setRelation(
        churchId: String,
        relation: UserChurchRelation.RelationType
    ) async throws {
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChurchError.notAuthenticated
        }
        
        let relationId = "\(userId)_\(churchId)"
        
        let relationData: [String: Any] = [
            "userId": userId,
            "churchId": churchId,
            "relation": relation.rawValue,
            "since": Timestamp(date: Date()),
            "visitCount": 0
        ]
        
        try await db.collection("userChurchRelations")
            .document(relationId)
            .setData(relationData, merge: true)
        
        // Update church member/visitor count
        let field = relation == .member ? "memberCount" : "visitCount"
        try await db.collection("churches")
            .document(churchId)
            .updateData([
                field: FieldValue.increment(Int64(1))
            ])
    }
    
    /// Get user's relation with church
    func getRelation(churchId: String) async throws -> UserChurchRelation? {
        guard let userId = Auth.auth().currentUser?.uid else {
            return nil
        }
        
        let relationId = "\(userId)_\(churchId)"
        let doc = try await db.collection("userChurchRelations")
            .document(relationId)
            .getDocument()
        
        guard let data = doc.data() else { return nil }
        return try? Firestore.Decoder().decode(UserChurchRelation.self, from: data)
    }
    
    // MARK: - Church Tips
    
    /// Submit a tip for first-time visitors
    func submitTip(
        churchId: String,
        content: String,
        category: ChurchTip.TipCategory
    ) async throws -> ChurchTip {
        
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChurchError.notAuthenticated
        }
        
        // Get user info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userName = userDoc.data()?["displayName"] as? String ?? "Anonymous"
        let userPhoto = userDoc.data()?["photoURL"] as? String
        
        let tip = ChurchTip(
            id: UUID().uuidString,
            churchId: churchId,
            authorId: userId,
            authorName: userName,
            authorPhotoURL: userPhoto,
            content: content,
            category: category,
            helpfulCount: 0,
            createdAt: Date(),
            isHelpful: false
        )
        
        let tipData = try Firestore.Encoder().encode(tip)
        try await db.collection("churchTips")
            .document(tip.id)
            .setData(tipData)
        
        // Increment church tip count
        try await db.collection("churches")
            .document(churchId)
            .updateData([
                "tipCount": FieldValue.increment(Int64(1))
            ])
        
        return tip
    }
    
    /// Get tips for a church
    func getTips(
        churchId: String,
        limit: Int = 10
    ) async throws -> [ChurchTip] {
        
        let snapshot = try await db.collection("churchTips")
            .whereField("churchId", isEqualTo: churchId)
            .order(by: "helpfulCount", descending: true)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? Firestore.Decoder().decode(ChurchTip.self, from: doc.data())
        }
    }
    
    /// Mark tip as helpful
    func markTipHelpful(tipId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Check if already marked
        let helpfulId = "\(userId)_\(tipId)"
        let existing = try await db.collection("tipHelpful")
            .document(helpfulId)
            .getDocument()
        
        if existing.exists {
            // Unlike
            try await db.collection("tipHelpful").document(helpfulId).delete()
            try await db.collection("churchTips")
                .document(tipId)
                .updateData(["helpfulCount": FieldValue.increment(Int64(-1))])
        } else {
            // Like
            try await db.collection("tipHelpful")
                .document(helpfulId)
                .setData(["userId": userId, "tipId": tipId, "at": Timestamp(date: Date())])
            try await db.collection("churchTips")
                .document(tipId)
                .updateData(["helpfulCount": FieldValue.increment(Int64(1))])
        }
    }
    
    // MARK: - Profile Data
    
    /// Load complete church profile
    func loadProfile(churchId: String, userLocation: CLLocation?) async throws -> ChurchProfileData {
        let church = try await getChurch(id: churchId)
        let relation = try await getRelation(churchId: churchId)
        let tips = try await getTips(churchId: churchId, limit: 10)
        
        // Get upcoming services (this week)
        let today = Calendar.current.component(.weekday, from: Date())
        let upcomingServices = church.serviceTimes.filter { $0.dayOfWeek >= today }.sorted { $0.dayOfWeek < $1.dayOfWeek }
        
        return ChurchProfileData(
            church: church,
            userRelation: relation,
            recentTips: tips,
            upcomingServices: upcomingServices,
            isMyChurch: relation?.relation == .member,
            havePlannedVisit: relation?.relation == .interested
        )
    }
}

// MARK: - Errors

enum ChurchError: LocalizedError {
    case notFound
    case notAuthenticated
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notFound: return "Church not found"
        case .notAuthenticated: return "User not authenticated"
        case .invalidData: return "Invalid church data"
        }
    }
}
