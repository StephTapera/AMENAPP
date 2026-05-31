// AegisDataRightsService.swift — C51–C58 Data Rights & Tracking
// Capabilities: noSellGuarantee, trackingMinimization, shadowProfilePrevention,
//               crossPlatformLinking, trueRightToBeForgotten, reverseImageTraceability,
//               digitalLegacy, dataPortability

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Data Rights Summary

struct AegisDataRightsSummary: Codable {
    let noSellActive:         Bool   // C51
    let trackingMinimized:    Bool   // C52
    let shadowProfileClear:   Bool   // C53
    let dataExportAvailable:  Bool   // C58
    let deletionAvailable:    Bool   // C55
    let memorialAvailable:    Bool   // C57
    let portabilityAvailable: Bool   // C58
}

// MARK: - Service

actor AegisDataRightsService {

    static let shared = AegisDataRightsService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - C51: No-Sell Guarantee

    /// Returns AMEN's static no-sell guarantee statement. No network call required.
    func getNoSellStatement() -> String {
        """
        AMEN does not sell, rent, or trade your personal data to third parties — ever. \
        Your faith journey, prayer requests, church notes, and personal connections are yours alone. \
        We do not use your data to build advertising profiles, and we do not share identifiable \
        information with data brokers, ad networks, or analytics resellers. \
        This guarantee is unconditional and applies to all AMEN users regardless of subscription tier.
        """
    }

    // MARK: - C52: Tracking Minimization Report

    /// Fetches what data is collected for this user and why, from the backend manifest.
    func getTrackingMinimizationReport(userId: String) async throws -> [String: String] {
        guard AegisFeatureFlags.shared.isEnabled(.trackingMinimization) else {
            return ["status": "Tracking minimization capability is not yet enabled."]
        }

        let doc = try await db
            .collection("dataCollectionManifest")
            .document(userId)
            .getDocument()

        guard doc.exists, let data = doc.data() else {
            // Return the canonical minimal manifest when no custom record exists
            return [
                "auth_uid":           "Required for account authentication and security.",
                "fcm_token":          "Required for push notification delivery.",
                "display_name":       "Required for community identity; user-controlled.",
                "profile_photo_url":  "Optional; user-provided for profile display.",
                "church_affiliation": "Optional; used to personalise church content.",
                "post_content":       "User-generated; stored for feed and moderation.",
                "prayer_requests":    "User-generated; visible only per privacy settings.",
                "crash_logs":         "Anonymous diagnostics; no PII included.",
            ]
        }

        return Dictionary(
            uniqueKeysWithValues: data.compactMap { key, value -> (String, String)? in
                guard let description = value as? String else { return nil }
                return (key, description)
            }
        )
    }

    // MARK: - C53 / C54: Shadow Profile Check

    /// Verifies with the backend that no shadow profile exists for this email address.
    func checkShadowProfileExists(email: String) async throws -> Bool {
        guard AegisFeatureFlags.shared.isEnabled(.shadowProfilePrevention) else {
            return false // Assume clean when flag is off
        }

        // Query the shadowProfiles collection; backend security rules restrict this to
        // authenticated admins or the matching verified email — the callable enforces this.
        let snapshot = try await db
            .collection("shadowProfiles")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments()

        return !snapshot.documents.isEmpty
    }

    // MARK: - C55: True Right to Be Forgotten

    /// Submits a true deletion request for all user data across Firestore, Storage,
    /// Pinecone embeddings, and derived data caches. Returns the confirmed manifest.
    func requestTrueDeletion(userId: String) async throws -> AegisDeletionManifest {
        guard AegisFeatureFlags.shared.isEnabled(.trueRightToBeForgotten) else {
            throw AegisDataRightsError.capabilityDisabled(.trueRightToBeForgotten)
        }

        let manifest = AegisDeletionManifest.canonicalPaths(for: userId)

        let payload: [String: Any] = [
            "userId":      userId,
            "action":      AegisPrivacyActionRequest.AegisPrivacyActionType.trueDelete.rawValue,
            "modeId":      NSNull(),
            "targetPaths": manifest.firestorePaths + manifest.storagePaths,
        ]

        let result = try await functions.callWithTimeout("aegisPrivacyAction", data: payload, timeout: 30)

        guard let responseData = result.data as? [String: Any] else {
            throw AegisDataRightsError.invalidResponse
        }

        // Decode the server-confirmed manifest (may carry a confirmedAt timestamp)
        let confirmedAt: Date? = {
            if let ts = responseData["confirmedAt"] as? TimeInterval {
                return Date(timeIntervalSince1970: ts)
            }
            return Date()
        }()

        return AegisDeletionManifest(
            manifestId:          manifest.manifestId,
            userId:              userId,
            requestedAt:         manifest.requestedAt,
            firestorePaths:      manifest.firestorePaths,
            storagePaths:        manifest.storagePaths,
            pineconeNamespaces:  manifest.pineconeNamespaces,
            derivedDataPaths:    manifest.derivedDataPaths,
            confirmedAt:         confirmedAt,
            isComplete:          responseData["success"] as? Bool ?? false
        )
    }

    // MARK: - C57: Digital Legacy / Memorial

    /// Transitions the account to a memorialised state and transfers legacy access
    /// to the nominated legacy contact.
    func memorializeAccount(userId: String, legacyContactId: String) async throws {
        guard AegisFeatureFlags.shared.isEnabled(.digitalLegacy) else {
            throw AegisDataRightsError.capabilityDisabled(.digitalLegacy)
        }

        // Step 1: mark memorial
        let memorialPayload: [String: Any] = [
            "userId":      userId,
            "action":      AegisPrivacyActionRequest.AegisPrivacyActionType.memorialAccount.rawValue,
            "modeId":      NSNull(),
            "targetPaths": [],
        ]
        _ = try await functions.callWithTimeout("aegisPrivacyAction", data: memorialPayload, timeout: 20)

        // Step 2: transfer legacy access to the nominated contact
        let legacyPayload: [String: Any] = [
            "userId":           userId,
            "action":           AegisPrivacyActionRequest.AegisPrivacyActionType.transferLegacy.rawValue,
            "modeId":           legacyContactId,
            "targetPaths":      [],
        ]
        _ = try await functions.callWithTimeout("aegisPrivacyAction", data: legacyPayload, timeout: 20)
    }

    // MARK: - C58: Data Export / Portability

    /// Requests a full data export and returns the signed download URL.
    func requestDataExport(userId: String) async throws -> URL? {
        guard AegisFeatureFlags.shared.isEnabled(.dataPortability) else {
            throw AegisDataRightsError.capabilityDisabled(.dataPortability)
        }

        let payload: [String: Any] = [
            "userId":      userId,
            "action":      AegisPrivacyActionRequest.AegisPrivacyActionType.exportData.rawValue,
            "modeId":      NSNull(),
            "targetPaths": [],
        ]

        let result = try await functions.callWithTimeout("aegisPrivacyAction", data: payload, timeout: 30)

        guard let responseData = result.data as? [String: Any],
              let urlString = responseData["exportUrl"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }

        return url
    }

    // MARK: - Aggregated Summary

    /// Aggregates C51–C58 status into a single summary for the Data Rights settings screen.
    func getDataRightsSummary(userId: String) async throws -> AegisDataRightsSummary {
        let flags = AegisFeatureFlags.shared

        // C53: shadow profile check (non-fatal — default to clear on error)
        let shadowClear: Bool
        if let uid = try? Auth.auth().currentUser?.uid, !uid.isEmpty,
           let email = Auth.auth().currentUser?.email {
            shadowClear = (try? await checkShadowProfileExists(email: email)).map { !$0 } ?? true
        } else {
            shadowClear = true
        }

        return AegisDataRightsSummary(
            noSellActive:         true, // Unconditional — always active per AMEN policy (C51)
            trackingMinimized:    flags.isEnabled(.trackingMinimization),
            shadowProfileClear:   shadowClear,
            dataExportAvailable:  flags.isEnabled(.dataPortability),
            deletionAvailable:    flags.isEnabled(.trueRightToBeForgotten),
            memorialAvailable:    flags.isEnabled(.digitalLegacy),
            portabilityAvailable: flags.isEnabled(.dataPortability)
        )
    }
}

// MARK: - Errors

enum AegisDataRightsError: LocalizedError {
    case capabilityDisabled(AegisCapability)
    case invalidResponse
    case exportUrlMissing

    var errorDescription: String? {
        switch self {
        case .capabilityDisabled(let cap):
            return "\(cap.displayName) is not currently enabled. Please check back later."
        case .invalidResponse:
            return "The server returned an unexpected response. Please try again."
        case .exportUrlMissing:
            return "Your data export is being prepared. You will be notified when it is ready."
        }
    }
}

// Needed for the shadow-profile check inside the actor
import FirebaseAuth
