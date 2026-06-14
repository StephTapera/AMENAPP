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
                            LensModeRow(selected: $selectedMode)
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
            checkCameraPermission()
        }
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
                let ocrText = try await extractText(from: image)
                let card = try await withTimeout(seconds: 15) {
                    try await callLensAnalyze(ocrText: ocrText, mode: selectedMode)
                }
                await MainActor.run {
                    resultCard = card
                    isAnalyzing = false
                }
            } catch is LensError {
                await MainActor.run {
                    analysisError = lensErrorMessage(error as! LensError)
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

    // MARK: - Callable

    private func callLensAnalyze(ocrText: String, mode: LensMode) async throws -> IslandCard {
        let functions = Functions.functions(region: "us-central1")
        let callable = functions.httpsCallable("bereanLens_analyze")

        let payload: [String: Any] = [
            "mode":    mode.rawValue,
            "ocrText": ocrText,
            "packet": [
                "intent":      BereanIntent.ask.rawValue,
                "surface":     BereanSurface.lens.rawValue,
                "fields":      [] as [[String: Any]],
                "assembledAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]

        let result = try await callable.call(payload)

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
}

// MARK: - LensMode display helpers

extension LensMode {
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LensMode.allCases, id: \.self) { mode in
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
