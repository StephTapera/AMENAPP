// BereanLensView.swift
// AMEN — Berean Island Wave 1
//
// Camera overlay: captures image → on-device Vision OCR → bereanLens_analyze callable
// → IslandCardView result.
//
// Privacy contract:
//   - Raw camera frames NEVER leave the device. Only OCR-extracted text (ocrText)
//     is sent to the backend. Image uploads via imageRef are NOT implemented here;
//     that path requires human review of retention policy + GUARDIAN pre-check pass.
//     See HUMAN BLOCKER in build-reports/berean-island/W1-privacy.md.
//
// Feature flag: AMENFeatureFlags.bereanLensEnabled
// CF callable:  bereanLens_analyze (functions/src/berean/callables.ts)
//
// Camera permission: not-determined → system prompt; denied/restricted → permission card.
// NSCameraUsageDescription MUST be set in Info.plist (added in Task 9).

import SwiftUI
import Vision
import FoundationModels
import FirebaseFunctions
import AVFoundation

// MARK: - BereanLensView

struct BereanLensView: View {

    var onDismiss: () -> Void

    @State private var capturedImage: UIImage?
    @State private var selectedMode: LensMode = .bible
    @State private var isAnalyzing = false
    @State private var resultCard: IslandCard?
    @State private var analysisError: String?
    @State private var showCamera = false
    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        switch cameraPermission {
                        case .denied, .restricted:
                            PermissionDeniedCard(onOpenSettings: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            })
                            .padding(.horizontal)

                        default:
                            LensModeRow(selected: $selectedMode, modes: availableModes)
                                .padding(.horizontal)

                            CaptureArea(
                                image: capturedImage,
                                isAnalyzing: isAnalyzing,
                                onTap: { showCamera = true }
                            )
                            .padding(.horizontal)

