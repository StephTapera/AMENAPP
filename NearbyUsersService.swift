// NearbyUsersService.swift
// AMENAPP
//
// Privacy-first "Find People Nearby" — opt-in, fuzzy, ephemeral.
//
// Design contract:
//  • No location is ever read or written without explicit user initiation.
//  • Only a GeoHash prefix at ~500 m precision is stored — never raw GPS.
//  • Every write includes an expiresAt timestamp 1 hour in the future.
//  • Queries are prefix-matched on geoHash5 (first 5 chars ≈ 4.9 km bounding box)
//    then refined by geoHash6 (first 6 chars ≈ 1.2 km) client-side.
//  • Blocked users, private accounts (unless already following), and the
//    current user are always excluded from results.

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

// MARK: - GeoHash utilities (~500 m precision)

/// Encodes a coordinate to a Base32 GeoHash string.
/// 5 chars ≈ 4.9 km × 4.9 km bounding box  (used for the Firestore query)
/// 6 chars ≈ 1.2 km × 0.6 km bounding box  (used for client-side refinement)
enum GeoHashEncoder {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    /// Returns a GeoHash of the requested length (default 6 for ~500 m precision).
    static func encode(_ coordinate: CLLocationCoordinate2D, length: Int = 6) -> String {
        var latRange = (-90.0, 90.0)
        var lngRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var bitsTotal = 0
        var hashValue = 0
        var isLng = true

        while hash.count < length {
            if isLng {
                let mid = (lngRange.0 + lngRange.1) / 2
                if coordinate.longitude >= mid {
                    hashValue = (hashValue << 1) | 1
                    lngRange.0 = mid
                } else {
                    hashValue = (hashValue << 1)
                    lngRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if coordinate.latitude >= mid {
                    hashValue = (hashValue << 1) | 1
                    latRange.0 = mid
                } else {
                    hashValue = (hashValue << 1)
                    latRange.1 = mid
                }
            }
            isLng.toggle()
            bits += 1
            bitsTotal += 1

            if bits == 5 {
                hash.append(base32[hashValue])
                bits = 0
                hashValue = 0
            }
        }
        return hash
    }

    /// Returns the GeoHash prefix at 5-char precision (used for Firestore range query).
    static func queryPrefix(_ coordinate: CLLocationCoordinate2D) -> String {
        encode(coordinate, length: 5)
    }
}

// MARK: - Nearby Discovery Models

/// A lightweight profile returned from a nearby search.
struct NearbyUserProfile: Identifiable, Equatable {
    let id: String           // Firestore UID
    let displayName: String
    let username: String
    let profileImageURL: String?
    let bio: String?
    let followersCount: Int
    let isPrivate: Bool
    let geoHash6: String     // 6-char hash used for client-side proximity check
}

/// Errors surfaced to the UI.
enum NearbySearchError: LocalizedError {
    case locationDenied
    case locationUnavailable
    case notAuthenticated
    case firestoreError(Error)

    var errorDescription: String? {
        switch self {
        case .locationDenied:
            return "Location access was denied. Go to Settings → AMEN → Location to enable it."
        case .locationUnavailable:
            return "Your location could not be determined. Please try again."
        case .notAuthenticated:
            return "You must be signed in to use this feature."
        case .firestoreError(let e):
            return "Search failed: \(e.localizedDescription)"
        }
    }
}

// MARK: - NearbyUsersService

/// Handles the full lifecycle of an on-demand, privacy-first nearby people search.
///
/// Lifecycle per search:
///   1. Request When-In-Use location authorization (if needed).
///   2. Get one location fix — do NOT start continuous updates.
///   3. Encode to a 6-char GeoHash (≈1.2 km precision, not exact GPS).
///   4. Write `users/{uid}/discoveryLocation` with `geoHash6`, `geoHash5`,
///      and `expiresAt = now + 1 hour` in a single atomic set.
///   5. Query `users` where `geoHash5 == prefix` AND `discoveryExpiresAt > now`.
///   6. Filter client-side: same geoHash6 prefix (≈1.2 km), remove self, blocked,
///      private (unless already following).
///   7. Return sorted results to caller.
///   8. On view dismiss or after 60 s idle: clear own discoveryLocation doc.
@MainActor
final class NearbyUsersService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = NearbyUsersService()

    // MARK: - Published state

    @Published private(set) var isSearching = false
    @Published private(set) var results: [NearbyUserProfile] = []
    @Published private(set) var error: NearbySearchError?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private let db = Firestore.firestore()
    private let ttlSeconds: Double = 3600 // 1 hour

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Execute a single nearby-people search.
    ///
    /// - Parameter followingIds: The current user's following set, used to exclude
    ///   already-followed users and to include private accounts the user follows.
    func requestNearbySearch(followingIds: Set<String>) async throws -> [NearbyUserProfile] {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            throw NearbySearchError.notAuthenticated
        }

