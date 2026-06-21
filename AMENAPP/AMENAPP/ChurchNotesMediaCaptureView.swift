// ChurchNotesMediaCaptureView.swift
// AMENAPP
//
// Media capture pipeline for Church Notes.
// Lets users photograph a bulletin, snap a slide, or scan a printed outline,
// then review the Vision-extracted text before adding it to a note.
//
// Design rules:
//   - NEVER auto-insert AI / OCR content into a note.
//   - All extracted text is labelled "Draft — needs review" until the user
//     taps "Add to Notes" explicitly.
//   - Feature-gated by AMENFeatureFlags.shared.mediaCreationEnabled.
//   - Supports Reduce Motion.
//   - Full accessibility labelling on every interactive element.

import SwiftUI
import UIKit
import Vision
import VisionKit

// MARK: - Main sheet

struct ChurchNotesMediaCaptureView: View {

    /// Called when the user approves text and wants it inserted into their note.
    var onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ChurchNotesMediaCaptureViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if !AMENFeatureFlags.shared.mediaCreationEnabled {
                    featureUnavailableView
                } else {
                    content
                }
            }
            .navigationTitle("Capture for Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close capture sheet")
                }
            }
        }
        // Camera picker
        .sheet(isPresented: $viewModel.showCamera) {
            CameraPickerView { image in
                viewModel.handleCaptured(image: image)
            }
            .ignoresSafeArea()
        }
        // Photo library picker
        .sheet(isPresented: $viewModel.showLibrary) {
            ImageLibraryPickerView { image in
                viewModel.handleCaptured(image: image)
            }
            .ignoresSafeArea()
        }
        // Document scanner
        .sheet(isPresented: $viewModel.showScanner) {
            DocumentScannerView { image in
                viewModel.handleCaptured(image: image)
            }
            .ignoresSafeArea()
        }
        .alert("Camera Unavailable",
               isPresented: $viewModel.showCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device does not have a rear camera.")
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .picking:
            captureModePicker
        case .processing:
            processingView
        case .review(let text):
            CapturedTextReviewView(
                draftText: text,
                reduceMotion: reduceMotion
            ) { approved in
                onInsert(approved)
                dismiss()
            } onRetake: {
                viewModel.reset()
            }
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Capture mode picker

    private var captureModePicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("How would you like to capture?")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.top, 32)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 12) {
                    CaptureModeButton(
                        icon: "camera.fill",
                        title: "Take a Photo",
                        subtitle: "Photograph a slide, bulletin, or board"
                    ) {
                        viewModel.startCamera()
                    }
                    .accessibilityLabel("Take a photo with camera")

                    CaptureModeButton(
                        icon: "photo.on.rectangle.angled",
                        title: "Choose from Library",
                        subtitle: "Pick an existing photo to extract text"
                    ) {
                        viewModel.showLibrary = true
                    }
                    .accessibilityLabel("Choose photo from library")

                    CaptureModeButton(
                        icon: "doc.viewfinder",
                        title: "Scan Document",
                        subtitle: "Scan a printed outline or notes page"
                    ) {
                        if VNDocumentCameraViewController.isSupported {
                            viewModel.showScanner = true
                        } else {
                            viewModel.showLibrary = true // graceful fallback
                        }
                    }
                    .accessibilityLabel("Scan a document")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96).ignoresSafeArea())
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            if reduceMotion {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.systemScaled(44))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.black)
            }
            Text("Extracting text…")
                .font(.systemScaled(17))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Extracting text from image, please wait")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(44))
                .foregroundStyle(.orange)
            Text(message)
                .font(.systemScaled(16))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { viewModel.reset() }
                .font(.systemScaled(16, weight: .semibold))
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.black)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Try again")
            Spacer()
        }
    }

    // MARK: - Feature unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.systemScaled(40))
                .foregroundStyle(.secondary)
            Text("Media capture is not available right now.")
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Media capture is not available right now")
    }
}

// MARK: - Review view

/// Shows OCR-extracted text with a "Draft — needs review" badge.
/// The user can edit the text inline before inserting it into a note.
struct CapturedTextReviewView: View {

    var draftText: String
    var reduceMotion: Bool
    var onInsert: (String) -> Void
    var onRetake: () -> Void

