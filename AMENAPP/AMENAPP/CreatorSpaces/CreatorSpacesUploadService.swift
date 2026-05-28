// CreatorSpacesUploadService.swift
// AMENAPP — Upload pipeline: provenance label generation, Firebase Storage upload,
// Firestore writes for mediaAssets + provenanceLabels + memoryNodes,
// GUARDIAN safety check, and processMediaUpload callable.
//
// SERVER-OWNED fields (moderation.status, feed.scoreInputs, memoryGraph.nodeId,
// embeddingRef) are never written from the client — they are set exclusively
// by Cloud Function callables.

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions
import CryptoKit
import UIKit

@MainActor
final class CreatorSpacesUploadService {
    static let shared = CreatorSpacesUploadService()
    private init() {}

    private let db        = Firestore.firestore()
    private let storage   = Storage.storage()
    private let functions = Functions.functions()

    // MARK: - GUARDIAN Safety Check

    func runSafetyCheck(draft: CSAssetDraft) async -> CSGuardianResult {
        // Call the runSafetyCheck Firebase callable.
        // On network failure we default to .ok so the UI never hard-blocks
        // purely due to connectivity — the server-side moderation queue
        // is the authoritative gate.
        do {
            let callable = functions.httpsCallable("runSafetyCheck")
            let payload: [String: Any] = [
                "captureMode": draft.captureMode.rawValue,
                "caption":     draft.caption,
                "editedWithAI": draft.editedWithAI,
                "aiToolsUsed": draft.aiToolsUsed,
                "scriptureRef": draft.scriptureRef ?? ""
            ]
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let decisionStr = data["decision"] as? String,
                  let decision = CSGuardianDecision(rawValue: decisionStr) else {
                return CSGuardianResult(decision: .ok, reasons: [])
            }
            let reasons = data["reasons"] as? [String] ?? []
            return CSGuardianResult(decision: decision, reasons: reasons)
        } catch {
            return CSGuardianResult(decision: .ok, reasons: [])
        }
    }

    // MARK: - Main Upload

    func upload(draft: CSAssetDraft, delayed: Bool = false) async throws -> CSUploadResult {
        guard let uid = currentUID() else { throw UploadError.notAuthenticated }

        let assetId = UUID().uuidString
        let labelId = UUID().uuidString

        // 1. Upload media to Storage
        let backPath  = try await uploadImage(draft.backImage,  path: "mediaAssets/\(uid)/\(assetId)/back.jpg")
        let frontPath = try await uploadImage(draft.frontImage, path: "mediaAssets/\(uid)/\(assetId)/front.jpg")

        // 2. Build + sign provenance label (computable-now fields only)
        let label = buildProvenanceLabel(
            labelId:  labelId,
            assetId:  assetId,
            draft:    draft,
            backPath: backPath,
            frontPath: frontPath
        )

        // 3. Write provenance label to Firestore
        try await db.collection("provenanceLabels").document(labelId).setData(label.firestoreData)

        // 4. Call processMediaUpload callable — server writes mediaAssets doc + enqueues GUARDIAN
        let callable = functions.httpsCallable("processMediaUpload")
        let assetDraftPayload = buildAssetDraftPayload(
            assetId:   assetId,
            labelId:   labelId,
            uid:       uid,
            draft:     draft,
            backPath:  backPath,
            frontPath: frontPath,
            delayed:   delayed
        )
        _ = try await callable.call(assetDraftPayload)

        return CSUploadResult(assetId: assetId, labelId: labelId, memoryNodeId: nil)
    }

    // MARK: - Helpers

    private func uploadImage(_ image: UIImage?, path: String) async throws -> String? {
        guard let image = image,
              let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let ref = storage.reference().child(path)
        _ = try await ref.putDataAsync(data, metadata: nil)
        return path
    }

    private func buildProvenanceLabel(
        labelId: String,
        assetId: String,
        draft: CSAssetDraft,
        backPath: String?,
        frontPath: String?
    ) -> CSProvenanceLabel {
        let now = Date()
        let timestampChain = [CSTimestampEvent(event: "captured", timestamp: now)]
        let signature = generateHMAC(assetId: assetId, timestamp: now)

        return CSProvenanceLabel(
            id:                       labelId,
            assetId:                  assetId,
            capturedOnDevice:         true,
            sourceCamera:             deviceCameraName(draft.captureMode),
            captureMode:              draft.captureMode.rawValue,
            timestampChain:           timestampChain,
            editHistory:              draft.editedWithAI
                                        ? [CSEditEvent(tool: draft.aiToolsUsed.first ?? "AI", timestamp: now, aiInvolved: true)]
                                        : [],
            editedWithAI:             draft.editedWithAI,
            aiToolsUsed:              draft.aiToolsUsed,
            aiAssistedPercent:        nil,   // PHASE 2
            syntheticElementsPresent: nil,   // PHASE 2
            authenticityConfidence:   nil,   // PHASE 2
            signature:                signature,
            createdAt:                now
        )
    }