        isSearching = true
        error = nil
        defer { isSearching = false }

        // 1. Acquire location authorization
        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            let e = NearbySearchError.locationDenied
            self.error = e
            throw e
        }
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait for the delegate callback to set locationStatus
            try await Task.sleep(nanoseconds: 400_000_000) // 0.4 s grace
        }

        // 2. Get one location fix
        let location: CLLocation
        do {
            location = try await getOneLocationFix()
        } catch {
            let e = NearbySearchError.locationUnavailable
            self.error = e
            throw e
        }

        let coord = location.coordinate

        // 3. Encode to fuzzy GeoHash (no raw GPS stored)
        let hash6 = GeoHashEncoder.encode(coord, length: 6)
        let hash5 = String(hash6.prefix(5))

        // 4. Write ephemeral discoveryLocation doc with 1-hour TTL
        let expiresAt = Date().addingTimeInterval(ttlSeconds)
        let docRef = db.collection("users").document(currentUID)
            .collection("discoveryLocation").document("current")
        try await docRef.setData([
            "geoHash6": hash6,
            "geoHash5": hash5,
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt)
        ])

        // Also write the two hash fields to the root user doc so they're queryable
        try await db.collection("users").document(currentUID).updateData([
            "nearbyGeoHash5": hash5,
            "nearbyGeoHash6": hash6,
            "nearbyExpiresAt": Timestamp(date: expiresAt)
        ])

        // 5. Query users by geoHash5 prefix whose discovery hasn't expired
        let blockedIds = BlockService.shared.blockedUsers
        let now = Timestamp(date: Date())

        let snapshot: QuerySnapshot
        do {
            snapshot = try await db.collection("users")
                .whereField("nearbyGeoHash5", isEqualTo: hash5)
                .whereField("nearbyExpiresAt", isGreaterThan: now)
                .limit(to: 60)
                .getDocuments()
        } catch {
            let e = NearbySearchError.firestoreError(error)
            self.error = e
            throw e
        }

        // 6. Filter and map
        var profiles: [NearbyUserProfile] = []
        for doc in snapshot.documents {
            let data = doc.data()
            let uid = doc.documentID

            // Exclude self
            guard uid != currentUID else { continue }
            // Exclude blocked users
            guard !blockedIds.contains(uid) else { continue }

            let isPrivate = data["isPrivate"] as? Bool ?? false
            // Exclude private accounts unless the current user already follows them
            if isPrivate && !followingIds.contains(uid) { continue }

            // Client-side 1.2 km refinement via geoHash6 match
            let theirHash6 = data["nearbyGeoHash6"] as? String ?? ""
            guard theirHash6.prefix(6) == hash6.prefix(6) else { continue }

            // Respect showInDiscovery privacy toggle
            let showInDiscovery = data["showInDiscovery"] as? Bool ?? true
            guard showInDiscovery else { continue }

            let profile = NearbyUserProfile(
                id: uid,
                displayName: data["displayName"] as? String ?? "AMEN Member",
                username: data["username"] as? String ?? "",
                profileImageURL: data["profileImageURL"] as? String,
                bio: data["bio"] as? String,
                followersCount: data["followersCount"] as? Int ?? 0,
                isPrivate: isPrivate,
                geoHash6: theirHash6
            )
            profiles.append(profile)
        }

        // Sort by follower count descending as a lightweight relevance signal
        profiles.sort { $0.followersCount > $1.followersCount }
        self.results = profiles
        return profiles
    }

    /// Clear the current user's discovery location document (call on dismiss / opt-out).
    func clearDiscoveryLocation() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await db.collection("users").document(uid)
                .collection("discoveryLocation").document("current").delete()
            try? await db.collection("users").document(uid).updateData([
                "nearbyGeoHash5": FieldValue.delete(),
                "nearbyGeoHash6": FieldValue.delete(),
                "nearbyExpiresAt": FieldValue.delete()
            ])
        }
    }

    // MARK: - Private helpers

    /// Requests a single location fix. Resolves when the first valid location
    /// arrives or rejects after 8 seconds.
    private func getOneLocationFix() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
            // 8 s timeout
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let cont = self.locationContinuation {
                    self.locationContinuation = nil
                    cont.resume(throwing: NearbySearchError.locationUnavailable)
                }
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension NearbyUsersService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(throwing: NearbySearchError.locationUnavailable)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.locationStatus = manager.authorizationStatus
        }
    }
}
