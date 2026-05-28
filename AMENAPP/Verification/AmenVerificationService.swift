// AmenVerificationService.swift
// AMENAPP — Verification & Trust System
//
// Manages real-time Firestore listeners for a user's verification state and
// wraps all Firebase Callable invocations behind user-safe error types.

import SwiftUI
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenVerificationError

enum AmenVerificationError: LocalizedError, Sendable {
    case notAuthenticated
    case rateLimited
    case ineligible(String)
    case networkError
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use verification features."
        case .rateLimited:
            return "You've made too many requests. Please wait a moment and try again."
        case .ineligible(let reason):
            return reason.isEmpty
                ? "Your account is not currently eligible for this verification."
                : reason
        case .networkError:
            return "A network error occurred. Please check your connection and try again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - AmenVerificationService

@MainActor
final class AmenVerificationService: ObservableObject {

    static let shared = AmenVerificationService()

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    private var listeners: [ListenerRegistration] = []
    private var listeningUid: String?

    @Published private(set) var summary: AmenPublicVerificationSummary = .empty
    @Published private(set) var requests: [AmenVerificationRequest] = []
    @Published private(set) var roles: [AmenRoleVerification] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private init() {}

    // MARK: - Listeners

    func startListening(uid: String) {
        guard uid != listeningUid else { return }
        stopListening()
        listeningUid = uid
        attachSummaryListener(uid: uid)
        attachRequestsListener(uid: uid)
        attachRolesListener(uid: uid)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        listeningUid = nil
    }

    // MARK: - Private Listener Attachments

    private func attachSummaryListener(uid: String) {
        let ref = db.collection("users").document(uid)
        let registration = ref.addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor [weak self] in
                guard let self, let data = snapshot?.data() else { return }
                guard let nested = data["publicVerificationSummary"] as? [String: Any] else { return }
                do {
                    let decoded = try Firestore.Decoder().decode(
                        AmenPublicVerificationSummary.self, from: nested
                    )
                    self.summary = decoded
                } catch {
                    // Silently skip malformed data — do not crash on partial Firestore documents
                }
            }
        }
        listeners.append(registration)
    }

    private func attachRequestsListener(uid: String) {
        let ref = db.collection("users").document(uid).collection("verificationRequests")
        let registration = ref.addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor [weak self] in
                guard let self, let docs = snapshot?.documents else { return }
                self.requests = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return try? Firestore.Decoder().decode(AmenVerificationRequest.self, from: data)
                }
            }
        }
        listeners.append(registration)
    }

    private func attachRolesListener(uid: String) {
        // Query across all organization role subcollections for this uid.
        // The canonical Firestore path is: organizations/{orgId}/roles/{uid}
        // We use a collection group query so we don't need to know orgIds up front.
        let ref = db.collectionGroup("roles").whereField("uid", isEqualTo: uid)
        let registration = ref.addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor [weak self] in
                guard let self, let docs = snapshot?.documents else { return }
                self.roles = docs.compactMap { doc in
                    var data = doc.data()
                    data["id"] = doc.documentID
                    return try? Firestore.Decoder().decode(AmenRoleVerification.self, from: data)
                }
            }
        }
        listeners.append(registration)
    }

    // MARK: - Identity Verification

    func startIdentityVerification() async throws -> AmenIdentitySessionResponse {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("startIdentityVerification").call()
            guard let data = result.data as? [String: Any] else {
                throw AmenVerificationError.unknown
            }
            let json = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(AmenIdentitySessionResponse.self, from: json)
        } catch let err as AmenVerificationError {
            throw err
        } catch {
            throw mapFunctionsError(error)
        }
    }

    // MARK: - Organization Verification

    func requestOrganizationVerification(orgId: String, domainEmail: String) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await functions.httpsCallable("requestOrganizationVerification").call([
                "orgId": orgId,
                "domainEmail": domainEmail
            ])
        } catch {
            throw mapFunctionsError(error)
        }
    }

    // MARK: - Role Verification

    func requestRoleVerification(orgId: String, role: String, scope: String) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await functions.httpsCallable("requestRoleVerification").call([
                "orgId": orgId,
                "role": role,
                "scope": scope
            ])
        } catch {
            throw mapFunctionsError(error)
        }
    }

    // MARK: - Creator Verification

    func requestCreatorVerification() async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await functions.httpsCallable("requestCreatorVerification").call()
        } catch {
            throw mapFunctionsError(error)
        }
    }

    // MARK: - Impersonation Report

    func reportImpersonation(targetUid: String, reason: String) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await functions.httpsCallable("reportImpersonation").call([
                "targetUid": targetUid,
                "reason": reason
            ])
        } catch {
            throw mapFunctionsError(error)
        }
    }

    // MARK: - Error Mapping

    private func mapFunctionsError(_ error: Error) -> AmenVerificationError {
        // FunctionsError conforms to CustomNSError; catch as NSError to access error code.
        let nsErr = error as NSError
        if nsErr.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: nsErr.code)
            switch code {
            case .unauthenticated:
                return .notAuthenticated
            case .resourceExhausted:
                return .rateLimited
            case .failedPrecondition, .permissionDenied:
                // Server may provide a user-safe message via NSLocalizedDescriptionKey.
                let detail = nsErr.userInfo[NSLocalizedDescriptionKey] as? String ?? ""
                return .ineligible(detail)
            case .unavailable, .deadlineExceeded:
                return .networkError
            default:
                return .unknown
            }
        }
        if nsErr.domain == NSURLErrorDomain { return .networkError }
        return .unknown
    }
}
