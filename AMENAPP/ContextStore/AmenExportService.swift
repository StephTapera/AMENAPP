// AmenExportService.swift
// AMEN Universal Migration & Context System — Wave 5 (export-engineer)
//
// CLIENT service for the .amen v0.1 portable file: export and import.
//
// CONTRACT (CONTRACTS.md §7/§8 — FROZEN, never modified here)
// ────────────────────────────────────────────────────────────
//   Export calls `exportAmenFile` then `signAmenExport` (both enforceAppCheck + Auth).
//   Import is client-only: parse + validate → return PROPOSED facets (userApproved: false)
//   ready for FacetApprovalView. Nothing is persisted by this service.
//
// NON-NEGOTIABLE INVARIANTS
// ─────────────────────────
//   1. FLAG-GATED — `contextSystemEnabled && contextExportEnabled` must both be true.
//      Every public entry point throws `AmenExportError.exportDisabled` if either is false.
//   2. TIER-P NEVER EXPORTED — even if the caller passes Tier-P facet UUIDs, the server
//      drops them. Additionally, this service never sends facet values to a CF — it sends
//      only UUID strings (the CF reads facets directly from Firestore for the owner only).
//   3. IMPORT ROUTES THROUGH APPROVAL — importFile returns PROPOSED facets with
//      `provenance.userApproved == false`. The caller must route them through
//      FacetApprovalView; nothing is persisted here.
//   4. UNVERIFIED SIGNATURE → mark as unverified, still importable — the CF or the bundled
//      public key may be unavailable; the import path is never silently aborted by a bad sig.
//   5. TIER-P FACETS STRIPPED ON IMPORT — any facet parsed from an .amen file whose
//      category/key maps to Tier P is dropped before returning candidates. An import file
//      may have been produced by a non-standard exporter.
//   6. NO WRITES — this service never touches Firestore, Auth, or UserDefaults.
//
// The canonical .amen v0.1 schema (AmenContextV0_1) is defined at the CF layer;
// this client mirrors only what it needs to decode the response and parse imports.

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Local .amen v0.1 mirror types (decode-only, mirrors exportAmenFile.ts)

/// Provenance as returned in the .amen export (reduced, non-identifying).
private struct AmenExportProvenance: Codable {
    let source: String
    let sourceLabel: String?
    let confidence: Double?
}

/// Structured value in its tagged-union wire shape.
private struct AmenExportStructuredValue: Codable {
    let kind: String
    let payload: AnyCodable
}

/// A single facet in the .amen v0.1 wire format.
private struct AmenExportFacet: Codable {
    let id: String
    let category: String
    let key: String
    let label: String
    let value: AmenExportStructuredValue
    let visibility: String
    let provenance: AmenExportProvenance
    let createdAt: String   // ISO-8601
    let updatedAt: String   // ISO-8601
}

/// The .amen v0.1 document body returned by `exportAmenFile`.
private struct AmenContextDocument: Codable {
    let spec: String
    let version: String
    let exportedAt: String
    let owner: AmenOwner
    let facets: [AmenExportFacet]
}

private struct AmenOwner: Codable {
    let userId: String
}

/// The signature envelope returned by `signAmenExport`.
private struct AmenSignature: Codable {
    let alg: String
    let keyId: String
    let value: String
}

// MARK: - AnyCodable (thin helper for the payload field)

/// Lightweight type-erased Codable value used only for the `payload` field inside an export
/// facet's structured value. The value is stored as a JSON fragment and exposed as a
/// `StructuredFacetValue.text` summary on import; never round-tripped as a rich type.
private struct AnyCodable: Codable {
    let jsonString: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Attempt common types in order; fall back to "?" to avoid a throw.
        if let s = try? container.decode(String.self) {
            jsonString = s
        } else if let a = try? container.decode([String].self) {
            jsonString = a.joined(separator: ", ")
        } else if let d = try? container.decode(Double.self) {
            jsonString = String(d)
        } else if let b = try? container.decode(Bool.self) {
            jsonString = b ? "true" : "false"
        } else {
            // Complex sub-object — produce a JSON representation best-effort.
            if let raw = try? container.decode([String: AnyCodable].self) {
                jsonString = raw.map { "\($0.key): \($0.value.jsonString)" }.sorted().joined(separator: ", ")
            } else {
                jsonString = ""
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(jsonString)
    }
}

// MARK: - Errors

enum AmenExportError: LocalizedError, Equatable {
    case exportDisabled
    case notSignedIn
    case noFacetsSelected
    case serverRejectedExport(String)
    case signingUnavailable
    case malformedFile
    case schemaVersionUnsupported(String)
    case importDisabled

