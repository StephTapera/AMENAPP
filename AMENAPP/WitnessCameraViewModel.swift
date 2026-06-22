import Foundation
import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class WitnessCameraViewModel: ObservableObject {
    @Published var surfaceMode: WitnessCameraSurfaceMode = .photo
    @Published var primaryCamera: WitnessPrimaryCamera = .back
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var isRecording = false
    @Published var recordingProgress: Double = 0
    @Published var reviewState: WitnessCaptureReviewState?
    @Published var isSessionReady = false
    @Published var isPreparing = false
    @Published var alertMessage: String?
    @Published var multiCamActive = false
    @Published var lastFallbackReason: String?

    let permissionManager = CameraPermissionManager()
    let singleCamService = SingleCamCaptureService()
    let multiCamService = MultiCamCaptureService()

    let maxVideoDuration: TimeInterval = 15
    let maxRetakes = 1

    private var recordTask: Task<Void, Never>?
    private var currentRetakeCount = 0

    var backPreviewLayer: AVCaptureVideoPreviewLayer {
        multiCamService.backPreviewLayer
    }

    var frontPreviewLayer: AVCaptureVideoPreviewLayer {
        multiCamService.frontPreviewLayer
    }

    var singlePreviewSession: AVCaptureSession {
        singleCamService.session
    }

    var isFlashAvailable: Bool {
        if multiCamActive {
            return true
        }
        return singleCamService.isFlashAvailable()
    }

    var canUseMultiCam: Bool {
        multiCamService.isSupported
    }

    func prepare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            switch surfaceMode {
            case .photo:
                try await permissionManager.requestPhotoPermissions()
            case .video:
                try await permissionManager.requestVideoPermissions()
            }
            try await configureActiveService()
            isSessionReady = true
        } catch {
            alertMessage = error.localizedDescription
            isSessionReady = false
        }
    }

    func startSession() {
        if multiCamActive {
            multiCamService.startRunning()
        } else {
            singleCamService.startRunning()
        }
    }

    func stopSession() {
        if multiCamActive {
            multiCamService.stopRunning()
        } else {
            singleCamService.stopRunning()
        }
    }

    func handleDismiss() {
        recordTask?.cancel()
        if isRecording {
            Task {
                _ = try? await singleCamService.stopRecording()
            }
        }
        stopSession()
    }

    func switchSurfaceMode(_ mode: WitnessCameraSurfaceMode) {
        guard surfaceMode != mode else { return }
        surfaceMode = mode
        reviewState = nil
        Task {
            await prepare()
            startSession()
        }
    }

    func swapPrimaryCamera() {
        primaryCamera = primaryCamera == .back ? .front : .back

        guard !multiCamActive else { return }
        Task {
            do {
                _ = try await singleCamService.switchCamera()
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func toggleFlash() {
        guard isFlashAvailable else { return }
        flashMode = flashMode == .off ? .auto : .off
    }

    func capture(using pipLayout: WitnessPiPLayout) async {
        do {
            switch surfaceMode {
            case .photo:
                try await capturePhoto(using: pipLayout)
            case .video:
                try await captureOrStopVideo(using: pipLayout)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func acceptReview(with coordinator: CreatePostCameraCoordinator) {
        guard let reviewState else { return }
        WitnessCameraAnalytics.track("witness_review_accepted", parameters: [
            "mode": reviewState.attachment.mode.rawValue
        ])
        coordinator.attachCapturedMediaToDraft(reviewState.attachment)
    }

    func discardReview() {
        if let attachment = reviewState?.attachment {
            WitnessMediaComposer.removeLocalAssets(for: attachment)
        }
        reviewState = nil
        WitnessCameraAnalytics.track("witness_review_discarded", parameters: nil)
    }

    func canRetake() -> Bool {
        currentRetakeCount < maxRetakes
    }

    private func configureActiveService() async throws {
        stopSession()

        if surfaceMode == .photo && canUseMultiCam {
            do {
                try await multiCamService.configure()
                multiCamActive = true
                WitnessCameraAnalytics.track("multi_cam_started", parameters: ["mode": "photo"])
                return
            } catch {
                multiCamActive = false
                lastFallbackReason = error.localizedDescription
                WitnessCameraAnalytics.track("multi_cam_failed_fallback_single", parameters: [
                    "reason": error.localizedDescription,
                    "mode": "photo"
                ])
            }
        }

        multiCamActive = false
        let position: AVCaptureDevice.Position = primaryCamera == .back ? .back : .front
        try await singleCamService.configure(position: position, includeAudio: surfaceMode == .video)
    }

    private func capturePhoto(using pipLayout: WitnessPiPLayout) async throws {
        let attachment: WitnessDraftAttachment

        if multiCamActive {
            let capture = try await multiCamService.captureDualPhoto(backFlashMode: flashMode)
            let primary = primaryCamera == .back ? capture.back : capture.front
            let pip = primaryCamera == .back ? capture.front : capture.back
            let composed = try WitnessMediaComposer.composeDualPhoto(primary: primary, pip: pip, layout: pipLayout)

            let finalAsset = WitnessMediaAssetDescriptor(
                localPath: composed.finalURL.path,
                width: Int(composed.size.width.rounded()),
                height: Int(composed.size.height.rounded()),
                contentType: "image/jpeg"
            )
            let thumbnailAsset = WitnessMediaAssetDescriptor(
                localPath: composed.thumbnailURL.path,
                width: 640,
                height: 640,
                contentType: "image/jpeg"
            )

            attachment = WitnessDraftAttachment(
                mode: .dualPhoto,
                primaryCamera: primaryCamera,
                layout: primaryCamera == .back ? .backPrimary : .frontPrimary,
                pipLayout: pipLayout,
                captureTimestamp: Date(),
                retakeCount: currentRetakeCount,
                deviceMultiCamSupported: canUseMultiCam,
                finalAsset: finalAsset,
                frontAsset: WitnessMediaAssetDescriptor(contentType: "image/jpeg"),
                backAsset: WitnessMediaAssetDescriptor(contentType: "image/jpeg"),
                thumbnailAsset: thumbnailAsset
            )
            WitnessCameraAnalytics.track("witness_photo_captured", parameters: ["mode": "dualPhoto"])
        } else {
            let image = try await singleCamService.capturePhoto(flashMode: flashMode)
            let prepared = try WitnessMediaComposer.prepareSinglePhoto(image)
            let finalAsset = WitnessMediaAssetDescriptor(
                localPath: prepared.finalURL.path,
                width: Int(prepared.size.width.rounded()),
                height: Int(prepared.size.height.rounded()),
                contentType: "image/jpeg"
            )
            let thumbnailAsset = WitnessMediaAssetDescriptor(
                localPath: prepared.thumbnailURL.path,
                width: 640,
                height: 640,
                contentType: "image/jpeg"
            )
            attachment = WitnessDraftAttachment(
                mode: .singlePhoto,
                primaryCamera: primaryCamera,
                layout: primaryCamera == .back ? .backPrimary : .frontPrimary,
                pipLayout: pipLayout,
                captureTimestamp: Date(),
                retakeCount: currentRetakeCount,
                deviceMultiCamSupported: canUseMultiCam,
                finalAsset: finalAsset,
                thumbnailAsset: thumbnailAsset
            )
            WitnessCameraAnalytics.track("witness_photo_captured", parameters: ["mode": "singlePhoto"])
        }

        reviewState = WitnessCaptureReviewState(attachment: attachment, canRetake: canRetake())
    }

    private func captureOrStopVideo(using pipLayout: WitnessPiPLayout) async throws {
        if isRecording {
            let recordedURL = try await singleCamService.stopRecording()
            recordTask?.cancel()
            isRecording = false
            recordingProgress = 0

            let prepared = try await WitnessMediaComposer.prepareSingleVideo(recordedURL)
            let finalAsset = WitnessMediaAssetDescriptor(
                localPath: prepared.videoURL.path,
                width: Int(prepared.size.width.rounded()),
                height: Int(prepared.size.height.rounded()),
                durationSec: prepared.duration,
                contentType: "video/mp4"
            )
            let thumbnailAsset = WitnessMediaAssetDescriptor(
                localPath: prepared.thumbnailURL.path,
                width: 640,
                height: 640,
                contentType: "image/jpeg"
            )
            let attachment = WitnessDraftAttachment(
                mode: .singleVideo,
                primaryCamera: primaryCamera,
                layout: primaryCamera == .back ? .backPrimary : .frontPrimary,
                pipLayout: pipLayout,
                captureTimestamp: Date(),
                durationSec: prepared.duration,
                retakeCount: currentRetakeCount,
                deviceMultiCamSupported: canUseMultiCam,
                finalAsset: finalAsset,
                thumbnailAsset: thumbnailAsset
            )
            reviewState = WitnessCaptureReviewState(attachment: attachment, canRetake: canRetake())
            WitnessCameraAnalytics.track("witness_video_captured", parameters: ["mode": "singleVideo"])
            return
        }

        if multiCamActive {
            multiCamActive = false
            lastFallbackReason = "Video capture uses the primary camera for stability in v1."
            try await singleCamService.configure(
                position: primaryCamera == .back ? .back : .front,
                includeAudio: true
            )
            singleCamService.startRunning()
        }

        try await singleCamService.startRecording()
        isRecording = true
        recordingProgress = 0
        WitnessCameraAnalytics.track("multi_cam_failed_fallback_single", parameters: [
            "reason": "video_v1_single_cam",
            "mode": "video"
        ])

        recordTask?.cancel()
        recordTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(elapsed / maxVideoDuration, 1)
                await MainActor.run {
                    self.recordingProgress = progress
                }
                if elapsed >= maxVideoDuration {
                    try? await self.captureOrStopVideo(using: pipLayout)
                    break
                }
            }
        }
    }
}