                            if let err = analysisError {
                                Text(err)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            if let card = resultCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Berean Lens Result")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .padding(.horizontal)

                                    IslandCardView(card: card, onAction: handleCardAction)
                                        .padding(.horizontal)
                                }
                            }

                            if capturedImage != nil && resultCard == nil && !isAnalyzing {
                                Button(action: runAnalysis) {
                                    Label("Analyze with Berean", systemImage: "sparkles")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.accentColor)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .padding(.horizontal)
                                .accessibilityLabel("Analyze image with Berean Lens in \(selectedMode.displayName) mode")
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Berean Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: onDismiss)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if capturedImage != nil {
                        Button("Retake") {
                            capturedImage = nil
                            resultCard = nil
                            analysisError = nil
                            showCamera = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            AmenCameraView { capture in
                if case .image(let img) = capture {
                    capturedImage = img
                    resultCard = nil
                    analysisError = nil
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onAppear {
            enforceModeAvailability()
            checkCameraPermission()
        }
    }

    private var youthLensRestricted: Bool {
        AMENFeatureFlags.shared.youthMode && YouthModeService.shared.isActive
    }

    private var availableModes: [LensMode] {
        youthLensRestricted ? LensMode.ocrOnlyModes : LensMode.lensSelectableModes
    }

    private func enforceModeAvailability() {
        guard !availableModes.contains(selectedMode) else { return }
        selectedMode = .bible
    }

    // MARK: - Permission

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = status
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { showCamera = true }
                }
            }
        case .authorized:
            if capturedImage == nil { showCamera = true }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Analysis

    private func runAnalysis() {
        guard let image = capturedImage, !isAnalyzing else { return }

        isAnalyzing = true
        analysisError = nil
        resultCard = nil

        Task {
            do {
                let request = try await buildLensAnalyzeRequest(image: image, mode: selectedMode)
                let card = try await withTimeout(seconds: 15) {
                    try await callLensAnalyze(request: request)
                }
                await MainActor.run {
                    resultCard = card
                    isAnalyzing = false
                }
            } catch let le as LensError {
                await MainActor.run {
                    analysisError = lensErrorMessage(le)
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    analysisError = networkErrorMessage(error)
                    isAnalyzing = false
                }
            }
        }
    }

    // MARK: - On-device OCR (Vision)

    private func extractText(from image: UIImage) async throws -> String {
        // Downscale: cap longest edge at 1536 px to reduce memory and OCR time.
        let downscaled = image.downscaled(maxEdge: 1536)
        guard let cgImage = downscaled.cgImage else { throw LensError.ocrFailed }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // If OCR finds nothing, return a synthetic stub so the callable
                // can still return a mode-appropriate card.
                continuation.resume(returning: text.isEmpty ? "[no text detected]" : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - On-device mode analysis

    private func buildLensAnalyzeRequest(image: UIImage, mode: LensMode) async throws -> LensAnalyzeRequest {
        if youthLensRestricted && !LensMode.ocrOnlyModes.contains(mode) {
            throw LensError.modeUnavailable
        }

        switch mode {
        case .bible, .sermon, .study:
            let ocrText = try await extractText(from: image)
            return LensAnalyzeRequest(mode: mode, ocrText: ocrText, derivedLabels: [:])

        case .flyer:
            let ocrText = try await extractText(from: image)
            let documentLabels = await detectFlyerDocumentLabels(from: image, ocrText: ocrText)
            let semanticLabels = await understandLocally(text: ocrText, baseLabels: documentLabels)
            return LensAnalyzeRequest(mode: mode, ocrText: ocrText, derivedLabels: semanticLabels)

        case .fellowship:
            let ocrText = try await extractText(from: image)
            let faceSummary = try await detectFacePresenceOnly(from: image)
            let semanticLabels = await understandLocally(
                text: ocrText,
                baseLabels: [
                    "peoplePresent": faceSummary.peoplePresent ? "true" : "false",
                    "peoplePresenceSource": faceSummary.peoplePresent ? "face_detection_presence_only" : "none_detected"
                ]
            )
            return LensAnalyzeRequest(mode: mode, ocrText: ocrText, derivedLabels: semanticLabels)

        case .safety:
            // DO NOT ENABLE — pending legal + Trust & Safety review (CSAM-handling exposure).
            throw LensError.modeUnavailable
        }
    }

    private func detectFlyerDocumentLabels(from image: UIImage, ocrText: String) async -> [String: String] {
        let downscaled = image.downscaled(maxEdge: 1536)
        guard let cgImage = downscaled.cgImage else {
            return flyerHeuristicLabels(ocrText: ocrText, documentDetected: false)
        }

        let documentDetected = await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let rectangles = request.results as? [VNRectangleObservation] ?? []
                continuation.resume(returning: !rectangles.isEmpty)
            }
            request.maximumObservations = 4
            request.minimumConfidence = 0.5

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
            }
        }

        return flyerHeuristicLabels(ocrText: ocrText, documentDetected: documentDetected)
    }

    private func flyerHeuristicLabels(ocrText: String, documentDetected: Bool) -> [String: String] {
        let lower = ocrText.lowercased()
        let eventTerms = ["event", "service", "worship", "conference", "meeting", "registration", "rsvp"]
        let hasEventLanguage = eventTerms.contains { lower.contains($0) }

        return [
            "documentDetected": documentDetected ? "true" : "false",
            "documentType": hasEventLanguage ? "event_flyer" : "document",
            "eventLanguagePresent": hasEventLanguage ? "true" : "false"
        ]
    }

    private func detectFacePresenceOnly(from image: UIImage) async throws -> FacePresenceSummary {
        let downscaled = image.downscaled(maxEdge: 1536)
        guard let cgImage = downscaled.cgImage else { throw LensError.ocrFailed }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNFaceObservation] ?? []
                // Local-only privacy boundary: bounding boxes are used only to derive
                // presence. No boxes, landmarks, crops, geometry, or embeddings leave.
                continuation.resume(returning: FacePresenceSummary(peoplePresent: !observations.isEmpty))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func understandLocally(text: String, baseLabels: [String: String]) async -> [String: String] {
        if #available(iOS 26.0, *) {
            let modelLabels = await FoundationLensSemanticEngine().labels(for: text)
            return baseLabels.merging(modelLabels) { current, _ in current }
        }
        return baseLabels
    }

    // MARK: - Callable

    private func callLensAnalyze(request: LensAnalyzeRequest) async throws -> IslandCard {
        let functions = Functions.functions(region: "us-central1")
        let callable = functions.httpsCallable("bereanLens_analyze")

        let result = try await callable.call(request.payload)

        guard
            let dict = result.data as? [String: Any],
            let cardDict = dict["card"] as? [String: Any],
            let cardData = try? JSONSerialization.data(withJSONObject: cardDict),
            let card = try? JSONDecoder.bereanDecoder.decode(IslandCard.self, from: cardData)
        else {
            throw LensError.invalidResponse
        }

        return card
    }

    private struct LensAnalyzeRequest: Sendable {
        let mode: LensMode
        let ocrText: String
        let derivedLabels: [String: String]

        var payload: [String: Any] {
            var body: [String: Any] = [
                "mode": mode.rawValue,
                "ocrText": ocrText,
                "packet": [
                    "intent":      BereanIntent.ask.rawValue,
                    "surface":     BereanSurface.lens.rawValue,
                    "fields":      [] as [[String: Any]],
                    "assembledAt": ISO8601DateFormatter().string(from: Date())
                ]
            ]
            if !derivedLabels.isEmpty {
                body["derivedLabels"] = derivedLabels
            }
            return body
        }
    }

    private struct FacePresenceSummary: Sendable {
        let peoplePresent: Bool
    }

    // MARK: - Timeout helper

    private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw LensError.timeout
            }
            guard let result = try await group.next() else { throw LensError.timeout }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Error messages

    private func lensErrorMessage(_ error: LensError) -> String {
        switch error {
        case .ocrFailed:         return "Couldn't read the image. Try a clearer photo."
        case .invalidResponse:   return "Berean couldn't analyze this content. Try another image."
        case .timeout:           return "The request timed out. Check your connection and try again."
        case .modeUnavailable:   return "That Lens mode is unavailable in this build."
        }
    }

    private func networkErrorMessage(_ error: Error) -> String {
        if (error as NSError).domain == NSURLErrorDomain {
            return "No internet connection. Connect and try again."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Card actions

    private func handleCardAction(_ action: IslandCardAction) {
        switch action {
        case .share:
            guard let card = resultCard else { return }
            let text = "\(card.header)\n\n\(card.body)"
            let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(av, animated: true)
            }
        default:
            break
        }
    }
}

