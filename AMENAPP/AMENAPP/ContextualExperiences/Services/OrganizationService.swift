// OrganizationService.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// Cloud Functions + Firestore service layer for AMEN Organizations.
// Organizations are the owning tenant for Contextual Experiences.
//
// Constraints:
//   - @MainActor throughout
//   - No Combine — async/await + @Published
//   - No force-unwrap
//   - NEVER log user PII in dlog calls

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - OrganizationServiceError

enum OrganizationServiceError: LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    case encodingFailed
    case invalidResponse
    case invalidArgument(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .notFound:
            return "The organization was not found."
        case .permissionDenied:
            return "You do not have permission to perform this action."
        case .encodingFailed:
            return "Failed to decode the organization data."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .invalidArgument(let msg):
            return msg
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - OrganizationService

@MainActor
final class OrganizationService: ObservableObject {

    static let shared = OrganizationService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Auth helper

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw OrganizationServiceError.notAuthenticated
            }
            return uid
        }
    }

    // MARK: - CF helper

    private func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let callable = functions.httpsCallable(name)
        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw OrganizationServiceError.invalidResponse
            }
            return data
        } catch let err as OrganizationServiceError {
            throw err
        } catch {
            throw OrganizationServiceError.underlying(error)
        }
    }

    // MARK: - Create Organization

    /// Creates a new organization via Cloud Function.
    /// Returns the new organizationId on success.
    func createOrganization(
        name: String,
        handle: String,
        type: OrganizationType,
        region: String,
        denomination: String?,
        description: String,
        isPublic: Bool
    ) async throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrganizationServiceError.invalidArgument("name cannot be empty.")
        }
        guard !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrganizationServiceError.invalidArgument("handle cannot be empty.")
        }

        var payload: [String: Any] = [
            "name": name,
            "handle": handle,
            "type": type.rawValue,
            "region": region,
            "description": description,
            "isPublic": isPublic
        ]
        if let denomination {
            payload["denomination"] = denomination
        }

        let response = try await call("createOrganization", payload)
        guard let orgId = response["organizationId"] as? String, !orgId.isEmpty else {
            throw OrganizationServiceError.invalidResponse
        }
        dlog("OrganizationService: created org \(orgId)")
        return orgId
    }

    // MARK: - Fetch Organization

    func getOrganization(id: String) async throws -> Organization {
        guard !id.isEmpty else {
            throw OrganizationServiceError.invalidArgument("id cannot be empty.")
        }
        let doc = try await db.collection("organizations").document(id).getDocument()
        guard doc.exists else {
            throw OrganizationServiceError.notFound
        }
        guard let org = try? doc.data(as: Organization.self) else {
            throw OrganizationServiceError.encodingFailed
        }
        return org
    }

    // MARK: - Search Organizations

    func searchOrganizations(query: String, type: OrganizationType?) async throws -> [Organization] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var payload: [String: Any] = ["query": query]
        if let type {
            payload["type"] = type.rawValue
        }
        let response = try await call("searchOrganizations", payload)
        guard let rawList = response["organizations"] as? [[String: Any]] else {
            return []
        }
        return rawList.compactMap { dict -> Organization? in
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(Organization.self, from: jsonData) else {
                return nil
            }
            return decoded
        }
    }

    // MARK: - Membership

    func joinOrganization(id: String) async throws {
        guard !id.isEmpty else {
            throw OrganizationServiceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("joinOrganization", ["organizationId": id])
        dlog("OrganizationService: joined org \(id)")
    }

    func leaveOrganization(id: String) async throws {
        guard !id.isEmpty else {
            throw OrganizationServiceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("leaveOrganization", ["organizationId": id])
        dlog("OrganizationService: left org \(id)")
    }

    // MARK: - Current User's Organizations

    /// Returns all organizations the current user is a member of.
    func getMyOrganizations() async throws -> [Organization] {
        let uid = try currentUID
        let memberSnap = try await db.collectionGroup("orgMembers")
            .whereField("userId", isEqualTo: uid)
            .getDocuments()

        var orgs: [Organization] = []
        for memberDoc in memberSnap.documents {
            // Path: organizations/{orgId}/orgMembers/{userId}
            guard let orgRef = memberDoc.reference.parent.parent else { continue }
            let orgDoc = try? await orgRef.getDocument()
            if let orgDoc, orgDoc.exists,
               let org = try? orgDoc.data(as: Organization.self) {
                orgs.append(org)
            }
        }
        return orgs
    }

    // MARK: - Get Membership Record

    func getMembership(orgId: String, userId: String) async throws -> OrgMembership? {
        guard !orgId.isEmpty, !userId.isEmpty else {
            throw OrganizationServiceError.invalidArgument("orgId and userId cannot be empty.")
        }
        let doc = try await db
            .collection("organizations")
            .document(orgId)
            .collection("orgMembers")
            .document(userId)
            .getDocument()

        guard doc.exists else { return nil }
        return try? doc.data(as: OrgMembership.self)
    }
}
