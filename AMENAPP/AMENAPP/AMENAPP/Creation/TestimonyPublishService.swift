// TestimonyPublishService.swift
// AMEN App — Testimony publish + C2PA provenance pipeline
//
// C2PA provenance manifest is non-negotiable:
//   publish() ALWAYS fails with an error if c2paManifestRef is empty.
//   There is no bypass, no fallback, no silent degradation.
//
// Flow:
//   1. prepareManifest(for:)  → calls generateC2PAManifest CF
//                             → returns manifestRef string
//   2. publish(_:)            → hard-fails if manifestRef is empty
//                             → writes to testimonies/{id}
//
// Flag-gated: AMENFeatureFlags.shared.testimonies

import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore

enum TestimonyPublishError: LocalizedError {
    case flagDisabled
    case missingManifestRef
    case unauthenticated
    case firestoreWriteFailed(String)
    case manifestGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .flagDisabled:
            return "Testimonies are not available right now."
        case .missingManifestRef:
            return "A provenance record is required before publishing. Tap 'Prepare to Publish' first."
        case .unauthenticated:
            return "You must be signed in to publish a testimony."
        case .firestoreWriteFailed(let msg):
            return "Publish failed: \(msg)"
        case .manifestGenerationFailed(let msg):
            return "Could not create provenance record: \(msg)"
        }
    }
}

@MainActor
final class TestimonyPublishService: ObservableObject {

    // MARK: - Dependencies

    private let functions = Functions.functions(region: "us-central1")
    private let db = Firestore.firestore()

    // MARK: - C2PA Manifest

    /// Calls the generateC2PAManifest Cloud Function.
    /// Returns the manifestRef string (e.g. "c2paManifests/testimonyId").
    /// Throws TestimonyPublishError.manifestGenerationFailed on any failure.
    func prepareManifest(for testimony: Testimony) async throws -> String {
        guard AMENFeatureFlags.shared.testimonies else {
            throw TestimonyPublishError.flagDisabled
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            throw TestimonyPublishError.unauthenticated
        }

        let data: [String: Any] = [
            "testimonyId": testimony.id,
            "authorUid": uid
        ]

        do {
            let result = try await functions.httpsCallable("generateC2PAManifest").call(data)
            guard
                let dict = result.data as? [String: Any],
                let ref = dict["manifestRef"] as? String,
                !ref.isEmpty
            else {
                throw TestimonyPublishError.manifestGenerationFailed("Unexpected response from manifest service.")
            }
            return ref
        } catch let error as TestimonyPublishError {
            throw error
        } catch {
            throw TestimonyPublishError.manifestGenerationFailed(error.localizedDescription)
        }
    }

    // MARK: - Publish

    /// Writes testimony to Firestore at testimonies/{id}.
    /// Hard-fails if c2paManifestRef is empty — no bypass.
    func publish(_ testimony: Testimony) async throws {
        guard AMENFeatureFlags.shared.testimonies else {
            throw TestimonyPublishError.flagDisabled
        }

        // Non-negotiable: manifest must exist
        guard !testimony.c2paManifestRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TestimonyPublishError.missingManifestRef
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            throw TestimonyPublishError.unauthenticated
        }

        var mutableTestimony = testimony
        // Ensure author is the authenticated user
        mutableTestimony = Testimony(
            id: testimony.id,
            authorUid: uid,
            before: testimony.before,
            encounter: testimony.encounter,
            after: testimony.after,
            c2paManifestRef: testimony.c2paManifestRef,
            visibility: testimony.visibility,
            createdAt: testimony.createdAt
        )

        let docData: [String: Any] = [
            "id": mutableTestimony.id,
            "authorUid": mutableTestimony.authorUid,
            "before": [
                "richText": mutableTestimony.before.richText,
                "mediaRef": mutableTestimony.before.mediaRef as Any
            ],
            "encounter": [
                "richText": mutableTestimony.encounter.richText,
                "mediaRef": mutableTestimony.encounter.mediaRef as Any
            ],
            "after": [
                "richText": mutableTestimony.after.richText,
                "mediaRef": mutableTestimony.after.mediaRef as Any
            ],
            "c2paManifestRef": mutableTestimony.c2paManifestRef,
            "visibility": mutableTestimony.visibility.rawValue,
            "createdAt": Timestamp(date: mutableTestimony.createdAt)
        ]

        do {
            try await db.collection("testimonies").document(mutableTestimony.id).setData(docData)
        } catch {
            throw TestimonyPublishError.firestoreWriteFailed(error.localizedDescription)
        }
    }

    // MARK: - Fetch

    /// Fetches the authenticated user's published testimonies as an async stream.
    func myTestimonies(uid: String) -> AsyncThrowingStream<[Testimony], Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("testimonies")
                .whereField("authorUid", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let docs = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }
                    let testimonies: [Testimony] = docs.compactMap { doc in
                        let d = doc.data()
                        guard
                            let id = d["id"] as? String,
                            let authorUid = d["authorUid"] as? String,
                            let beforeMap = d["before"] as? [String: Any],
                            let beforeText = beforeMap["richText"] as? String,
                            let encounterMap = d["encounter"] as? [String: Any],
                            let encounterText = encounterMap["richText"] as? String,
                            let afterMap = d["after"] as? [String: Any],
                            let afterText = afterMap["richText"] as? String,
                            let manifestRef = d["c2paManifestRef"] as? String,
                            let visibilityRaw = d["visibility"] as? String,
                            let visibility = TestimonyVisibility(rawValue: visibilityRaw),
                            let ts = d["createdAt"] as? Timestamp
                        else { return nil }

                        return Testimony(
                            id: id,
                            authorUid: authorUid,
                            before: TestimonySection(
                                richText: beforeText,
                                mediaRef: beforeMap["mediaRef"] as? String
                            ),
                            encounter: TestimonySection(
                                richText: encounterText,
                                mediaRef: encounterMap["mediaRef"] as? String
                            ),
                            after: TestimonySection(
                                richText: afterText,
                                mediaRef: afterMap["mediaRef"] as? String
                            ),
                            c2paManifestRef: manifestRef,
                            visibility: visibility,
                            createdAt: ts.dateValue()
                        )
                    }
                    continuation.yield(testimonies)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
}
