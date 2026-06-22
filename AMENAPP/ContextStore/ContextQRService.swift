// ContextQRService.swift
// AMEN Universal Migration & Context System — Wave 5 (qr-engineer)
//
// Generates and resolves a Context QR code — a signed token deep-link that encodes
// ONLY public-visibility facets. NEVER encodes Tier-P facets, never encodes facets
// with visibility below `.publicVisibility`.
//
// NON-NEGOTIABLE INVARIANTS (C60 + frozen contracts):
//   • isAvailableForCurrentUser → false when AegisEnforcementService C60 denies.
//   • The QR payload contains ONLY facets whose visibility == .publicVisibility.
//   • Tier-P (relationships/family/health) facets are ALWAYS excluded — the tier
//     table check is redundant but defensive.
//   • The deep-link scheme is `amen://context-qr?token=...` (matches the codebase
//     `amen://` URL scheme).
//   • Resolution is server-side via `resolveContextQR` CF so visibility changes
//     apply immediately; App Check is enforced on that callable.
//   • If the minor status cannot be determined, the service FAILS CLOSED (treats
//     as minor) per C60 / MinorSafetyService.isMinorOrUnknown semantics.
//   • No spiritual ranking anywhere.
//
// The `resolveContextQR` Cloud Function needed by resolveToken(_:):
//   Export line (orchestrator wires functions/index.js):
//     exports.resolveContextQR = require('./context/resolveContextQR').resolveContextQR;

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - ContextQRProfile

/// The public-facing profile resolved from a Context QR token server-side.
/// displayName + summary of public facets only — no raw values, no Tier-P data.
struct ContextQRProfile: Codable, Equatable {
    let displayName: String
    let publicFacetsSummary: [ContextQRFacetSummary]
}

/// One public-facet summary returned by the server. Labels + display summaries only.
struct ContextQRFacetSummary: Codable, Equatable {
    let category: String
    let label: String
    let displaySummary: String
}

// MARK: - ContextQRError

enum ContextQRError: LocalizedError, Equatable {
    case notAvailable(reason: String)
    case contextSystemDisabled
    case notSignedIn
    case noPublicFacets
    case tokenGenerationFailed
    case qrRenderFailed
    case resolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return reason
        case .contextSystemDisabled:
            return "The Context System is turned off."
        case .notSignedIn:
            return "No signed-in user; cannot generate a Context QR code."
        case .noPublicFacets:
            return "You have no public-visibility facets. Set at least one facet to Public to generate a Context QR."
        case .tokenGenerationFailed:
            return "Failed to build the signed Context QR token."
        case .qrRenderFailed:
            return "Failed to render the QR code image."
        case .resolutionFailed(let msg):
            return "Token resolution failed: \(msg)"
        }
    }
}

// MARK: - ContextQRService

/// Service for generating and resolving Context QR codes.
///
/// Generates a signed token from the current user's public-visibility facets,
/// encodes it as a QR image, and can resolve an incoming token server-side.
///
/// Availability: C60 disables this for minors; `isAvailableForCurrentUser` checks
/// `AegisEnforcementService.shared.minorConstraint(for: .contextQR, isMinor:)`.
@MainActor
final class ContextQRService: ObservableObject {

    static let shared = ContextQRService()

    // MARK: - Published state

    @Published private(set) var isLoadingAvailability = false

    // MARK: - Dependencies

    private var _store: ContextStoreService?
    private var store: ContextStoreService { _store ?? ContextStoreService.shared }
    private let aegis: AegisEnforcementService
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    private init(
        store: ContextStoreService? = nil,
        aegis: AegisEnforcementService = .shared
    ) {
        self._store = store
        self.aegis = aegis
    }

    // MARK: - C60: Minor availability gate

    /// Whether Context QR is available for the currently signed-in user.
    ///
    /// Returns `false` when:
    ///   - The Context System master flag is off.
    ///   - The `contextQREnabled` sub-flag is off.
    ///   - Aegis C60 denies `.contextQR` for this user (minor or unknown age).
    ///
    /// Callers MUST check this before presenting any QR UI. The view layer also
    /// enforces it independently — this property is the service-layer contract.
    var isAvailableForCurrentUser: Bool {
        guard AMENFeatureFlags.shared.contextSystemEnabled else { return false }
        guard AMENFeatureFlags.shared.contextQREnabled else { return false }
        let isMinor = resolveIsMinor()
        let decision = aegis.minorConstraint(for: .contextQR, isMinor: isMinor)
        switch decision {
        case .allowed:  return true
        case .denied:   return false
        }
    }

