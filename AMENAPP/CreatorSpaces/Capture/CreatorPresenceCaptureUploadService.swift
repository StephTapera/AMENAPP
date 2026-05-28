import Foundation
import FirebaseAuth
import FirebaseStorage
import UIKit

@MainActor
final class CreatorPresenceCaptureUploadService {
    static let shared = CreatorPresenceCaptureUploadService()

    private init() {}

    func upload(_ capture: CreatorPresenceCaptureResult, layout: CreatorFrameLayout) async throws -> CreatorPresenceUploadResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw CreatorPresenceCaptureError.uploadFailed
        }

        let draftId = UUID().uuidString
        var backFrame: CreatorMediaFrame?
        var frontFrame: CreatorMediaFrame?
        var compositeFrame: CreatorMediaFrame?

        if let back = capture.back {
            let path = "creator_spaces/\(uid)/\(draftId)/back.jpg"
            try await uploadFrame(back, path: path)
            backFrame = CreatorMediaFrame(storagePath: path, width: back.width, height: back.height)
        }

        if let front = capture.front {
            let path = "creator_spaces/\(uid)/\(draftId)/front.jpg"
            try await uploadFrame(front, path: path)
            frontFrame = CreatorMediaFrame(storagePath: path, width: front.width, height: front.height)
        }

        if let composite = CreatorPresenceImageCompositor.composite(capture, layout: layout) {
            let path = "creator_spaces/\(uid)/\(draftId)/composite_\(layout.rawValue).jpg"
            try await uploadFrame(composite.frame, path: path)
            compositeFrame = CreatorMediaFrame(
                storagePath: path,
                width: composite.frame.width,
                height: composite.frame.height
            )
        }

        let draft = CreatorMediaAssetDraft(
            type: .presence,
            frames: CreatorMediaFrames(back: backFrame, front: frontFrame, composite: compositeFrame, audio: nil, layout: layout),
            context: nil,
            distribution: .profileOnly,
            sourceCamera: capture.isDualCamera ? "ios_front_back" : "ios_single_camera",
            capturedOnDevice: true,
            editedWithAI: false
        )

        let safety = try await CreatorSpacesService.shared.runSafetyCheck(draft)
        guard safety.decision == "ok" || safety.decision == "warn" else {
            throw CreatorPresenceCaptureError.uploadFailed
        }

        let result = try await CreatorSpacesService.shared.processMediaUpload(draft)
        CreatorSpacesAnalytics.track(.presencePostCreated, parameters: [
            "dual_camera": capture.isDualCamera,
            "layout": layout.rawValue
        ])
        if capture.isDualCamera {
            CreatorSpacesAnalytics.track(.dualCameraCaptureUsed)
        }
        return CreatorPresenceUploadResult(assetId: result.assetId, labelId: result.labelId)
    }

    private func uploadFrame(_ frame: CreatorPresenceCapturedFrame, path: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let ref = Storage.storage().reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.putData(frame.data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