    var errorDescription: String? {
        switch self {
        case .exportDisabled:
            return "Export is turned off (contextSystemEnabled && contextExportEnabled must both be true)."
        case .notSignedIn:
            return "No signed-in user; cannot export context."
        case .noFacetsSelected:
            return "No facets were selected for export."
        case .serverRejectedExport(let reason):
            return "The server rejected the export: \(reason)"
        case .signingUnavailable:
            return "The signing service is unavailable; export cannot produce a verifiable file."
        case .malformedFile:
            return "The .amen file could not be parsed — it may be corrupt or from an incompatible version."
        case .schemaVersionUnsupported(let v):
            return "This .amen file uses schema version \"\(v)\", which is not supported by this app version."
        case .importDisabled:
            return "Import is turned off (contextSystemEnabled && contextExportEnabled must both be true)."
        }
    }
}

// MARK: - Import result

/// The result of a successful `importFile` parse.
///
/// - `proposed`: PROPOSED facets (`userApproved == false`). Route through `FacetApprovalView`.
/// - `signatureVerified`: whether the Ed25519 signature was validated. False = unverified provenance;
///   the facets are still importable via the Approval UI — never auto-persisted.
/// - `ownerUserId`: the `owner.userId` from the file header (for display only; never auto-trusted).
struct AmenImportResult {
    /// Proposed facets ready for FacetApprovalView. All have `provenance.userApproved == false`.
    let proposed: [ContextFacet]
    /// True iff the Ed25519 signature was validated against the bundled public key.
    let signatureVerified: Bool
    /// Stable owner handle from the file header, for provenance display. Never auto-trusted.
    let ownerUserId: String
}

// MARK: - AmenExportService

/// Client façade for the .amen v0.1 export/import system.
///
/// Export: calls `exportAmenFile` (builds the portable file server-side) then `signAmenExport`
/// (produces an Ed25519 signature). Returns both as strings so the caller can share them.
///
/// Import: parses a `.amen` JSON string, validates structure and signature best-effort,
/// returns PROPOSED `ContextFacet` candidates (all `userApproved == false`) for routing
/// through `FacetApprovalView`. Nothing is persisted here.
@MainActor
final class AmenExportService: ObservableObject {

    static let shared = AmenExportService()

    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false
    @Published private(set) var lastExportError: String?
    @Published private(set) var lastImportError: String?

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Export

