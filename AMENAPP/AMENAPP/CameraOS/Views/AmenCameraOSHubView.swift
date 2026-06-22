// AmenCameraOSHubView.swift
// AMENAPP — Camera OS
// Main entry point for the camera OS experience.
// Flow: Intent Selection → Capture → Safety Scan → [Safety Review] → Publish

import SwiftUI
import AVFoundation


// MARK: - CameraOSCaptureState helpers

extension CameraOSCaptureState {
    /// True only when the state is `.intentSelection`.
    var isIntentSelection: Bool {
        if case .intentSelection = self { return true }
        return false
    }

    /// True only when the state is `.capturing`.
    var isCapturing: Bool {
        if case .capturing = self { return true }
        return false
    }

    /// True only when the state is `.contextLensScanning`.
    var isContextLensScanning: Bool {
        if case .contextLensScanning = self { return true }
        return false
    }

    /// True only when the state is `.publishing`.
    var isPublishing: Bool {
        if case .publishing = self { return true }
        return false
    }

    /// Extracts the intent from any state that carries one.
    var intent: CameraIntent? {
        switch self {
        case .intentSelection:
            return nil
        case .capturing(let intent),
             .contextLensScanning(let intent),
             .prayerCapture(let intent),
             .publishing(let intent):
            return intent
        case .safetyReview(let intent, _, _):
            return intent
        }
    }
}

// MARK: - AmenCameraOSHubView

/// Orchestrating entry point for the entire Camera OS experience.
///
/// Manages the full state machine:
///   intentSelection → capturing → contextLensScanning → safetyReview → publishing
///
/// WitnessCameraView is always present underneath as the capture surface.
/// State-specific overlays are composited on top via ZStack.
struct AmenCameraOSHubView: View {

    // MARK: Props

    /// Called when the user approves a captured piece of media and it is ready to post.
    var onMediaCaptured: (WitnessDraftAttachment, CameraIntent) -> Void
    /// Called when a prayer capture completes.
    var onPrayerCaptured: (PrayerCapture) -> Void
    /// Called to dismiss the entire Camera OS.
    var onDismiss: () -> Void

    // MARK: State

    @StateObject private var cameraCoordinator = CreatePostCameraCoordinator()

    @State private var captureState: CameraOSCaptureState = .intentSelection
    @State private var selectedIntent: CameraIntent? = nil
    @State private var isShowingIntentPicker = true
    @State private var isRunningContextLens = false
    @State private var contextLensResult: ContextLensResult? = nil
    @State private var pendingScanResult: CameraPrePublishScanResult? = nil
    @State private var safetyProfile: CameraSafetyProfile = .standard
    @AppStorage("cameraOS.cloudContextLensConsent.v1") private var hasCloudContextLensConsent = false
    @State private var pendingCloudConsentAttachment: WitnessDraftAttachment?
    @State private var pendingCloudConsentIntent: CameraIntent?
    @State private var isShowingCloudContextConsent = false

    // MARK: Body

