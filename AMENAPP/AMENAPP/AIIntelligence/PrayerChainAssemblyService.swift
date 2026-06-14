// PrayerChainAssemblyService.swift
// AMEN — Prayer Chain Assembly Service
//
// Assembles ChainLinks into a woven artifact via Cloud Function.
// Delivers the chain to the requester and triggers a SelahMoment.
// Flag-gated: AMENFeatureFlags.shared.prayerChains

import Foundation
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class PrayerChainAssemblyService: ObservableObject {

    // MARK: - Dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-east1")

    // MARK: - Create Chain

    /// Creates a new PrayerChain document with the given first link.
    func createChain(requestRef: String, firstLink: ChainLink) async throws {
        guard AMENFeatureFlags.shared.prayerChains else {
            throw PrayerChainAssemblyError.featureDisabled
        }

        let chainId = UUID().uuidString
        let linkData = try encodeLinkData(firstLink)
        let data: [String: Any] = [
            "id": chainId,
            "requestRef": requestRef,
            "links": [linkData],
            "createdAt": Timestamp(date: Date())
        ]
        try await db.collection("prayerChains").document(chainId).setData(data)
    }

    /// Appends a ChainLink to an existing chain.
    func appendLink(_ link: ChainLink, toChainId chainId: String) async throws {
        guard AMENFeatureFlags.shared.prayerChains else {
            throw PrayerChainAssemblyError.featureDisabled
        }

        let linkData = try encodeLinkData(link)
        try await db.collection("prayerChains").document(chainId).updateData([
            "links": FieldValue.arrayUnion([linkData])
        ])
    }

    // MARK: - Assemble

    /// Reads chain links from Firestore, calls the assemblePrayerChain Cloud Function
    /// to create a wovenArtifact document, then updates the chain with the artifact ref.
    func assembleChain(chainId: String) async throws {
        guard AMENFeatureFlags.shared.prayerChains else {
            throw PrayerChainAssemblyError.featureDisabled
        }

        let callable = functions.httpsCallable("assemblePrayerChain")
        _ = try await callable.call(["chainId": chainId])
        // The Cloud Function writes wovenArtifactRef back onto the chain document.
    }

    // MARK: - Deliver

    /// Marks the chain as delivered at the current timestamp and triggers a SelahMoment
    /// for the requester.
    func deliverChain(chainId: String, requestUid: String) async throws {
        guard AMENFeatureFlags.shared.prayerChains else {
            throw PrayerChainAssemblyError.featureDisabled
        }

        try await db.collection("prayerChains").document(chainId).updateData([
            "deliveredAt": Timestamp(date: Date()),
            "deliveredToUid": requestUid
        ])

        // SelahMoment for the requester — this is a high-grace moment.
        SelahMomentService().trigger()
    }

    // MARK: - Helpers

    private func encodeLinkData(_ link: ChainLink) throws -> [String: Any] {
        let encoder = Firestore.Encoder()
        return try encoder.encode(link)
    }
}

// MARK: - Error

enum PrayerChainAssemblyError: Error, LocalizedError {
    case featureDisabled

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Prayer Chains is not available right now."
        }
    }
}
