//
//  AmenMediaProvenanceService.swift
//  AMENAPP
//
//  Implements Amen True Source on the client side.
//  Registers provenance for every media upload.
//  Reads provenance for display in feed and post detail.
//

import Foundation
import SwiftUI
import FirebaseFunctions
import CryptoKit

@MainActor
final class AmenMediaProvenanceService: ObservableObject {

    static let shared = AmenMediaProvenanceService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    private init() {}

    // MARK: - Register provenance after upload

    func registerProvenance(
        mediaId: String,
        storageUri: String,
        mimeType: String,
        fileSizeBytes: Int,
        fileData: Data?,
        declaration: TSCreatorDeclaration,
        sourceChain: [String] = []
    ) async -> TSMediaProvenance? {
        guard flags.mediaProvenanceEnabled else { return nil }

        let hash = fileData.map { computeSHA256($0) } ?? "unknown"

        let params: [String: Any] = [
            "mediaId": mediaId,
            "storageUri": storageUri,
            "mimeType": mimeType,
            "fileSizeBytes": fileSizeBytes,
            "originalHash": hash,
            "creatorDeclaration": declaration.rawValue,
            "sourceChain": sourceChain,
        ]

        do {
            let result = try await functions.httpsCallable("registerMediaProvenance").call(params)
            guard let data = result.data as? [String: Any] else { return nil }
            return parseProvenance(data, mediaId: mediaId)
        } catch {
            return nil
        }
    }

    // MARK: - Fetch provenance for display

    func fetchProvenance(mediaId: String) async -> TSMediaProvenance? {
        do {
            let result = try await functions
                .httpsCallable("getMediaProvenance")
                .call(["mediaId": mediaId])
            guard let data = result.data as? [String: Any] else { return nil }
            return parseProvenance(data, mediaId: mediaId)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func computeSHA256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseProvenance(_ data: [String: Any], mediaId: String) -> TSMediaProvenance {
        let statusStr = data["provenanceStatus"] as? String ?? "unknown"
        let aiStatusStr = data["aiGeneratedStatus"] as? String ?? "unknown"
        let declarationStr = data["creatorDeclaration"] as? String ?? "unknown"
        return TSMediaProvenance(
            mediaId: mediaId,
            uploaderUid: data["uploaderUid"] as? String ?? "",
            originalHash: data["originalHash"] as? String ?? "",
            perceptualHash: data["perceptualHash"] as? String ?? "",
            aiDetectionScore: data["aiDetectionScore"] as? Double ?? 0,
            editingDetected: data["editingDetected"] as? Bool ?? false,
            creatorDeclaration: TSCreatorDeclaration(rawValue: declarationStr) ?? .unknown,
            provenanceStatus: TSProvenanceStatus(rawValue: statusStr) ?? .unknown,
            trendEligible: data["trendEligible"] as? Bool ?? false,
            boostEligible: data["boostEligible"] as? Bool ?? false,
            labelRequired: data["labelRequired"] as? Bool ?? false,
            policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
        )
    }
}

// MARK: - Creator Declaration Picker

struct CreatorDeclarationPicker: View {
    @Binding var selection: TSCreatorDeclaration
    let onSelect: (TSCreatorDeclaration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this media")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(TSCreatorDeclaration.allCases, id: \.self) { decl in
                Button {
                    selection = decl
                    onSelect(decl)
                } label: {
                    HStack {
                        Text(decl.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == decl {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
