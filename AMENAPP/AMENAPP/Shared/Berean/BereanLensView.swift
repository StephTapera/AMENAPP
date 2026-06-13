// BereanLensView.swift
// AMEN — Berean Island Wave 1
//
// Camera overlay that captures an image, routes it through the
// `bereanLens_analyze` callable, and displays the result as an IslandCardView.
//
// Feature flag: AMENFeatureFlags.bereanLensEnabled
// CF callable:  bereanLens_analyze (stub in functions/src/berean/callables.ts)

import SwiftUI
import FirebaseFunctions

// MARK: - BereanLensView

struct BereanLensView: View {

    var onDismiss: () -> Void

    @State private var capturedImage: UIImage?
    @State private var selectedMode: LensMode = .bible
    @State private var isAnalyzing = false
    @State private var resultCard: IslandCard?
    @State private var analysisError: String?
    @State private var showCamera = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Lens mode picker
                        LensModeRow(selected: $selectedMode)
                            .padding(.horizontal)

                        // Capture area
                        CaptureArea(
                            image: capturedImage,
                            isAnalyzing: isAnalyzing,
                            onTap: { showCamera = true }
                        )
                        .padding(.horizontal)

                        // Error
                        if let err = analysisError {
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Result card
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

                        // Analyze CTA
                        if capturedImage != nil && resultCard == nil {
                            Button(action: runAnalysis) {
                                Label("Analyze with Berean", systemImage: "sparkles")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isAnalyzing)
                            .padding(.horizontal)
                            .accessibilityLabel("Analyze image with Berean Lens in \(selectedMode.displayName) mode")
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
            if capturedImage == nil { showCamera = true }
        }
    }

    // MARK: - Analysis

    private func runAnalysis() {
        guard let image = capturedImage else { return }
        guard !isAnalyzing else { return }

        isAnalyzing = true
        analysisError = nil
        resultCard = nil

        Task {
            do {
                let card = try await analyzeLens(image: image, mode: selectedMode)
                await MainActor.run {
                    resultCard = card
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    analysisError = lensErrorMessage(error)
                    isAnalyzing = false
                }
            }
        }
    }

    private func analyzeLens(image: UIImage, mode: LensMode) async throws -> IslandCard {
        guard let jpegData = image.jpegData(compressionQuality: 0.75) else {
            throw LensError.imageEncodingFailed
        }

        let base64 = jpegData.base64EncodedString()
        let functions = Functions.functions(region: "us-central1")
        let callable = functions.httpsCallable("bereanLens_analyze")

        let packet = ContextPacket(
            intent: .ask,
            surface: .lens,
            fields: [],
            assembledAt: Date()
        )

        let payload: [String: Any] = [
            "mode":     mode.rawValue,
            "imageB64": base64,
            "packet":   [
                "intent":      packet.intent.rawValue,
                "surface":     packet.surface.rawValue,
                "fields":      [] as [[String: Any]],
                "assembledAt": ISO8601DateFormatter().string(from: packet.assembledAt)
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

    private func lensErrorMessage(_ error: Error) -> String {
        if let le = error as? LensError {
            switch le {
            case .imageEncodingFailed: return "Couldn't encode the image. Please try again."
            case .invalidResponse:     return "Berean couldn't read this image. Try a clearer photo."
            }
        }
        return "Something went wrong. Please try again."
    }

    private func handleCardAction(_ action: IslandCardAction) {
        // Route standard card actions; more can be wired here as needed.
        switch action {
        case .save:
            // Saving is handled by the caller / BereanMemoryService
            break
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

// MARK: - LensMode helpers

extension LensMode {
    var displayName: String {
        switch self {
        case .bible:       return "Bible"
        case .sermon:      return "Sermon"
        case .flyer:       return "Flyer"
        case .study:       return "Study"
        case .safety:      return "Safety"
        case .fellowship:  return "Fellowship"
        }
    }

    var systemImage: String {
        switch self {
        case .bible:       return "book"
        case .sermon:      return "mic"
        case .flyer:       return "doc.text.image"
        case .study:       return "graduationcap"
        case .safety:      return "shield"
        case .fellowship:  return "person.3"
        }
    }
}

// MARK: - Lens Error

private enum LensError: Error {
    case imageEncodingFailed
    case invalidResponse
}

// MARK: - Sub-views

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
                .accessibilityLabel("Open camera")
            }
        }
    }
}

// MARK: - JSON decoder

private extension JSONDecoder {
    static var bereanDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