// MARK: - LensError

private enum LensError: Error {
    case ocrFailed
    case invalidResponse
    case timeout
    case modeUnavailable
}

// MARK: - LensMode display helpers

extension LensMode {
    static let ocrOnlyModes: [LensMode] = [.bible, .sermon, .study]

    static let lensSelectableModes: [LensMode] = [.bible, .sermon, .study, .flyer, .fellowship]

    var displayName: String {
        switch self {
        case .bible:      return "Bible"
        case .sermon:     return "Sermon"
        case .flyer:      return "Flyer"
        case .study:      return "Study"
        case .safety:     return "Safety"
        case .fellowship: return "Fellowship"
        }
    }

    var systemImage: String {
        switch self {
        case .bible:      return "book"
        case .sermon:     return "mic"
        case .flyer:      return "doc.text.image"
        case .study:      return "graduationcap"
        case .safety:     return "shield"
        case .fellowship: return "person.3"
        }
    }
}

@available(iOS 26.0, *)
@Generable
private struct FoundationLensLabels {
    @Guide(description: "Up to three coarse non-biometric labels from the visible OCR text, such as church event, sermon notes, or bible study")
    var labels: [String]
}

@available(iOS 26.0, *)
private struct FoundationLensSemanticEngine {
    func labels(for text: String) async -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[no text detected]" else { return [:] }

        let model = SystemLanguageModel(useCase: .contentTagging)
        guard case .available = model.availability else { return [:] }

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: Instructions {
                    "Return only coarse, non-biometric labels for OCR text from a Berean Lens capture."
                    "Do not infer identity, age, ethnicity, health, or private attributes."
                }
            )
            let response = try await session.respond(
                to: Prompt(trimmed),
                generating: FoundationLensLabels.self
            )
            let labels = response.content.labels
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .prefix(3)
            guard !labels.isEmpty else { return [:] }
            return ["localSemanticLabels": labels.joined(separator: ",")]
        } catch {
            return [:]
        }
    }
}

// MARK: - Sub-views

private struct PermissionDeniedCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Camera Access Required")
                .font(.system(size: 17, weight: .semibold))

            Text("Berean Lens needs camera access to analyze scripture and events around you. Enable it in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct LensModeRow: View {
    @Binding var selected: LensMode
    let modes: [LensMode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selected = mode
                        }
                    } label: {
                        Label(mode.displayName, systemImage: mode.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected == mode ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundStyle(selected == mode ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.displayName) mode\(selected == mode ? ", selected" : "")")
                }
            }
        }
    }
}

private struct CaptureArea: View {
    let image: UIImage?
    let isAnalyzing: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if isAnalyzing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Analyzing…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button(action: onTap) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Tap to capture")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open camera to capture image for Berean Lens")
            }
        }
    }
}

// MARK: - UIImage downscaling

private extension UIImage {
    func downscaled(maxEdge: CGFloat) -> UIImage {
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxEdge else { return self }
        let scale = maxEdge / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - JSONDecoder helper

private extension JSONDecoder {
    static var bereanDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