    /// Build and sign a portable .amen v0.1 file for the given facet IDs.
    ///
    /// - Parameter selectedFacetIds: UUIDs of facets the user explicitly selected for inclusion.
    ///   Public-visibility facets are always included by the server; Tier-P facets are always
    ///   excluded by the server regardless of this list.
    /// - Returns: `(amenJSON, signature)` — the JSON body and its base64 Ed25519 signature.
    ///   Both are needed to share a verifiable file.
    /// - Throws: `AmenExportError` on gate failures or server errors.
    func export(selectedFacetIds: [UUID]) async throws -> (amenJSON: String, signature: String) {
        guard AMENFeatureFlags.shared.contextSystemEnabled,
              AMENFeatureFlags.shared.contextExportEnabled else {
            throw AmenExportError.exportDisabled
        }
        guard Auth.auth().currentUser?.uid != nil else {
            throw AmenExportError.notSignedIn
        }
        guard !selectedFacetIds.isEmpty else {
            throw AmenExportError.noFacetsSelected
        }

        isExporting = true
        lastExportError = nil
        defer { isExporting = false }

        // Step 1: build the .amen document server-side.
        // The CF reads the OWNER's own facets; this client sends only UUID strings (never values).
        let facetIdStrings: [String] = selectedFacetIds.map { $0.uuidString }
        let exportPayload: [String: Any] = ["facetIds": facetIdStrings]

        let exportResult: HTTPSCallableResult
        do {
            exportResult = try await functions
                .httpsCallable("exportAmenFile")
                .call(exportPayload)
        } catch {
            let msg = (error as NSError).localizedDescription
            lastExportError = msg
            throw AmenExportError.serverRejectedExport(msg)
        }

        // Serialize the returned `amen` document to JSON (the shape to sign + share).
        guard let data = exportResult.data as? [String: Any],
              let amenDict = data["amen"] as? [String: Any] else {
            throw AmenExportError.serverRejectedExport("Unexpected response shape from exportAmenFile.")
        }

        let amenJSONData: Data
        do {
            amenJSONData = try JSONSerialization.data(withJSONObject: amenDict, options: [.sortedKeys])
        } catch {
            throw AmenExportError.serverRejectedExport("Could not serialize the .amen document.")
        }
        guard let amenJSON = String(data: amenJSONData, encoding: .utf8) else {
            throw AmenExportError.serverRejectedExport("Could not encode the .amen document as UTF-8.")
        }

        // Step 2: sign the document.
        let signPayload: [String: Any] = ["amen": amenDict]
        let signResult: HTTPSCallableResult
        do {
            signResult = try await functions
                .httpsCallable("signAmenExport")
                .call(signPayload)
        } catch {
            // Signing is best-effort — if unavailable (key not provisioned) surface as a distinct error.
            let msg = (error as NSError).localizedDescription
            lastExportError = msg
            throw AmenExportError.signingUnavailable
        }

        guard let signData = signResult.data as? [String: Any],
              let sigDict = signData["signature"] as? [String: Any],
              let sigValue = sigDict["value"] as? String,
              !sigValue.isEmpty else {
            throw AmenExportError.signingUnavailable
        }

        return (amenJSON: amenJSON, signature: sigValue)
    }

    // MARK: - Import

    /// Parse a `.amen` JSON string into PROPOSED `ContextFacet` candidates.
    ///
    /// The returned facets all have `provenance.userApproved == false`. The caller MUST route
    /// them through `FacetApprovalView`; nothing is persisted here. Tier-P facets parsed from
    /// the file are silently dropped (defense-in-depth: a non-standard exporter may have
    /// included them; the Tier table is law).
    ///
    /// If signature verification fails or no public key is available for the `keyId`, the import
    /// continues with `signatureVerified == false` — the user is shown an "unverified" badge but
    /// can still approve facets individually through the Approval UI.
    ///
    /// - Parameter jsonString: The raw JSON text from a `.amen` file.
    /// - Returns: An `AmenImportResult` with proposed facets + verification state.
    /// - Throws: `AmenExportError.importDisabled` if the gate flags are off; `.malformedFile`
    ///   if the JSON cannot be parsed; `.schemaVersionUnsupported` if the version is not "0.1".
    func importFile(_ jsonString: String) async throws -> AmenImportResult {
        guard AMENFeatureFlags.shared.contextSystemEnabled,
              AMENFeatureFlags.shared.contextExportEnabled else {
            throw AmenExportError.importDisabled
        }

        isImporting = true
        lastImportError = nil
        defer { isImporting = false }

        guard let data = jsonString.data(using: .utf8) else {
            lastImportError = AmenExportError.malformedFile.localizedDescription
            throw AmenExportError.malformedFile
        }

        let document: AmenContextDocument
        do {
            document = try JSONDecoder().decode(AmenContextDocument.self, from: data)
        } catch {
            lastImportError = AmenExportError.malformedFile.localizedDescription
            throw AmenExportError.malformedFile
        }

        // Version gate — only "0.1" is supported in this build.
        guard document.spec == "amen-context", document.version == "0.1" else {
            let v = "\(document.spec)/\(document.version)"
            lastImportError = AmenExportError.schemaVersionUnsupported(v).localizedDescription
            throw AmenExportError.schemaVersionUnsupported(v)
        }

        // We currently do not bundle the Ed25519 public key in this build — signature
        // verification requires the public key for `keyId`. Until the key is embedded,
        // all imports are marked unverified (still importable, never auto-persisted).
        let signatureVerified = false   // TODO(gate: HUMAN-MACHINE) — wave5-verify: embed Ed25519 public key for amen-export-2026-1 in bundle before enabling signature enforcement

        // Map wire facets → proposed ContextFacets (userApproved: false).
        // The current user's UID is used for the userId field. If no user is signed in,
        // the facets are still created but will be rejected at the ContextStoreService
        // write-path tier check (correct behavior — approval gates persistence).
        let importUserId = Auth.auth().currentUser?.uid ?? "imported-unlinked"

        let proposed: [ContextFacet] = document.facets.compactMap { wire in
            buildProposedFacet(wire: wire, userId: importUserId)
        }

        return AmenImportResult(
            proposed: proposed,
            signatureVerified: signatureVerified,
            ownerUserId: document.owner.userId
        )
    }

