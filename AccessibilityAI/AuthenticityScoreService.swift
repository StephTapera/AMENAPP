// AuthenticityScoreService.swift
// AMEN Trust Layer — T2 Authenticity Scoring
// Computes AuthenticityScore via the trustVerifyProxy callable.
// Falls back to local signal derivation when offline or the callable fails.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Errors

enum AuthenticityScoreError: LocalizedError {
    case unauthenticated
    case malformedResponse
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:    return "Sign in required to verify content authenticity."
        case .malformedResponse:  return "Authenticity response could not be parsed."
        case .upstream(let msg):  return msg
        }
    }
}

// MARK: - Actor

actor AuthenticityScoreService {

    // MARK: Singleton
    static let shared = AuthenticityScoreService()
    private init() {}

    private let functions = Functions.functions()

    // MARK: - Compute Score (Network)

    /// Calls `trustVerifyProxy` to compute an AuthenticityScore for the given
    /// mediaId. Gracefully falls back to a zeroed score on any network or
    /// callable failure — never throws to the caller from the fallback path.
    func computeScore(for mediaId: String) async throws -> AuthenticityScore {
        guard Auth.auth().currentUser != nil else {
            throw AuthenticityScoreError.unauthenticated
        }

        let params: [String: Any] = ["mediaId": mediaId]

        do {
            let result = try await functions
                .httpsCallable(TrustA11yCallable.trustVerifyProxy.rawValue)
                .call(params)

            guard let data = result.data as? [String: Any] else {
                throw AuthenticityScoreError.malformedResponse
            }

            return try parseScore(from: data)

        } catch let error as AuthenticityScoreError {
            // Re-throw our typed errors.
            throw error
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            // Cloud Function error — return offline fallback score instead of
            // crashing the caller; the UI can indicate "unverified" gracefully.
            return offlineFallback()
        } catch {
            // Any other network/parsing error also produces the offline fallback.
            return offlineFallback()
        }
    }

    // MARK: - Local Fallback (no network)

    /// Derives an AuthenticityScore purely from the credential's stored signals.
    /// Never touches the network.
    func localFallback(for credential: MediaCredential) -> AuthenticityScore {
        let originalCapture  = credential.state == .verifiedOriginal
        let provenanceIntact = credential.c2paManifestPresent && credential.metadataIntact
        let editsDisclosed   = !credential.editChain.isEmpty || credential.state != .edited

        return AuthenticityScore(
            originalCapture:  originalCapture,
            provenanceIntact: provenanceIntact,
            sourceVerified:   credential.sourceVerified,
            metadataIntact:   credential.metadataIntact,
            editsDisclosed:   editsDisclosed
        )
    }

    // MARK: - Private helpers

    private func parseScore(from data: [String: Any]) throws -> AuthenticityScore {
        // The proxy returns boolean signals matching our model.
        guard
            let originalCapture  = data["originalCapture"]  as? Bool,
            let provenanceIntact = data["provenanceIntact"]  as? Bool,
            let sourceVerified   = data["sourceVerified"]    as? Bool,
            let metadataIntact   = data["metadataIntact"]    as? Bool,
            let editsDisclosed   = data["editsDisclosed"]    as? Bool
        else {
            throw AuthenticityScoreError.malformedResponse
        }

        return AuthenticityScore(
            originalCapture:  originalCapture,
            provenanceIntact: provenanceIntact,
            sourceVerified:   sourceVerified,
            metadataIntact:   metadataIntact,
            editsDisclosed:   editsDisclosed
        )
    }

    /// Zero-score fallback used when the network call cannot complete.
    private func offlineFallback() -> AuthenticityScore {
        AuthenticityScore(
            originalCapture:  false,
            provenanceIntact: false,
            sourceVerified:   false,
            metadataIntact:   false,
            editsDisclosed:   false
        )
    }
}
