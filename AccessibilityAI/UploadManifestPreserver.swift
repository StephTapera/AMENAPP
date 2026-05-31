// UploadManifestPreserver.swift
// AMEN Trust Layer — T1 Provenance
// Static helpers that stamp and extract provenance metadata on Firebase Storage
// uploads so that C2PA-aligned manifest data travels with the media object.

import Foundation
import FirebaseStorage

// MARK: - Manifest Preserver

struct UploadManifestPreserver {

    private static let metadataKey = "amen_provenance"

    // MARK: - Stamp

    /// Serialises a MediaCredential as JSON and writes it into the Storage
    /// object's custom metadata under the `amen_provenance` key.
    /// Call this before initiating a `putData` or `putFile` upload task.
    static func stamp(metadata: inout StorageMetadata, credential: MediaCredential) {
        guard let encoded = try? JSONEncoder().encode(credential),
              let json = String(data: encoded, encoding: .utf8) else {
            return
        }

        var custom = metadata.customMetadata ?? [:]
        custom[metadataKey] = json
        metadata.customMetadata = custom
    }

    // MARK: - Extract

    /// Reads the `amen_provenance` key from a StorageMetadata object returned
    /// after an upload completes or when fetching object metadata.
    /// Returns nil when no provenance data is present or decoding fails.
    static func extractCredentialStub(from metadata: StorageMetadata) -> MediaCredential? {
        guard let json = metadata.customMetadata?[metadataKey],
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(MediaCredential.self, from: data)
    }

    // MARK: - Verify Manifest Integrity

    /// Returns true only when all three integrity signals are positive:
    /// - A C2PA manifest is present in the credential
    /// - The metadata has not been tampered with
    /// - The state is something other than `.unverified`
    static func verifyManifestIntact(_ credential: MediaCredential) -> Bool {
        credential.c2paManifestPresent
            && credential.metadataIntact
            && credential.state != .unverified
    }
}