    // MARK: - Private helpers

    /// Map one wire-format facet to a proposed `ContextFacet`. Returns nil if the facet maps
    /// to Tier P (Tier-P facets are never imported via any server-readable path) or if required
    /// fields are missing/unrecognised.
    private func buildProposedFacet(wire: AmenExportFacet, userId: String) -> ContextFacet? {
        // Parse enums — reject unrecognized values (forward-compat safety).
        guard let category = FacetCategory(rawValue: wire.category) else { return nil }
        guard !wire.key.isEmpty, !wire.label.isEmpty else { return nil }

        // Tier-P drop (defense-in-depth). ContextTierTable is the authoritative tier source.
        let tier = ContextTierTable.tier(for: category, key: wire.key)
        guard tier != .p else { return nil }

        // Map visibility; default to private if unknown.
        let visibility = Visibility(rawValue: wire.visibility) ?? .privateVisibility

        // Map source; default to .derived (imports from another AMEN client).
        let facetSource: FacetSource
        switch wire.provenance.source {
        case "manual":           facetSource = .manual
        case "interview":        facetSource = .interview
        case "extracted_paste":  facetSource = .extracted_paste
        case "extracted_file":   facetSource = .extracted_file
        default:                 facetSource = .derived
        }

        // Map the structured value. We use the .text summary path — the structured types
        // (faithJourney, communicationStyle, relationshipCategory) require re-entry via
        // their dedicated builders and cannot be reconstructed from the reduced export payload.
        let structuredValue: StructuredFacetValue
        switch wire.value.kind {
        case "list":
            // The payload for a list is a comma-joined string in AnyCodable; split it back.
            let items = wire.value.payload.jsonString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            structuredValue = items.isEmpty
                ? .text(wire.value.payload.jsonString)
                : .list(items)
        default:
            structuredValue = .text(wire.value.payload.jsonString)
        }

        // Parse ISO-8601 dates; fall back to now.
        let iso = ISO8601DateFormatter()
        let createdAt = iso.date(from: wire.createdAt) ?? Date()
        let updatedAt = iso.date(from: wire.updatedAt) ?? Date()

        // Build a stable sanitization passId for the import receipt.
        // Format: "import-<facetId>" so the write-path receipt check can identify its origin.
        let sanitizationPassId = "import-\(wire.id)"

        let provenance = Provenance(
            source: facetSource,
            sourceLabel: wire.provenance.sourceLabel ?? "AMEN import",
            extractedAt: updatedAt,
            confidence: wire.provenance.confidence,
            userApproved: false,    // INVARIANT: approval before persistence
            userEdited: false,
            sanitizationPassId: sanitizationPassId
        )

        let id = UUID(uuidString: wire.id) ?? UUID()

        return ContextFacet(
            id: id,
            userId: userId,
            category: category,
            key: wire.key,
            label: wire.label,
            value: structuredValue,
            visibility: visibility,
            tier: tier,
            provenance: provenance,
            createdAt: createdAt,
            updatedAt: updatedAt,
            schemaVersion: 1
        )
    }
}
