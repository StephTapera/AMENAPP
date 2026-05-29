// AmenOrgClaimService.swift
// AMEN App — Organization Claim Service
//
// Handles search (Algolia `organizations` index + Google Places fallback)
// and submits claim requests to the `requestOrgClaim` Cloud Function.
//
// Google Places privacy constraint: `placeId` is the ONLY field that ever
// reaches Firestore. `displayName` and `displayAddress` live in
// `PlaceSearchResult` (a display-only struct) and are NEVER persisted.

import Foundation
import FirebaseFunctions
import FirebaseAuth
import AlgoliaSearch

// MARK: - Supporting types

enum ClaimVerificationMethod {
    /// Caller provided a work email whose domain matches the org's website domain.
    case domainMatch(String)
    /// No domain match; submission enters the manual review queue.
    case manualReview
}

/// Display-only result from a Google Places keyword search.
/// PRIVACY: only `placeId` is stored anywhere. The other fields are
/// display-only and must not be written to Firestore.
struct PlaceSearchResult: Identifiable {
    let id: UUID = UUID()
    let placeId: String         // stored field (Google Places TOS: placeId only)
    let displayName: String     // display only — never persisted
    let displayAddress: String  // display only — never persisted
}

// MARK: - AmenOrgClaimService

@MainActor
final class AmenOrgClaimService: ObservableObject {

    static let shared = AmenOrgClaimService()

    // MARK: Published state

    @Published var searchResults: [AmenOrganizationProfile] = []
    @Published var isSearching: Bool = false
    @Published var claimState: ClaimSubmissionState = .idle

    enum ClaimSubmissionState: Equatable {
        case idle
        case submitting
        case submitted(autoVerified: Bool, claimId: String)
        case error(String)

        static func == (lhs: ClaimSubmissionState, rhs: ClaimSubmissionState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.submitting, .submitting): return true
            case (.submitted(let a1, let b1), .submitted(let a2, let b2)):
                return a1 == a2 && b1 == b2
            case (.error(let m1), .error(let m2)): return m1 == m2
            default: return false
            }
        }
    }

    // MARK: Private

    private let functions = Functions.functions()
    private var searchClient: SearchClient? = nil
    private let orgIndexName = "organizations"

    private init() {
        let appID = AlgoliaConfig.applicationID
        let searchKey = AlgoliaConfig.searchAPIKey
        guard !appID.isEmpty, !searchKey.isEmpty else {
            dlog("AmenOrgClaimService: Algolia keys not configured — search will be unavailable.")
            return
        }
        do {
            searchClient = try SearchClient(appID: appID, apiKey: searchKey)
        } catch {
            dlog("AmenOrgClaimService: Algolia init failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Algolia Search

    /// Searches the Algolia `organizations` index.
    /// Optionally filters by `AmenOrganizationType`.
    func search(query: String, type: AmenOrganizationType? = nil) async {
        guard let client = searchClient else {
            dlog("AmenOrgClaimService.search: Algolia not configured.")
            return
        }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            var searchForHits = SearchForHits(
                query: query,
                hitsPerPage: 20,
                indexName: orgIndexName,
                type: .default
            )
            if let type {
                searchForHits.filters = "type:\(type.rawValue)"
            }

            let responses: [SearchResponse<Hit>] = try await client.searchForHitsWithResponse(
                searchMethodParams: SearchMethodParams(requests: [.searchForHits(searchForHits)])
            )

            guard let first = responses.first else {
                searchResults = []
                return
            }

            // Decode each hit's additionalProperties → AmenOrganizationProfile
            let decoded: [AmenOrganizationProfile] = first.hits.compactMap { hit in
                guard let props = hit.additionalProperties,
                      let data = try? JSONSerialization.data(withJSONObject: props),
                      let profile = try? JSONDecoder().decode(AmenOrganizationProfile.self, from: data)
                else { return nil }
                return profile
            }
            searchResults = decoded
        } catch {
            dlog("AmenOrgClaimService.search error: \(error.localizedDescription)")
            searchResults = []
        }
    }

    // MARK: - Google Places Fallback

    /// Keyword-search Google Places and return display-only results.
    /// Only the `placeId` is retained; all other place fields are display-only.
    /// The caller must pass the `placeId` to `createOrgStub` if the user
    /// selects a Places result — the stub CF persists only the ID.
    func searchPlaces(query: String) async -> [PlaceSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        do {
            let result = try await functions.httpsCallable("searchPlacesByKeyword")
                .call(["query": query])

            guard let data = result.data as? [[String: Any]] else { return [] }

            return data.compactMap { item -> PlaceSearchResult? in
                guard let placeId      = item["placeId"]      as? String,
                      let displayName  = item["displayName"]  as? String,
                      let displayAddress = item["displayAddress"] as? String
                else { return nil }

                // placeId only — no other Places data enters Firestore from the client
                return PlaceSearchResult(
                    placeId: placeId,
                    displayName: displayName,
                    displayAddress: displayAddress
                )
            }
        } catch {
            dlog("AmenOrgClaimService.searchPlaces error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Submit Claim

    /// Calls `requestOrgClaim` Cloud Function.
    /// Throws on network error, rate limit, or server rejection.
    func requestClaim(
        orgId: String,
        verificationMethod: ClaimVerificationMethod
    ) async throws {
        claimState = .submitting

        var payload: [String: Any] = ["orgId": orgId]
        switch verificationMethod {
        case .domainMatch(let email):
            payload["verificationEmail"] = email
            payload["verificationMethod"] = "domain_match"
        case .manualReview:
            payload["verificationMethod"] = "manual_review"
            payload["verificationEmail"] = ""
        }

        do {
            let result = try await functions.httpsCallable("requestOrgClaim").call(payload)
            guard let data = result.data as? [String: Any],
                  let claimId = data["claimId"] as? String else {
                throw AmenOrgClaimError.invalidResponse
            }
            let autoVerified = data["autoVerified"] as? Bool ?? false
            claimState = .submitted(autoVerified: autoVerified, claimId: claimId)
        } catch let error as AmenOrgClaimError {
            claimState = .error(error.localizedDescription)
            throw error
        } catch {
            let msg = (error as NSError).localizedDescription
            claimState = .error(msg)
            throw error
        }
    }

    // MARK: - Create Stub

    /// Calls `createOrgStub` for the "Add a new listing" path.
    /// `placeId` is the ONLY Google Places-derived field written to Firestore.
    func createOrgStub(
        placeId: String?,
        name: String,
        type: AmenOrganizationType,
        city: String,
        state: String
    ) async throws -> String {
        var payload: [String: Any] = [
            "name":  name,
            "type":  type.rawValue,
            "city":  city,
            "state": state
        ]
        if let placeId { payload["placeId"] = placeId }

        let result = try await functions.httpsCallable("createOrgStub").call(payload)
        guard let data = result.data as? [String: Any],
              let orgId = data["orgId"] as? String else {
            throw AmenOrgClaimError.invalidResponse
        }
        return orgId
    }

    // MARK: - Reset

    func resetClaimState() {
        claimState = .idle
    }
}

// MARK: - Errors

enum AmenOrgClaimError: LocalizedError {
    case invalidResponse
    case alreadyClaimed
    case rateLimitExceeded
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:   return "The server returned an unexpected response. Please try again."
        case .alreadyClaimed:    return "This organization has already been claimed."
        case .rateLimitExceeded: return "You've submitted too many claims recently. Please wait and try again."
        case .notAuthenticated:  return "You must be signed in to claim an organization."
        }
    }
}
