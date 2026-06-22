//  ConnectGuardianService.swift
//  AMEN Connect V1 — client for the Verified Guardian Link primitive (spec §5.1).
//
//  Calls the us-east1 callables in Backend/functions/src/connect/guardianLink.ts:
//    • requestGuardianLink  → creates a PENDING church-scoped guardian link
//    • getChildCheckInStatus → guardian-only child status (server returns 403 otherwise)
//
//  DISTINCT from AmenChildSafetyService.requestGuardianLink(minorId:guardianEmail:), which is the
//  email-based COPPA minor-DM guardian (collection `guardianLinkRequests`). This one is the
//  CHURCH check-in guardian (collection `guardianLinks/{guardianUid}_{childId}`). They coexist.
//
//  The client NEVER trusts itself for child data — every gate is re-asserted server-side. This
//  service only surfaces what the verified callable returns; it caches nothing sensitive.

import Foundation
import FirebaseFunctions

@MainActor
final class ConnectGuardianService: ObservableObject {

    static let shared = ConnectGuardianService()

    // Connect functions live in us-east1 (us-central1 is at quota; see CLAUDE.md).
    private let functions = Functions.functions(region: "us-east1")

    private init() {}

    /// Requests a (pending) church-scoped guardian link. Verification is a separate server path;
    /// this always resolves to `.pending` on success.
    func requestGuardianLink(
        churchId: String,
        childId: String,
        evidence: GuardianEvidence
    ) async throws -> RequestGuardianLinkResponse {
        var evidencePayload: [String: Any] = ["kind": evidence.kind]
        if let reference = evidence.reference { evidencePayload["reference"] = reference }

        let payload: [String: Any] = [
            "churchId": churchId,
            "childId": childId,
            "evidence": evidencePayload
        ]
        let result = try await functions.httpsCallable("requestGuardianLink").call(payload)
        return try Self.decode(result.data, as: RequestGuardianLinkResponse.self)
    }

    /// Reads a child's check-in status. Throws if the caller is not a verified guardian
    /// (the callable returns `permission-denied`, surfaced here as an error).
    func childCheckInStatus(childId: String) async throws -> ChildStatus {
        let payload: [String: Any] = ["childId": childId]
        let result = try await functions.httpsCallable("getChildCheckInStatus").call(payload)
        return try Self.decode(result.data, as: ChildStatus.self)
    }

    // Bridges a callable's loosely-typed result into our Codable contract mirror.
    private static func decode<T: Decodable>(_ raw: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: raw, options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }
}
