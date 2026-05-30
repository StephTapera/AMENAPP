// BereanVisualScriptureView.swift
// AMEN App — Berean Visual Scripture Intelligence (Agent 2)
//
// Camera/photo library -> OCR -> scripture context card.
// User MUST confirm before anything saves or shares.
// Journal/personal images are transient — never stored unless saved.

import SwiftUI
import PhotosUI

// MARK: - Visual Phase

private enum VisualScripturePhase {
    case capture                                    // pick or shoot a photo
    case processing                                 // OCR + Berean lookup
    case result(BereanScriptureContextCard)         // context card ready
    case noReference(String)                        // OCR text, no ref found
}

// MARK: - Main View

struct BereanVisualScriptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called when user confirms "Add to Church Notes" — passes a draft block payload.
    let onAddToChurchNotes: ((BereanScriptureContextCard) -> Void)?

    @StateObject private var service = BereanVisualScriptureService.shared

    @State private var phase: VisualScripturePhase = .capture
    @State private var selectedItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var ocrResult: BereanScriptureOCRResult?
    @State private var showShareConfirm = false
    @State private var showChurchNotesConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                switch phase {
                case .capture:
                    capturePhaseView
                case .processing:
                    processingView
                case .result(let card):
                    resultView(card: card)
                case .noReference(let rawText):
                    noReferenceView(rawText: rawText)
                }
            }
            .navigationTitle("Scan Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onChange(of: selectedItem) { _, item in
            Task { await loadAndProcess(item: item) }
        }
    }

    // MARK: - Capture Phase

    private var capturePhaseView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            VStack(spacing: 8) {
                Text("Scan Bible Text")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)

                Text("Point your camera at a Bible page, sermon slide, or quoted scripture.\nBerean will identify the passage and add context.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Privacy note
            Label("Images for personal use are processed locally and never stored automatically.", systemImage: "lock.shield")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Photo picker
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                    Text("Choose Photo")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color(red: 0.56, green: 0.40, blue: 0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Color(red: 0.56, green: 0.40, blue: 0.85))
            Text("Reading scripture…")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result (Context Card)

    private func resultView(card: BereanScriptureContextCard) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Context card
                BereanScriptureContextCardView(card: card)
                    .padding(.horizontal, 16)

                // Action buttons — confirm required before save/share
                VStack(spacing: 12) {
                    if let onAdd = onAddToChurchNotes {
                        Button {
                            showChurchNotesConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "note.text.badge.plus")
                                Text("Add to Church Notes")
                            }
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.16, green: 0.40, blue: 0.76), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog(
                            "Add to Church Notes",
                            isPresented: $showChurchNotesConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Add as Draft") {
                                onAdd(card)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("This will create a draft block in Church Notes. You can review and edit it before saving.")
                        }
                    }

                    Button {
                        phase = .capture
                        selectedItem = nil
                        ocrResult = nil
                    } label: {
                        Text("Scan Another")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - No Reference Found

    private func noReferenceView(rawText: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            Text("No Scripture Reference Found")
                .font(.custom("OpenSans-Bold", size: 20))

            Text("Berean couldn't identify a Bible reference in this image. Try a clearer photo of a Bible page or sermon slide.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !rawText.isEmpty {
                DisclosureGroup("Show extracted text") {
                    Text(rawText)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .font(.custom("OpenSans-Regular", size: 14))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }

            Button {
                phase = .capture
                selectedItem = nil
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Load & Process

    private func loadAndProcess(item: PhotosPickerItem?) async {
        guard let item else { return }
        phase = .processing

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                phase = .capture
                errorMessage = "Could not load the selected image."
                return
            }
            capturedImage = image

            let ocr = try await service.extractScripture(from: image)
            ocrResult = ocr

            guard let reference = ocr.detectedReference else {
                phase = .noReference(ocr.rawText)
                return
            }

            let version = ocr.detectedVersion ?? .unknown
            let card = try await service.fetchContextCard(for: reference, version: version)

            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                phase = .result(card)
            }

        } catch {
            phase = .capture
            errorMessage = error.localizedDescription
        }
    }
}