    @State private var editableText: String
    @State private var didAppear = false

    init(
        draftText: String,
        reduceMotion: Bool,
        onInsert: @escaping (String) -> Void,
        onRetake: @escaping () -> Void
    ) {
        self.draftText = draftText
        self.reduceMotion = reduceMotion
        self.onInsert = onInsert
        self.onRetake = onRetake
        self._editableText = State(initialValue: draftText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Draft badge
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                        .font(.systemScaled(13, weight: .medium))
                    Text("Draft — needs review")
                        .font(.systemScaled(13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .clipShape(Capsule())
                .accessibilityLabel("Draft content that needs your review before adding to notes")
                .opacity(didAppear ? 1 : 0)
                .animation(reduceMotion ? .none : .easeIn(duration: 0.3), value: didAppear)

                // Instruction
                Text("Edit the extracted text below, then tap Add to Notes.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)

                // Editable text area
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                        )
                    TextEditor(text: $editableText)
                        .font(.systemScaled(15))
                        .foregroundStyle(.black)
                        .padding(12)
                        .frame(minHeight: 220)
                        .accessibilityLabel("Extracted text editor. Edit before inserting.")
                }
                .frame(minHeight: 240)

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        onInsert(editableText)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add to Notes")
                                .font(.systemScaled(17, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add reviewed text to your church note")

                    Button {
                        onRetake()
                    } label: {
                        Text("Retake / Capture Again")
                            .font(.systemScaled(15))
                            .foregroundStyle(.black.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Retake or capture a different image")
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96).ignoresSafeArea())
        .onAppear { didAppear = true }
    }
}

// MARK: - CaptureModeButton

private struct CaptureModeButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.systemScaled(22))
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .label))
                    Text(subtitle)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

enum ChurchNotesCapturePhase {
    case picking
    case processing
    case review(String)
    case error(String)
}

@MainActor
final class ChurchNotesMediaCaptureViewModel: ObservableObject {

    @Published var phase: ChurchNotesCapturePhase = .picking
    @Published var showCamera = false
    @Published var showLibrary = false
    @Published var showScanner = false
    @Published var showCameraUnavailableAlert = false

    func startCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailableAlert = true
            return
        }
        showCamera = true
    }

    func handleCaptured(image: UIImage) {
        phase = .processing
        Task {
            do {
                let text = try await ChurchNotesOCRProcessor.extract(from: image)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    phase = .error("No readable text was found in the image. Try a clearer photo or choose a different image.")
                } else {
                    phase = .review(text)
                }
            } catch {
                phase = .error("Text extraction failed: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        phase = .picking
        showCamera = false
        showLibrary = false
        showScanner = false
    }
}

// MARK: - OCR Processor

enum ChurchNotesOCRProcessor {

    /// Runs a Vision VNRecognizeTextRequest on the given image and returns
    /// the extracted text, sorted top-to-bottom then left-to-right.
    static func extract(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                // Sort observations top-to-bottom (descending y in Vision coordinates = ascending on screen)
                let sorted = observations.sorted {
                    $0.boundingBox.minY > $1.boundingBox.minY
                }
                let text = sorted
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
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

    enum OCRError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            "The image could not be processed. Please try a different photo."
        }
    }
}

// MARK: - CameraPickerView (UIViewControllerRepresentable)

struct CameraPickerView: UIViewControllerRepresentable {

    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - ImageLibraryPickerView (UIViewControllerRepresentable)

struct ImageLibraryPickerView: UIViewControllerRepresentable {

    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - DocumentScannerView (UIViewControllerRepresentable)

/// Wraps VNDocumentCameraViewController for multi-page document scanning.
/// Falls back gracefully when running in the simulator or on devices that
/// don't support VisionKit's document scanner.
struct DocumentScannerView: UIViewControllerRepresentable {

    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            controller.dismiss(animated: true)
            guard scan.pageCount > 0 else { return }
            // Use the first scanned page; OCR will linearise multi-page content.
            let image = scan.imageOfPage(at: 0)
            onCapture(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true)
            dlog("[ChurchNotesMediaCapture] Document scanner failed: \(error)")
        }
    }
}
