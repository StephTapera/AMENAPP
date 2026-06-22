// GuardianLinkService.swift
// AMENAPP — Child Safety / Guardian Link (finding #44)
//
// iOS client for the guardian email-verification pipeline.
//
// Flow:
//   1. Minor calls requestGuardianLink(guardianEmail:) → writes guardianLinkRequests/{id}
//      (the onGuardianLinkCreated CF sends a verification email to the guardian).
//   2. Guardian (signed in) calls verifyGuardianLink(requestId:otp:) → verifyGuardianLink CF
//      validates the OTP and writes guardianApprovedContacts/{minorId}/contacts/{guardianUid}.
//
// Gate: AMENFeatureFlags.shared.guardianLinkEnabled (default OFF until A-03 policy).
// Backend: functions/guardianLink.js (onGuardianLinkCreated + verifyGuardianLink callable).

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class GuardianLinkService: ObservableObject {

    static let shared = GuardianLinkService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Errors

    enum GuardianLinkError: LocalizedError {
        case featureDisabled
        case notAuthenticated
        case invalidEmail
        case invalidCode
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .featureDisabled:      return "Guardian linking is not available yet."
            case .notAuthenticated:     return "You must be signed in to link a guardian."
            case .invalidEmail:         return "Please enter a valid guardian email address."
            case .invalidCode:          return "The verification code must be 6 digits."
            case .requestFailed(let m): return m
            }
        }
    }

    // MARK: - Request a guardian link (minor-initiated)

    /// Writes a pending guardian link request. The onGuardianLinkCreated CF sends the
    /// verification email. Returns the new request document ID.
    func requestGuardianLink(guardianEmail: String) async throws -> String {
        guard AMENFeatureFlags.shared.guardianLinkEnabled else {
            throw GuardianLinkError.featureDisabled
        }
        guard let minorId = Auth.auth().currentUser?.uid else {
            throw GuardianLinkError.notAuthenticated
        }
        let trimmed = guardianEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else {
            throw GuardianLinkError.invalidEmail
        }

        let requestData: [String: Any] = [
            "minorId": minorId,
            "guardianEmail": trimmed,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            let ref = try await db.collection("guardianLinkRequests").addDocument(data: requestData)
            return ref.documentID
        } catch {
            throw GuardianLinkError.requestFailed("Couldn't submit the guardian request. Please try again.")
        }
    }

    // MARK: - Verify (guardian-initiated)

    /// Guardian submits the 6-digit OTP from their email. Calls the verifyGuardianLink CF
    /// which writes the approved-contact document on success.
    func verifyGuardianLink(requestId: String, otp: String) async throws {
        guard AMENFeatureFlags.shared.guardianLinkEnabled else {
            throw GuardianLinkError.featureDisabled
        }
        guard Auth.auth().currentUser?.uid != nil else {
            throw GuardianLinkError.notAuthenticated
        }
        let trimmedOTP = otp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOTP.count == 6, trimmedOTP.allSatisfy(\.isNumber) else {
            throw GuardianLinkError.invalidCode
        }

        do {
            _ = try await functions
                .httpsCallable("verifyGuardianLink")
                .call(["requestId": requestId, "otp": trimmedOTP])
        } catch {
            // Surface the CF's user-facing message when available.
            let nsError = error as NSError
            let message = nsError.localizedDescription.isEmpty
                ? "Verification failed. Please check the code and try again."
                : nsError.localizedDescription
            throw GuardianLinkError.requestFailed(message)
        }
    }

    // MARK: - Status

    /// Observes the status of a guardian link request for the minor's own request.
    /// Returns the latest status string or nil if the request is gone.
    func fetchRequestStatus(requestId: String) async throws -> String? {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GuardianLinkError.notAuthenticated
        }
        let doc = try await db.collection("guardianLinkRequests").document(requestId).getDocument()
        guard doc.exists else { return nil }
        return doc.data()?["status"] as? String
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