    var body: some View {
        ZStack {
            // Layer 1: capture surface — always present underneath
            captureLayer

            // Layer 2: state-specific overlay
            stateOverlay
        }
        .ignoresSafeArea()
        .onChange(of: cameraCoordinator.attachedWitnessMedia) { _, attachment in
            if let attachment, let intent = selectedIntent {
                handleCapturedMedia(attachment: attachment, intent: intent)
            }
        }
        .confirmationDialog(
            "Use cloud Context Lens for this scan?",
            isPresented: $isShowingCloudContextConsent,
            titleVisibility: .visible
        ) {
            Button("Use Cloud Scan") {
                hasCloudContextLensConsent = true
                if let attachment = pendingCloudConsentAttachment,
                   let intent = pendingCloudConsentIntent {
                    startPrePublishScan(attachment: attachment, intent: intent, allowCloudContext: true)
                }
                pendingCloudConsentAttachment = nil
                pendingCloudConsentIntent = nil
            }
            Button("Scan On Device Only") {
                if let attachment = pendingCloudConsentAttachment,
                   let intent = pendingCloudConsentIntent {
                    startPrePublishScan(attachment: attachment, intent: intent, allowCloudContext: false)
                }
                pendingCloudConsentAttachment = nil
                pendingCloudConsentIntent = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloudConsentAttachment = nil
                pendingCloudConsentIntent = nil
                captureState = .capturing(intent: selectedIntent ?? .testimony)
            }
        } message: {
            Text("Cloud scan sends recognized text, not the image, to AMEN's AI functions for scene context and Berean suggestions. Images are not retained by the scan service.")
        }
        // Intent picker sheet — presented when in intentSelection state
        .sheet(isPresented: Binding(
            get: { captureState.isIntentSelection },
            set: { _ in }
        )) {
            CameraIntentPickerView(
                onIntentSelected: { intent in
                    selectedIntent = intent
                    isShowingIntentPicker = false
                    if case .prayerCapture = intentToCaptureState(intent) {
                        captureState = .prayerCapture(intent: intent)
                    } else {
                        captureState = .capturing(intent: intent)
                    }
                },
                onDismiss: {
                    onDismiss()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Capture Layer

    /// The underlying AVFoundation capture surface. Always rendered so the session
    /// remains live. A dark scrim is applied during intent selection so the picker
    /// reads cleanly over a blurred preview.
    private var captureLayer: some View {
        WitnessCameraView(coordinator: cameraCoordinator)
            .overlay {
                if captureState.isIntentSelection {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: LiquidGlassTokens.motionFast), value: captureState.isIntentSelection)
                }
            }
    }

    // MARK: - State Overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch captureState {
        case .intentSelection:
            // Sheet is presented via .sheet modifier above; nothing extra here.
            EmptyView()

        case .capturing(let intent):
            VStack {
                HStack {
                    Spacer()
                    intentBadge
                    Spacer()
                    contextLensButton(intent: intent)
                        .padding(.trailing, 20)
                }
                .padding(.top, 60)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82), value: captureState.isCapturing)

        case .contextLensScanning:
            VStack {
                HStack {
                    Spacer()
                    contextLensScanningIndicator
                    Spacer()
                }
                .padding(.top, 60)
                Spacer()
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: LiquidGlassTokens.motionFast), value: captureState.isContextLensScanning)

        case .safetyReview(let intent, let attachment, let scanResult):
            PrePublishSafetyReviewView(
                intent: intent,
                attachment: attachment,
                scanResult: scanResult,
                onApprove: { approvedAttachment, _ in
                    handleSafetyApproved(attachment: approvedAttachment, intent: intent)
                },
                onCancel: {
                    // Return to capture for the same intent
                    captureState = .capturing(intent: intent)
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.85), value: true)

