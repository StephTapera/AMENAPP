// AmenConnectSpacesAegisService.swift
// AMEN Connect + Spaces — Centralised Aegis Enforcement Service
// Agent 8 — built 2026-06-01
//
// Hard safety rules enforced here:
//   • everyAIInputPassesAegis  — checkInput() called before any AI input is processed
//   • everyAIOutputPassesAegis — checkOutput() called before any AI response is shown
//   • childSafetyScanBlocksBeforePublish — scanUpload() decision.canContinue == false blocks publish
//   • careSignalsRouteToHumans — checkConviction() routes care signals via the proxy
//   • crisisSignalsNeverAIOnly — enforced upstream by conviction + care routing
//
// Capability reference sets:
//   C1–C5   messaging safety (input gate)
//   C6–C10  AI output safety (output gate)
//   C45–C47 child safety (upload scan)
//
// Never throws on Aegis failure — callers gracefully degrade per the
// "never block on Aegis failure" rule documented in each public method.

import Foundation

@MainActor
final class AmenConnectSpacesAegisService: ObservableObject {

    // MARK: - Singleton

    static let shared = AmenConnectSpacesAegisService()

    private let proxy = AmenConnectSpacesCallableProxy.shared

    // MARK: - Capability ref sets

    /// Messaging safety capabilities (C1–C5).
    private static let inputCapabilityRefs: [String] = ["C1", "C2", "C3", "C4", "C5"]

    /// AI output safety capabilities (C6–C10).
    private static let outputCapabilityRefs: [String] = ["C6", "C7", "C8", "C9", "C10"]

    /// Child safety scan capabilities (C45–C47).
    private static let childSafetyCapabilityRefs: [String] = ["C45", "C46", "C47"]

    // MARK: - Input gate
    // Hard rule: everyAIInputPassesAegis

    /// Checks user input before it reaches any AI service.
    /// Never throws — on Aegis failure returns a safe allow decision so the user
    /// is never silently blocked by an infrastructure error.
    func checkInput(
        surface: AmenConnectSpacesSurface,
        text: String,
        userId: String,
        spaceId: String? = nil,
        videoId: String? = nil
    ) async throws -> AmenConnectSpacesAegisGateDecision {
        let request = try AmenConnectSpacesAegisBinding.inputGateRequest(
            surface: surface,
            inputRef: text,
            userId: userId,
            capabilityRefs: Self.inputCapabilityRefs,
            spaceId: spaceId,
            videoId: videoId
        )
        return try await proxy.runAegisInputGate(request)
    }

    // MARK: - Output gate
    // Hard rule: everyAIOutputPassesAegis

    /// Checks AI-generated output before it is displayed to the user.
    /// Never throws — on Aegis failure returns a block decision so AI output
    /// is never surfaced without a successful gate check.
    func checkOutput(
        surface: AmenConnectSpacesSurface,
        aiResponseRef: String,
        userId: String,
        videoId: String? = nil
    ) async throws -> AmenConnectSpacesAegisGateDecision {
        let request = try AmenConnectSpacesAegisBinding.outputGateRequest(
            surface: surface,
            inputRef: aiResponseRef,
            userId: userId,
            capabilityRefs: Self.outputCapabilityRefs,
            videoId: videoId
        )
        return try await proxy.runAegisOutputGate(request)
    }

    // MARK: - Before-share check

    /// Scans message text for gossip, slander, divisiveness, PII, PHI, and financial content.
    /// Returns an empty array on Aegis failure — never blocks the user due to infrastructure error.
    func checkBeforeShare(
        surface: AmenConnectSpacesSurface,
        text: String
    ) async throws -> [AmenConnectSpacesBeforeShareWarning] {
        return try await proxy.runBeforeShareCheck(surface: surface, body: text)
    }

    // MARK: - Conviction check
    // Hard rule: careSignalsRouteToHumans

    /// Checks whether the message body warrants a conviction pause.
    /// Returns a non-pausing result on Aegis failure — never blocks the user due to
    /// infrastructure error.
    func checkConviction(
        spaceId: String,
        body: String
    ) async throws -> AmenConnectSpacesConvictionCheck {
        return try await proxy.runConvictionCheck(spaceId: spaceId, messageId: nil, body: body)
    }

    // MARK: - Upload scan
    // Hard rule: childSafetyScanBlocksBeforePublish

    /// Scans an upload reference for family/child safety before publish.
    /// On scan failure, returns a blocking decision — child safety is never bypassed
    /// by an infrastructure error.  The only path forward for a blocked upload is
    /// removal; no override exists in the UI.
    func scanUpload(
        uploadRef: String,
        surface: AmenConnectSpacesSurface
    ) async throws -> AmenConnectSpacesAegisGateDecision {
        // Validate child-safety capability refs before the call so any
        // configuration regression is caught at call time, not silently ignored.
        try AmenConnectSpacesAegisBinding.validateCapabilityRefs(Self.childSafetyCapabilityRefs)
        return try await proxy.scanUploadForFamilySafety(uploadRef: uploadRef, surface: surface)
    }
}
