// EdgeService.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: manages the /edges collection for many-to-many
// object relationships.
//
// Source contracts: C1 §4 "Edges Collection — Many-to-Many Relationships".
// Cloud Functions `createEdge` and `getEdges` are stubs — they call Firebase
// Callable Functions that are deployed separately.

import Foundation
import FirebaseFunctions

// MARK: - AmenCallableEdge

/// A directed relationship between two canonical objects.
/// Stored in Firestore `/edges/{edgeId}`.
/// Source: C1 §4a "Firestore shape".
struct AmenCallableEdge: Codable, Identifiable, Sendable {
    var id: String { "\(fromRef)|\(toRef)|\(edgeType.rawValue)" }

    /// Firestore path of the originating object (e.g. `/posts/abc`).
    let fromRef: String
    /// Raw object type string of the origin object.
    let fromType: String
    /// Firestore path of the destination object (e.g. `/organizations/xyz`).
    let toRef: String
    /// Raw object type string of the destination object.
    let toType: String
    /// The semantic relationship type.
    let edgeType: AmenCallableEdgeType
    /// UID of the user who created this edge.
    let createdBy: String
    /// Visibility level: `"public"`, `"members"`, or `"private"`.
    let visibility: String
    /// Server-set creation timestamp.
    let createdAt: Date
}

// MARK: - EdgeDirection

extension EdgeService {
    enum EdgeDirection: String, Sendable {
        case outbound = "outbound"
        case inbound  = "inbound"
        case both     = "both"
    }
}

// MARK: - EdgeService

/// @MainActor service for creating and querying the `/edges` collection.
/// All mutations and reads are routed through Firebase Callable Functions
/// (`createEdge`, `getEdges`) to enforce Firestore security rules and
/// server-side fan-out limits (C1 §4e: max 50 edge writes per mutation).
@MainActor
final class EdgeService {

    // MARK: - Singleton

    static let shared = EdgeService()

    // MARK: - Private

    private let functions: Functions

    private init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Create Edge

    /// Creates a directed edge between two objects.
    ///
    /// - Parameters:
    ///   - fromRef: Firestore path of the source object.
    ///   - fromType: Raw `AmenObjectType` string of the source.
    ///   - toRef: Firestore path of the destination object.
    ///   - toType: Raw `AmenObjectType` string of the destination.
    ///   - edgeType: The semantic relationship type.
    ///   - visibility: One of `"public"`, `"members"`, or `"private"`.
    /// - Returns: The created `AmenCallableEdge`.
    /// - Throws: Errors forwarded from the `createEdge` Cloud Function.
    @discardableResult
    func createEdge(
        fromRef: String,
        fromType: String,
        toRef: String,
        toType: String,
        edgeType: AmenCallableEdgeType,
        visibility: String
    ) async throws -> AmenCallableEdge {

        guard AMENFeatureFlags.shared.communityOSEnabled else {
            throw EdgeServiceError.featureFlagDisabled
        }

        let payload: [String: Any] = [
            "fromRef":    fromRef,
            "fromType":   fromType,
            "toRef":      toRef,
            "toType":     toType,
            "edgeType":   edgeType.rawValue,
            "visibility": visibility
        ]

        let callable = functions.httpsCallable("createEdge")
        let result = try await callable.call(payload)

        guard let data = result.data as? [String: Any] else {
            throw EdgeServiceError.invalidResponse
        }

        return try AmenCallableEdge(from: data)
    }

    // MARK: - Get Edges

    /// Fetches edges associated with an object reference.
    ///
    /// - Parameters:
    ///   - ref: The Firestore document path of the object.
    ///   - direction: Whether to fetch outbound, inbound, or both directions.
    ///   - edgeType: Optional filter by edge type. `nil` returns all types.
    /// - Returns: An array of `AmenCallableEdge` records.
    /// - Throws: Errors forwarded from the `getEdges` Cloud Function.
    func getEdges(
        ref: String,
        direction: EdgeDirection,
        edgeType: AmenCallableEdgeType? = nil
    ) async throws -> [AmenCallableEdge] {

        guard AMENFeatureFlags.shared.communityOSEnabled else {
            throw EdgeServiceError.featureFlagDisabled
        }

        var payload: [String: Any] = [
            "ref":       ref,
            "direction": direction.rawValue
        ]
        if let type = edgeType {
            payload["edgeType"] = type.rawValue
        }

        let callable = functions.httpsCallable("getEdges")
        let result = try await callable.call(payload)

        guard let dataArray = result.data as? [[String: Any]] else {
            return []
        }

        return dataArray.compactMap { try? AmenCallableEdge(from: $0) }
    }
}

// MARK: - EdgeServiceError

enum EdgeServiceError: Error, Sendable {
    case featureFlagDisabled
    case invalidResponse
    case missingField(String)
}

// MARK: - AmenCallableEdge + Decoding helper

private extension AmenCallableEdge {
    init(from data: [String: Any]) throws {
        guard
            let fromRef   = data["fromRef"]   as? String,
            let fromType  = data["fromType"]  as? String,
            let toRef     = data["toRef"]     as? String,
            let toType    = data["toType"]    as? String,
            let edgeRaw   = data["edgeType"]  as? String,
            let edgeType  = AmenCallableEdgeType(rawValue: edgeRaw),
            let createdBy = data["createdBy"] as? String,
            let visibility = data["visibility"] as? String
        else {
            throw EdgeServiceError.missingField("core_fields")
        }

        let createdAt: Date
        if let epoch = data["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: epoch)
        } else {
            createdAt = Date()
        }

        self.init(
            fromRef: fromRef,
            fromType: fromType,
            toRef: toRef,
            toType: toType,
            edgeType: edgeType,
            createdBy: createdBy,
            visibility: visibility,
            createdAt: createdAt
        )
    }
}