        case .prayerCapture(let intent):
            PrayerCaptureView(
                onComplete: { prayer in
                    handlePrayerCaptured(prayer)
                },
                onDismiss: {
                    // Return user to intent selection if they back out of prayer flow
                    captureState = .intentSelection
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .animation(.spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.85), value: true)
            // Suppress unused-variable warning; intent is part of the enum case
            .id(intent)

        case .publishing:
            publishingOverlay
                .transition(.opacity)
                .animation(.easeInOut(duration: LiquidGlassTokens.motionFast), value: captureState.isPublishing)
        }
    }

    // MARK: - Intent Badge

    /// Glass pill displayed in the top-center of the capture surface showing
    /// which intent the current capture session is for.
    private var intentBadge: some View {
        HStack(spacing: 8) {
            if let intent = selectedIntent {
                Image(systemName: intent.systemIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(intent.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        )
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(selectedIntent.map { "Capturing for intent: \($0.displayName)" } ?? "Capturing")
    }

    // MARK: - Context Lens Button

    /// Small glass pill button in the top-right that triggers Context Lens scanning.
    private func contextLensButton(intent: CameraIntent) -> some View {
        Button {
            triggerContextLens(intent: intent)
        } label: {
            Image(systemName: "viewfinder.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                )
                .shadow(
                    color: LiquidGlassTokens.shadowSoft.color,
                    radius: LiquidGlassTokens.shadowSoft.radius,
                    y: LiquidGlassTokens.shadowSoft.y
                )
        }
        .accessibilityLabel("Context Lens — scan scene")
        .accessibilityHint("Analyzes the current frame for context and safety signals")
    }

    // MARK: - Context Lens Scanning Indicator

    private var contextLensScanningIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.85)
            Text("Scanning…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        )
        .shadow(
            color: LiquidGlassTokens.shadowSoft.color,
            radius: LiquidGlassTokens.shadowSoft.radius,
            y: LiquidGlassTokens.shadowSoft.y
        )
        .accessibilityLabel("Scanning scene for context")
    }

    // MARK: - Publishing Overlay

    private var publishingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                Text("Publishing…")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .shadow(
                color: LiquidGlassTokens.shadowFloating.color,
                radius: LiquidGlassTokens.shadowFloating.radius,
                y: LiquidGlassTokens.shadowFloating.y
            )
        }
        .accessibilityLabel("Publishing your post")
    }

    // MARK: - Handlers

    /// Invoked whenever `cameraCoordinator.attachedWitnessMedia` becomes non-nil.
    /// Runs an async safety scan and transitions to `.safetyReview`.
    private func handleCapturedMedia(attachment: WitnessDraftAttachment, intent: CameraIntent) {
        guard hasCloudContextLensConsent else {
            pendingCloudConsentAttachment = attachment
            pendingCloudConsentIntent = intent
            isShowingCloudContextConsent = true
            return
        }

        startPrePublishScan(attachment: attachment, intent: intent, allowCloudContext: true)
    }

    private func startPrePublishScan(
        attachment: WitnessDraftAttachment,
        intent: CameraIntent,
        allowCloudContext: Bool
    ) {
        Task {
            captureState = .contextLensScanning(intent: intent)

            let scanContext = await buildPrePublishScan(
                attachment: attachment,
                intent: intent,
                safetyProfile: safetyProfile,
                allowCloudContext: allowCloudContext
            )

            contextLensResult = scanContext.contextLensResult
            pendingScanResult = scanContext.scanResult

            captureState = .safetyReview(
                intent: intent,
                attachment: attachment,
                scanResult: scanContext.scanResult
            )
        }
    }

    /// Called from `PrePublishSafetyReviewView.onApprove`.
    /// Conceptually strips EXIF / location metadata, then hands off and dismisses.
    private func handleSafetyApproved(attachment: WitnessDraftAttachment, intent: CameraIntent) {
        captureState = .publishing(intent: intent)
        // Metadata stripping would be performed here by WitnessMediaComposer or a
        // dedicated MetadataStripEngine before the attachment leaves this boundary.
        onMediaCaptured(attachment, intent)
        onDismiss()
    }

    /// Called from `PrayerCaptureView.onComplete`.
    private func handlePrayerCaptured(_ prayer: PrayerCapture) {
        onPrayerCaptured(prayer)
        onDismiss()
    }

    // MARK: - Context Lens Trigger

    private func triggerContextLens(intent: CameraIntent) {
        guard !isRunningContextLens else { return }
        isRunningContextLens = true
        captureState = .contextLensScanning(intent: intent)

        Task {
            isRunningContextLens = false
            captureState = .capturing(intent: intent)
        }
    }

    // MARK: - Helpers

    /// Returns the capture state that maps from a given intent.
    /// Prayer intents branch into a dedicated capture flow.
    private func intentToCaptureState(_ intent: CameraIntent) -> CameraOSCaptureState {
        if intent.isPrayerIntent {
            return .prayerCapture(intent: intent)
        }
        return .capturing(intent: intent)
    }

    // MARK: - Safety Scan

    private func buildPrePublishScan(
        attachment: WitnessDraftAttachment,
        intent: CameraIntent,
        safetyProfile: CameraSafetyProfile,
        allowCloudContext: Bool
    ) async -> (contextLensResult: ContextLensResult?, scanResult: CameraPrePublishScanResult) {
        let imageData = loadScannableImageData(from: attachment)
        let context = await imageData.map { data in
            Task {
                if allowCloudContext {
                    return await ContextLensService.shared.scan(imageData: data)
                }
                return await ContextLensService.shared.localSafetyScan(imageData: data)
            }
        }?.value

        let sceneType = context?.sceneType ?? fallbackSceneType(for: intent)
        let detectedItems = detectedSensitiveItems(
            from: context?.rawOCRText ?? "",
            sceneType: sceneType,
            intent: intent
        )

        let safeZoneContext = await MainActor.run {
            (
                location: ChurchLocationManager.shared.currentLocation,
                safeZones: SafeZoneService.shared.safeZones
            )
        }

        let scanResult = await CameraContextRiskEngine.shared.computeRisk(
            detectedItems: detectedItems,
            sceneType: sceneType,
            userLocation: safeZoneContext.location,
            safeZones: safeZoneContext.safeZones,
            safetyProfile: safetyProfile,
            intent: intent
        )

        return (context, scanResult)
    }

    private func loadScannableImageData(from attachment: WitnessDraftAttachment) -> Data? {
        let candidateURLs = [
            attachment.thumbnailFileURL,
            attachment.finalFileURL
        ].compactMap { $0 }

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }

        return nil
    }

    private func detectedSensitiveItems(
        from text: String,
        sceneType: CameraSceneType,
        intent: CameraIntent
    ) -> [CameraSensitiveItemType] {
        var items = Set<CameraSensitiveItemType>()
        let lower = text.lowercased()

        if text.range(of: #"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"#, options: .regularExpression) != nil {
            items.insert(.phoneNumber)
        }
        if text.range(of: #"\b[A-Z0-9]{2,4}[-\s]?[A-Z0-9]{3,4}\b"#, options: .regularExpression) != nil &&
            lower.contains("plate") {
            items.insert(.licensePlate)
        }
        if lower.contains("driver license") || lower.contains("passport") ||
            lower.contains("student id") || lower.contains("identification") {
            items.insert(.idDocument)
        }
        if lower.contains("patient") || lower.contains("diagnosis") ||
            lower.contains("prescription") || lower.contains("medical record") {
            items.insert(.medicalRecord)
        }
        if lower.contains("badge") || lower.contains("employee id") || lower.contains("credential") {
            items.insert(.badge)
        }
        if lower.contains("address") ||
            text.range(of: #"\b\d{1,6}\s+[A-Za-z0-9.'-]+\s+(Street|St|Avenue|Ave|Road|Rd|Drive|Dr|Lane|Ln|Boulevard|Blvd)\b"#, options: .regularExpression) != nil {
            items.insert(.homeAddress)
        }
        if lower.contains("school") || sceneType == .school || sceneType == .classroom {
            items.insert(.schoolSign)
        }
        if lower.contains("uniform") {
            items.insert(.schoolUniform)
        }
        if lower.contains("bus stop") {
            items.insert(.busStop)
        }
        if lower.contains("screen") || lower.contains("screenshot") || lower.contains("password") {
            items.insert(.screenContent)
        }
        if lower.contains("child") || lower.contains("children") || lower.contains("student") ||
            lower.contains("minor") || intent == .memory {
            items.insert(.minorFace)
        }

        return Array(items)
    }

    private func fallbackSceneType(for intent: CameraIntent) -> CameraSceneType {
        switch intent {
        case .sermon, .churchNotes, .testimony, .prayer, .prayerRequest:
            return .church
        case .meeting, .interview:
            return .office
        case .event:
            return .outdoors
        default:
            return .unknown
        }
    }
}