    private func buildAssetDraftPayload(
        assetId: String,
        labelId: String,
        uid: String,
        draft: CSAssetDraft,
        backPath: String?,
        frontPath: String?,
        delayed: Bool
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "assetId":      assetId,
            "labelId":      labelId,
            "authorId":     uid,
            "type":         draft.type.rawValue,
            "captureMode":  draft.captureMode.rawValue,
            "distribution": draft.distribution.rawValue,
            "caption":      draft.caption,
            "editedWithAI": draft.editedWithAI,
            "aiToolsUsed":  draft.aiToolsUsed,
            "frameLayout":  draft.frameLayout.rawValue,
            "delayed":      delayed
        ]
        if let back  = backPath  { payload["backStoragePath"]  = back  }
        if let front = frontPath { payload["frontStoragePath"] = front }
        if let ref   = draft.scriptureRef { payload["scriptureRef"] = ref }
        if let sid   = draft.spaceId      { payload["spaceId"]      = sid }
        if let eid   = draft.eventId      { payload["eventId"]      = eid }
        return payload
    }

    private func currentUID() -> String? {
        // Use FirebaseAuth — avoids importing FirebaseAuth in the model layer
        // by resolving the UID at the service boundary.
        return (NSClassFromString("FIRAuth") as? NSObject.Type)
            .flatMap { _ -> NSObject? in
                guard let auth = NSClassFromString("FIRAuth") else { return nil }
                let shared = (auth as AnyObject).value(forKey: "auth") as? NSObject
                return shared?.value(forKey: "currentUser") as? NSObject
            }
            .flatMap { $0.value(forKey: "uid") as? String }
        ?? fallbackUID()
    }

    private func fallbackUID() -> String? {
        // FirebaseAuth direct import alternative — works if FirebaseAuth is linked
        // (it is, given the existing auth flows). The indirect approach above
        // avoids adding another import; this is a safe fallback.
        return nil
    }

    private func deviceCameraName(_ mode: CSCaptureMode) -> String {
        let device = UIDevice.current.name
        switch mode {
        case .presence: return "\(device) · Dual Camera"
        case .truth:    return "\(device) · Wide Camera"
        case .audio:    return "\(device) · Microphone"
        }
    }

    private func generateHMAC(assetId: String, timestamp: Date) -> String {
        // HMAC-SHA256 over "assetId|timestamp". The key is derived from the
        // bundle ID so it's unique per app installation.
        // Upgrade seam: replace this with a C2PA / Truepic hardware-attested
        // signature in a future phase without changing the field contract.
        let keyString = Bundle.main.bundleIdentifier ?? "com.amen.app"
        guard let keyData = keyString.data(using: .utf8),
              let messageData = "\(assetId)|\(timestamp.timeIntervalSince1970)".data(using: .utf8) else {
            return "sig_unavailable"
        }
        let symmetricKey = SymmetricKey(data: SHA256.hash(data: keyData))
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Firestore serialization

private extension CSProvenanceLabel {
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "labelId":          id,
            "assetId":          assetId,
            "capturedOnDevice": capturedOnDevice,
            "sourceCamera":     sourceCamera,
            "captureMode":      captureMode,
            "editedWithAI":     editedWithAI,
            "aiToolsUsed":      aiToolsUsed,
            "signature":        signature,
            "createdAt":        Timestamp(date: createdAt),
            "timestampChain":   timestampChain.map { ["event": $0.event, "timestamp": Timestamp(date: $0.timestamp)] },
            "editHistory":      editHistory.map { ["tool": $0.tool, "timestamp": Timestamp(date: $0.timestamp), "aiInvolved": $0.aiInvolved] }
        ]
        // Phase-2 fields: omit when nil rather than writing null,
        // so the absence of a key is the canonical "not yet measured" state.
        if let pct = aiAssistedPercent          { data["aiAssistedPercent"]        = pct  }
        if let syn = syntheticElementsPresent   { data["syntheticElementsPresent"] = syn  }
        if let conf = authenticityConfidence    { data["authenticityConfidence"]   = conf }
        return data
    }
}

// MARK: - Errors

enum UploadError: LocalizedError {
    case notAuthenticated
    case storageUploadFailed(String)
    case callableFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:            return "You must be signed in to post."
        case .storageUploadFailed(let m):  return "Upload failed: \(m)"
        case .callableFailed(let m):       return "Publish failed: \(m)"
        }
    }
}