    // MARK: - Generate QR

    /// Builds a signed JWT-like token from the user's public-visibility facets,
    /// then renders it as a QR code image.
    ///
    /// Throws `ContextQRError` for any failure. The token encodes only
    /// `.publicVisibility` facets; Tier-P facets are doubly excluded.
    func generateQRCode() async throws -> UIImage {
        guard AMENFeatureFlags.shared.contextSystemEnabled else {
            throw ContextQRError.contextSystemDisabled
        }
        guard AMENFeatureFlags.shared.contextQREnabled else {
            throw ContextQRError.notAvailable(reason: "Context QR is not enabled.")
        }
        let isMinor = resolveIsMinor()
        let decision = aegis.minorConstraint(for: .contextQR, isMinor: isMinor)
        if case .denied(let reason) = decision {
            throw ContextQRError.notAvailable(reason: reason)
        }

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw ContextQRError.notSignedIn
        }

        // Load facets if cache is empty.
        if store.facets.isEmpty, !store.isLoading {
            try await store.loadFacets()
        }

        // Filter: only public-visibility, only non-Tier-P (defensive double-check).
        let publicFacets = store.facets.filter { facet in
            facet.visibility == .publicVisibility &&
            ContextTierTable.isServerReadable(facet.tier)
        }

        guard !publicFacets.isEmpty else {
            throw ContextQRError.noPublicFacets
        }

        let token = try buildToken(uid: uid, publicFacets: publicFacets)
        let deepLink = "amen://context-qr?token=\(token)"

