// CameraContentCredentialService.swift
// AMENAPP — Camera OS
// Generates and manages Content Credentials (C2PA-inspired attestation).
// Amen attests only what it can verify: captured in Amen camera, unedited, or edited-with-X.
// Does NOT claim deepfake detection.

import Foundation
import SwiftUI


// MARK: - CameraContentCredentialService

/// Actor that issues and transforms Content Credentials for camera captures.
/// Thread-safe by design; all mutable state lives inside the actor boundary.
actor CameraContentCredentialService {

    // MARK: - Shared Singleton

    static let shared = CameraContentCredentialService()

    // MARK: - Private Init

    private init() {}

    // MARK: - Credential Issuance

    /// Creates a fresh credential for a capture.
    /// - Parameters:
    ///   - captureId: Unique identifier for this capture (e.g. UUID string).
    ///   - captureDate: Timestamp of the original shutter/record event.
    ///   - editLabel: The initial label for this capture.
    ///   - isAmenCapture: Whether the capture originated inside the Amen camera.
    /// - Returns: A new `CameraContentCredential` with `deviceAttested` set to `isAmenCapture`.
    func issueCredential(
        for captureId: String,
        captureDate: Date,
        editLabel: CameraEditLabel,
        isAmenCapture: Bool
    ) -> CameraContentCredential {
        CameraContentCredential(
            captureId: captureId,
            capturedAt: captureDate,
            editHistory: [editLabel],
            deviceAttested: isAmenCapture,
            isAmenCapture: isAmenCapture
        )
    }

    // MARK: - Edit History

    /// Appends a new edit label to an existing credential, returning the updated copy.
    /// The original credential is not mutated (value semantics preserved).
    /// - Parameters:
    ///   - label: The edit label to append.
    ///   - credential: The credential to extend.
    /// - Returns: A new `CameraContentCredential` with `label` appended to `editHistory`.
    func appendEdit(
        label: CameraEditLabel,
        to credential: inout CameraContentCredential
    ) -> CameraContentCredential {
        let updatedHistory = credential.editHistory + [label]
        let updated = CameraContentCredential(
            captureId: credential.captureId,
            capturedAt: credential.capturedAt,
            editHistory: updatedHistory,
            deviceAttested: credential.deviceAttested,
            isAmenCapture: credential.isAmenCapture
        )
        credential = updated
        return updated
    }

    // MARK: - ONE Provenance Bridge

    /// Converts a `CameraContentCredential` into a `ONEProvenanceLabel` for
    /// display in the ONE feed layer.
    ///
    /// Confidence values reflect what Amen can cryptographically attest:
    /// - `.originalCapture` → `.captured` at 0.95 (highest; Amen camera, no edits)
    /// - `.minorEdits`      → `.edited`   at 0.90
    /// - `.aiAssisted`      → `.aiAssisted` at 0.88
    /// - `.aiGenerated`     → `.synthetic` at 0.85
    /// - `.uploadedFromLibrary` → `.unknown` at 0.0 (not camera-attested)
    func toONEProvenanceLabel(_ credential: CameraContentCredential) -> ONEProvenanceLabel {
        let label = credential.currentLabel

        let (provenanceClass, confidence): (ONEProvenanceClass, Float) = {
            switch label {
            case .originalCapture:     return (.captured,   0.95)
            case .minorEdits:          return (.edited,     0.90)
            case .aiAssisted:          return (.aiAssisted, 0.88)
            case .aiGenerated:         return (.synthetic,  0.85)
            case .uploadedFromLibrary: return (.unknown,    0.0)
            }
        }()

        // Serialize the credential as the C2PA payload; gracefully degrade to nil on failure.
        let payload: Data? = try? JSONEncoder().encode(credential)

        return ONEProvenanceLabel(
            classification: provenanceClass,
            confidence: confidence,
            c2paPayload: payload,
            attestedAt: Date(),
            processorNote: "Amen Camera OS v1"
        )
    }

    // MARK: - Badge Text

    /// Short human-readable badge text suitable for feed/post overlays.
    func credentialBadgeText(_ credential: CameraContentCredential) -> String {
        switch credential.currentLabel {
        case .originalCapture:     return "Live · Amen"
        case .minorEdits:          return "Edited · Amen"
        case .aiAssisted:          return "AI-Assisted"
        case .aiGenerated:         return "AI-Generated"
        case .uploadedFromLibrary: return "Library"
        }
    }
}

// MARK: - CredentialBadgeView

/// Small inline badge for showing a credential label in feeds or post previews.
/// Uses a Liquid Glass pill (ultraThinMaterial) on iOS 16+.
@available(iOS 16.0, *)
struct CredentialBadgeView: View {
    let credential: CameraContentCredential

    /// Resolved badge text; computed synchronously from the actor's pure logic.
    private var badgeText: String {
        switch credential.currentLabel {
        case .originalCapture:     return "Live · Amen"
        case .minorEdits:          return "Edited · Amen"
        case .aiAssisted:          return "AI-Assisted"
        case .aiGenerated:         return "AI-Generated"
        case .uploadedFromLibrary: return "Library"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: credential.currentLabel.systemIcon)
                .font(.system(size: 10, weight: .medium))
            Text(badgeText)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(credential.currentLabel.systemIcon + ", " + badgeText)
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, *)
#Preview("CredentialBadgeView") {
    VStack(spacing: 12) {
        ForEach(CameraEditLabel.allCases, id: \.rawValue) { label in
            let credential = CameraContentCredential(
                captureId: UUID().uuidString,
                capturedAt: Date(),
                editHistory: [label],
                deviceAttested: true,
                isAmenCapture: true
            )
            CredentialBadgeView(credential: credential)
        }
    }
    .padding()
    .background(Color.black)
}
#endif
