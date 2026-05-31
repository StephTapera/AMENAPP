// ProvenanceCredentialService.swift
// AMEN Trust Layer — T1 Provenance
// Manages read/write of MediaCredential records against Firestore and
// the registerMediaProvenance Cloud Function callable.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Errors

enum ProvenanceCredentialError: LocalizedError {
    case decodingFailed
    case notFound
    case unauthenticated
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed:   return "Failed to decode credential data."
        case .notFound:         return "No credential found for this media."
        case .unauthenticated:  return "You must be signed in to manage credentials."
        case .upstream(let m):  return m
        }
    }
}

// MARK: - Actor

actor ProvenanceCredentialService {

    // MARK: Singleton
    static let shared = ProvenanceCredentialService()
    private init() {}

    // MARK: Private helpers
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private func credentialDoc(mediaId: String) -> DocumentReference {
        db.collection("mediaCredentials").document(mediaId)
    }

    // MARK: - Register (calls Cloud Function)

    /// Registers a new MediaCredential by calling the `registerMediaProvenance`
    /// callable, then persists the full object to Firestore so it can be fetched
    /// client-side without a second round-trip through the function.
    func registerCredential(_ credential: MediaCredential) async throws {
        guard Auth.auth().currentUser != nil else {
            throw ProvenanceCredentialError.unauthenticated
        }

        let params: [String: Any] = [
            "mediaId":       credential.mediaId,
            "state":         credential.state.rawValue,
            "signerType":    credential.signerType.rawValue,
            "metadataIntact": credential.metadataIntact
        ]

        do {
            let result = try await functions
                .httpsCallable(TrustA11yCallable.registerMediaProvenance.rawValue)
                .call(params)

            guard result.data is [String: Any] else {
                throw ProvenanceCredentialError.upstream("Unexpected response from registerMediaProvenance.")
            }
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            throw ProvenanceCredentialError.upstream(error.localizedDescription)
        }

        // Persist locally so fetchCredential can work without hitting the function again.
        let encoder = Firestore.Encoder()
        let data = try encoder.encode(credential)
        try await credentialDoc(mediaId: credential.mediaId).setData(data, merge: true)
    }

    // MARK: - Fetch

    /// Reads a MediaCredential from Firestore. Returns nil when no document exists.
    func fetchCredential(mediaId: String) async throws -> MediaCredential? {
        let snapshot = try await credentialDoc(mediaId: mediaId).getDocument()
        guard snapshot.exists, let rawData = snapshot.data() else {
            return nil
        }

        do {
            let decoder = Firestore.Decoder()
            return try decoder.decode(MediaCredential.self, from: rawData)
        } catch {
            throw ProvenanceCredentialError.decodingFailed
        }
    }

    // MARK: - Append Edit Record

    /// Appends an EditRecord to the editChain array in Firestore (append-only).
    func appendEditRecord(_ record: EditRecord, to mediaId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw ProvenanceCredentialError.unauthenticated
        }

        let encoder = Firestore.Encoder()
        let recordData = try encoder.encode(record)

        try await credentialDoc(mediaId: mediaId).updateData([
            "editChain": FieldValue.arrayUnion([recordData])
        ])
    }

    // MARK: - Attach AI Contribution

    /// Appends an AIContribution to the aiContributions array in Firestore.
    func attachAIContribution(_ contribution: AIContribution, to mediaId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw ProvenanceCredentialError.unauthenticated
        }

        let encoder = Firestore.Encoder()
        let contributionData = try encoder.encode(contribution)

        try await credentialDoc(mediaId: mediaId).updateData([
            "aiContributions": FieldValue.arrayUnion([contributionData])
        ])
    }
}