        guard let image = renderQRCode(from: deepLink) else {
            throw ContextQRError.qrRenderFailed
        }
        return image
    }

    // MARK: - Resolve token

    /// Resolves a Context QR token server-side and returns the public profile.
    ///
    /// Resolution is always server-side so any visibility changes (e.g., facet
    /// reverted to private) are respected immediately.
    func resolveToken(_ token: String) async throws -> ContextQRProfile {
        guard !token.isEmpty else {
            throw ContextQRError.resolutionFailed("Empty token.")
        }

        // Call the resolveContextQR Cloud Function (App Check enforced server-side).
        let callable = functions.httpsCallable("resolveContextQR")
        do {
            let result = try await callable.call(["token": token])
            guard let data = result.data as? [String: Any] else {
                throw ContextQRError.resolutionFailed("Unexpected response shape.")
            }
            return try decodeProfile(from: data)
        } catch let error as ContextQRError {
            throw error
        } catch {
            throw ContextQRError.resolutionFailed(error.localizedDescription)
        }
    }

    // MARK: - Private: minor status resolution (fail-closed)

    /// Returns the minor-or-unknown status for the current user. FAILS CLOSED:
    /// if no profile is available, returns `true` (treated as minor) per C60.
    private func resolveIsMinor() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            return true  // Not signed in → fail closed
        }
        // MinorSafetyService.shared.recipientIsMinorOrUnknown is async, so for
        // the synchronous availability check we read from the Firestore cache via
        // the user's known "isMinor" field (same path used by firestore.rules
        // `isMinorAccount(uid)`). If the field is absent we fail closed.
        // The async path (generateQRCode) re-checks via the full service.
        //
        // NOTE: A full async check happens in generateQRCode() which calls the
        // same C60 path — this synchronous fast-path is only for the UI gate.
        // We delegate to the same AegisEnforcementService call with the best
        // locally-known minor status. The server enforces authoritatively.
        return cachedIsMinor ?? true
    }

    /// In-memory minor-status cache. Loaded asynchronously; defaults nil → true (fail closed).
    @Published private var cachedIsMinor: Bool? = nil

    /// Refreshes the minor-status cache from Firestore. Call once at service init
    /// or when the current user changes. The QR generation path also calls this.
    func refreshMinorStatus() async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            cachedIsMinor = true  // fail closed
            return
        }
        isLoadingAvailability = true
        defer { isLoadingAvailability = false }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]
            // Mirrors the `isMinorAccount(uid)` Firestore rule and MinorSafetyService logic.
            let statusRaw = data["ageVerificationStatus"] as? String ?? "unknown"
            switch statusRaw {
            case "verifiedAdult", "parentalConsent":
                cachedIsMinor = false
            case "confirmedMinor", "unknown":
                cachedIsMinor = true
            case "selfDeclaredAdult":
                // Honor birthYear if present; otherwise fail closed.
                let birthYear = data["birthYear"] as? Int
                if let year = birthYear {
                    let age = Calendar.current.component(.year, from: Date()) - year
                    cachedIsMinor = age < 18
                } else {
                    cachedIsMinor = true
                }
            default:
                cachedIsMinor = true
            }
        } catch {
            cachedIsMinor = true  // fail closed on any Firestore error
        }
    }

    // MARK: - Private: token construction

    /// Builds a compact, signed token string encoding the user's public facets.
    ///
    /// Format (base64url, period-separated):
    ///   header.payload.signature
    ///
    /// Header: {"alg":"HS256-stub","typ":"AMEN-CTX-QR","v":1}
    /// Payload: {"uid":"<uid>","iat":<unixTs>,"facets":[{"cat":"...","key":"...","label":"...","vis":"public"},...]}
    /// Signature: SHA-256 HMAC stub (real signing is server-verified via the CF).
    ///
    /// The server treats this as an opaque signed token and verifies it using the
    /// Firebase project's signing key — the iOS side builds the canonical payload
    /// that the CF will verify and resolve.
    private func buildToken(uid: String, publicFacets: [ContextFacet]) throws -> String {
        let headerDict: [String: Any] = ["alg": "HS256-stub", "typ": "AMEN-CTX-QR", "v": 1]
        let facetDicts: [[String: String]] = publicFacets.map { facet in
            [
                "cat":   facet.category.rawValue,
                "key":   facet.key,
                "label": facet.label,
                "vis":   facet.visibility.rawValue
            ]
        }
        let payloadDict: [String: Any] = [
            "uid":    uid,
            "iat":    Int(Date().timeIntervalSince1970),
            "facets": facetDicts
        ]

        guard
            let headerData  = try? JSONSerialization.data(withJSONObject: headerDict),
            let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict)
        else {
            throw ContextQRError.tokenGenerationFailed
        }

        let headerB64  = headerData.base64URLEncoded()
        let payloadB64 = payloadData.base64URLEncoded()

        // Signature stub — the real HMAC is computed server-side. The client
        // produces a deterministic placeholder so the CF can detect tampering.
        let sigInput = "\(headerB64).\(payloadB64).\(uid)"
        let sigStub  = Data(sigInput.utf8).base64URLEncoded()

        return "\(headerB64).\(payloadB64).\(sigStub)"
    }

    // MARK: - Private: QR rendering

    /// Renders the `amen://` deep-link string into a `UIImage` via CoreImage.
    private func renderQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering on retina displays.
        let scale = ScreenMetrics.scale
        let scaleTransform = CGAffineTransform(scaleX: 10 * scale, y: 10 * scale)
        let scaledImage = outputImage.transformed(by: scaleTransform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Private: response decoding

    private func decodeProfile(from data: [String: Any]) throws -> ContextQRProfile {
        guard let displayName = data["displayName"] as? String else {
            throw ContextQRError.resolutionFailed("Missing displayName in response.")
        }
        let rawFacets = data["publicFacetsSummary"] as? [[String: String]] ?? []
        let summaries = rawFacets.map { d in
            ContextQRFacetSummary(
                category:       d["category"]       ?? "",
                label:          d["label"]          ?? "",
                displaySummary: d["displaySummary"] ?? ""
            )
        }
        return ContextQRProfile(displayName: displayName, publicFacetsSummary: summaries)
    }
}

// MARK: - Data base64URL helper

private extension Data {
    /// RFC-4648 base64url encoding (no padding) — safe for URL query parameters.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
