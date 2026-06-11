// FindChurch2GatheringService.swift
// AMENAPP — Find Church 2.0, Wave 2
//
// Fetches GatheringObjects from Firestore.
// Gated by AMENFeatureFlags.shared.findChurch2GatheringsEnabled.

import Foundation
import FirebaseFirestore
import CoreLocation

// MARK: - FindChurch2GatheringService

@MainActor
final class FindChurch2GatheringService: ObservableObject {

    // MARK: - Published state

    @Published var currentChurchGatherings: [GatheringObject] = []

    // MARK: - Private

    private let db = Firestore.firestore()

    // MARK: - Public API

    /// Fetches all active, public gatherings for a given church.
    /// Returns an empty array (and clears `currentChurchGatherings`) when the flag is off.
    @discardableResult
    func fetchGatherings(for churchId: String) async throws -> [GatheringObject] {
        guard AMENFeatureFlags.shared.findChurch2GatheringsEnabled else {
            currentChurchGatherings = []
            return []
        }

        let snapshot = try await db.collection("gatherings")
            .whereField("churchId", isEqualTo: churchId)
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isPublic", isEqualTo: true)
            .getDocuments()

        let gatherings: [GatheringObject] = snapshot.documents.compactMap { doc in
            try? doc.data(as: GatheringObject.self)
        }

        currentChurchGatherings = gatherings
        return gatherings
    }

    /// Fetches standalone gatherings (no required parent church) near a coordinate.
    /// Uses a bounding-box pre-filter on `coordinate.latitude` / `coordinate.longitude`,
    /// then sorts by distance client-side. Limited to 20 results.
    ///
    /// Note: Firestore does not support true geopoint range queries on compound fields,
    /// so we apply a ±degree bounding box and sort client-side.
    func fetchStandaloneGatherings(near location: CLLocationCoordinate2D,
                                   radiusMiles: Double) async throws -> [GatheringObject] {
        guard AMENFeatureFlags.shared.findChurch2GatheringsEnabled else { return [] }

        // 1 degree latitude ≈ 69 miles; use a generous bounding box for the initial query
        let latDelta = radiusMiles / 69.0
        // 1 degree longitude ≈ 69 * cos(lat) miles
        let lonDelta = radiusMiles / (69.0 * max(cos(location.latitude * .pi / 180), 0.01))

        let minLat = location.latitude  - latDelta
        let maxLat = location.latitude  + latDelta
        let minLon = location.longitude - lonDelta
        let maxLon = location.longitude + lonDelta

        // Firestore range on one field + equality on others
        let snapshot = try await db.collection("gatherings")
            .whereField("isDeleted",  isEqualTo: false)
            .whereField("isPublic",   isEqualTo: true)
            .whereField("coordinate.latitude", isGreaterThanOrEqualTo: minLat)
            .whereField("coordinate.latitude", isLessThanOrEqualTo: maxLat)
            .limit(to: 40)           // over-fetch; we'll trim after lon + distance filtering
            .getDocuments()

        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        let gatherings: [GatheringObject] = snapshot.documents
            .compactMap { doc in try? doc.data(as: GatheringObject.self) }
            .filter { gathering in
                // Apply longitude filter client-side (second range Firestore can't do)
                guard let coord = gathering.coordinate else { return false }
                guard coord.longitude >= minLon && coord.longitude <= maxLon else { return false }
                // Exact distance check
                return coord.distance(from: clLocation) <= radiusMiles
            }
            .sorted { a, b in
                let da = a.coordinate?.distance(from: clLocation) ?? .greatestFiniteMagnitude
                let db = b.coordinate?.distance(from: clLocation) ?? .greatestFiniteMagnitude
                return da < db
            }
            .prefix(20)
            .map { $0 }

        return gatherings
    }
}
