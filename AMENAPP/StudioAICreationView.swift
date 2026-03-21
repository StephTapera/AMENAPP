//
//  StudioAICreationView.swift
//  AMENAPP
//
//  Unified AI creation interface for AMEN Studio.
//  Handles: Testimony Builder, Prayer Composer, Devotional Writer,
//           Scripture Canvas caption, Sermon Prep, Weekly Challenge.
//
//  Flow: select tool → fill form → AI generates → edit → publish/export/save draft
//

import Combine
import FirebaseAuth
import FirebaseDatabase
import SwiftData
import SwiftUI
import FirebaseFunctions

// MARK: - Tool Enum

enum StudioTool: String, CaseIterable, Identifiable {
    case testimony
    case prayer
    case devotional
    case sermonPrep     = "sermon_prep"
    case scriptureCanvas = "scripture_canvas"
    case challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .testimony:       return "Testimony Builder"
        case .prayer:          return "Prayer Composer"
        case .devotional:      return "Devotional Writer"
        case .sermonPrep:      return "Sermon Prep"
        case .scriptureCanvas: return "Scripture Canvas"
        case .challenge:       return "Weekly Challenge"
        }
    }

    var icon: String {
        switch self {
        case .testimony:       return "quote.bubble.fill"
        case .prayer:          return "hands.sparkles.fill"
        case .devotional:      return "book.fill"
        case .sermonPrep:      return "mic.fill"
        case .scriptureCanvas: return "paintbrush.pointed.fill"
        case .challenge:       return "trophy.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .testimony:       return .blue
        case .prayer:          return .purple
        case .devotional:      return .teal
        case .sermonPrep:      return .orange
        case .scriptureCanvas: return .pink
        case .challenge:       return .yellow
        }
    }

    var promptHint: String {
        switch self {
        case .testimony:
            return "What has God done in your life? Share a moment of grace, healing, or transformation."
        case .prayer:
            return "What's on your heart? Write a prayer for yourself, someone else, or the world."
        case .devotional:
            return "Start with a scripture or theme. AI will shape it into a devotional reflection."
        case .sermonPrep:
            return "Enter a scripture passage or sermon topic. AI will outline a message framework."
        case .scriptureCanvas:
            return "Type a verse or theme. AI will craft a caption or visual meditation."
        case .challenge:
            return "This week's challenge: Write your testimony in 100 words. Begin below."
        }
    }

    var outputLabel: String {
        switch self {
        case .testimony:       return "Your Testimony"
        case .prayer:          return "Your Prayer"
        case .devotional:      return "Devotional"
        case .sermonPrep:      return "Sermon Outline"
        case .scriptureCanvas: return "Scripture Caption"
        case .challenge:       return "Your Entry"
        }
    }
}

// MARK: - View Model

@MainActor
final class StudioAICreationViewModel: ObservableObject {
    @Published var userInput: String = ""
    @Published var scriptureRef: String = ""
    @Published var tone: String = "reflective"
    @Published var generatedText: String = ""
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published var phase: Phase = .compose

    // Image generation (Day 9)
    @Published var generatedImageURL: URL? = nil
    @Published var isGeneratingImage: Bool = false
    @Published var imageError: String? = nil

    enum Phase { case compose, result }

    private let functions = Functions.functions(region: "us-central1")
    private let subscriptionService = StudioSubscriptionService.shared

    func generate(tool: StudioTool) {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        generatedText = ""
        phase = .result

        Task {
            defer { isGenerating = false }
            do {
                let payload: [String: Any] = [
                    "tool": tool.rawValue,
                    "user_input": userInput,
                    "scripture_ref": scriptureRef,
                    "tone": tone
                ]
                let result = try await functions
                    .httpsCallable("studioGenerateContent")
                    .safeCall(payload)
                if let data = result.data as? [String: Any],
                   let text = data["generated_text"] as? String {
                    generatedText = text
                    subscriptionService.recordCreate()
                } else {
                    errorMessage = "Couldn't read the response. Please try again."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reset() {
        userInput = ""
        scriptureRef = ""
        generatedText = ""
        errorMessage = nil
        isGenerating = false
        phase = .compose
        generatedImageURL = nil
        imageError = nil
    }

    func generateImage(prompt: String, style: String = "painterly") {
        guard !isGeneratingImage else { return }
        isGeneratingImage = true
        imageError = nil
        Task {
            defer { isGeneratingImage = false }
            do {
                let payload: [String: Any] = ["prompt": prompt, "style": style]
                let result = try await functions
                    .httpsCallable("generateStudioImage")
                    .safeCall(payload)
                if let data = result.data as? [String: Any],
                   let urlString = data["downloadURL"] as? String,
                   let url = URL(string: urlString) {
                    generatedImageURL = url
                } else {
                    imageError = "Couldn't load the generated image."
                }
            } catch {
                imageError = error.localizedDescription
            }
        }
    }
}

// MARK: - Main View

struct StudioAICreationView: View {
    let initialTool: StudioTool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = StudioAICreationViewModel()
    @State private var selectedTool: StudioTool
    private let sessionID = UUID().uuidString
    @State private var showShareSheet = false
    @State private var exportImage: UIImage?
    @State private var showImageShareSheet = false
    @State private var isExporting = false
    @State private var pdfExportURL: URL?
    @State private var showPDFShareSheet = false
    @State private var isExportingPDF = false
    @FocusState private var inputFocused: Bool
    @State private var autoSaveTimer: Timer?

    init(initialTool: StudioTool) {
        self.initialTool = initialTool
        _selectedTool = State(initialValue: initialTool)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        toolPickerHeader
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        if vm.phase == .compose {
                            composeSection
                                .transition(.opacity)
                        } else {
                            resultSection
                                .transition(.opacity)
                        }

                        Color.clear.frame(height: 100)
                    }
                }

                if vm.phase == .compose {
                    generateBar
                        .background(.ultraThinMaterial)
                }
            }
            .navigationBarHidden(true)
            .animation(.easeInOut(duration: 0.2), value: vm.phase)
            .onAppear { startAutoSaveTimer() }
            .onDisappear {
                autoSaveTimer?.invalidate()
                saveDraft()
                // Remove in-progress RTDB session on close
                if let uid = Auth.auth().currentUser?.uid {
                    Database.database().reference()
                        .child("studioSessions").child(uid).child(sessionID)
                        .removeValue()
                }
            }
        }
    }

    // MARK: - Auto-save

    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in saveDraft() }
        }
    }

    // MARK: - RTDB Sync (Day 12)

    private func syncToRTDB() {
        guard let uid = Auth.auth().currentUser?.uid,
              !vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let ref = Database.database().reference()
            .child("studioSessions").child(uid).child(sessionID)
        ref.setValue([
            "tool": selectedTool.rawValue,
            "userInput": vm.userInput,
            "scriptureRef": vm.scriptureRef,
            "tone": vm.tone,
            "generatedText": vm.generatedText,
            "updatedAt": ServerValue.timestamp(),
        ])
    }

    private func saveDraft() {
        guard !vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Also sync to RTDB so other devices can see the in-progress session
        syncToRTDB()

        let draft = StudioDraft(
            tool: selectedTool.rawValue,
            userInput: vm.userInput,
            scriptureRef: vm.scriptureRef,
            tone: vm.tone,
            generatedText: vm.generatedText
        )
        modelContext.insert(draft)

        // Prune to last 5 drafts for this tool
        let toolValue = selectedTool.rawValue
        let descriptor = FetchDescriptor<StudioDraft>(
            predicate: #Predicate { $0.tool == toolValue },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        if let allDrafts = try? modelContext.fetch(descriptor), allDrafts.count > 5 {
            allDrafts.dropFirst(5).forEach { modelContext.delete($0) }
        }

        try? modelContext.save()
    }

    // MARK: - Image Export (Day 11)

    private func exportAsImage() async {
        guard !vm.generatedText.isEmpty else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let image = try await StudioExportService.renderForSharing(
                text: vm.generatedText,
                tool: selectedTool,
                title: selectedTool.outputLabel
            )
            exportImage = image
            showImageShareSheet = true
        } catch {
            // Non-fatal — swallow silently; the Share button still works as fallback
        }
    }

    private func exportAsPDF() async {
        guard !vm.generatedText.isEmpty else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }
        do {
            let functions = Functions.functions(region: "us-central1")
            let payload: [String: Any] = [
                "content": vm.generatedText,
                "tool": selectedTool.rawValue,
                "title": selectedTool.outputLabel,
            ]
            let result = try await functions
                .httpsCallable("exportToPDF")
                .safeCall(payload)
            if let data = result.data as? [String: Any],
               let urlString = data["url"] as? String ?? (data["downloadURL"] as? String),
               let url = URL(string: urlString) {
                pdfExportURL = url
                showPDFShareSheet = true
            }
        } catch {
            // Non-fatal — share text fallback is still available
        }
    }

    // MARK: - Tool Picker Header

    private var toolPickerHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("AMEN Studio")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                // Balance button
                Color.clear.frame(width: 33, height: 33)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StudioTool.allCases.filter { $0 != .challenge }) { tool in
                        toolChip(tool)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func toolChip(_ tool: StudioTool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTool = tool
                vm.reset()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tool.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selectedTool == tool ? tool.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        Capsule().strokeBorder(
                            selectedTool == tool ? tool.accentColor.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                    )
            )
            .foregroundStyle(selectedTool == tool ? tool.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compose Section

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tool header card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedTool.accentColor.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: selectedTool.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(selectedTool.accentColor)
                    }
                    Text(selectedTool.title)
                        .font(.system(size: 18, weight: .bold))
                }
                Text(selectedTool.promptHint)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selectedTool.accentColor.opacity(0.1), lineWidth: 1)
                    )
            )

            // Main text input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your Thoughts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let uid = Auth.auth().currentUser?.uid {
                        StudioVoiceButton(uid: uid, accentColor: selectedTool.accentColor) { transcript in
                            if vm.userInput.isEmpty {
                                vm.userInput = transcript
                            } else {
                                vm.userInput += " " + transcript
                            }
                        }
                    }
                }
                TextEditor(text: $vm.userInput)
                    .focused($inputFocused)
                    .frame(minHeight: 140)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(alignment: .topLeading) {
                        if vm.userInput.isEmpty {
                            Text("Start writing here…")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(.placeholderText))
                                .padding(.top, 19)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    }
            }

            // Optional scripture reference
            if selectedTool == .devotional || selectedTool == .sermonPrep || selectedTool == .scriptureCanvas {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scripture Reference (optional)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. John 3:16, Psalm 23", text: $vm.scriptureRef)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }

            // Tone picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Tone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["reflective", "hopeful", "bold", "gentle", "celebratory"], id: \.self) { t in
                            Button { vm.tone = t } label: {
                                Text(t.capitalized)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(vm.tone == t ? selectedTool.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                                            .overlay(
                                                Capsule().strokeBorder(
                                                    vm.tone == t ? selectedTool.accentColor.opacity(0.4) : Color.clear,
                                                    lineWidth: 1
                                                )
                                            )
                                    )
                                    .foregroundStyle(vm.tone == t ? selectedTool.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Result Section

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Back + tool label
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.phase = .compose }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Edit")
                    }
                    .foregroundStyle(selectedTool.accentColor)
                    .font(.system(size: 14))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(selectedTool.outputLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            if vm.isGenerating {
                generatingPlaceholder
            } else if let err = vm.errorMessage {
                ErrorCard(message: err) { vm.generate(tool: selectedTool) }
                    .padding(.horizontal, 20)
            } else {
                // Editable result
                TextEditor(text: $vm.generatedText)
                    .frame(minHeight: 240)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(selectedTool.accentColor.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                // Image generation panel (Scripture Canvas only)
                if selectedTool == .scriptureCanvas {
                    StudioImageGenerationPanel(vm: vm, accentColor: selectedTool.accentColor)
                        .padding(.horizontal, 20)
                }

                // Action row
                HStack(spacing: 12) {
                    Button {
                        vm.generate(tool: selectedTool)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selectedTool.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selectedTool.accentColor.opacity(0.1))
                                    .overlay(Capsule().strokeBorder(selectedTool.accentColor.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = vm.generatedText
                        HapticManager.impact(style: .light)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(selectedTool.accentColor))
                    }
                    .buttonStyle(.plain)

                    // Export as image (on-device)
                    Button {
                        Task { await exportAsImage() }
                    } label: {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(selectedTool.accentColor)
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(selectedTool.accentColor)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)

                    // Export as PDF (cloud)
                    Button {
                        Task { await exportAsPDF() }
                    } label: {
                        if isExportingPDF {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(selectedTool.accentColor)
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(selectedTool.accentColor)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExportingPDF)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [vm.generatedText])
        }
        .sheet(isPresented: $showImageShareSheet) {
            if let img = exportImage {
                ShareSheet(items: [img])
            }
        }
        .sheet(isPresented: $showPDFShareSheet) {
            if let url = pdfExportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var generatingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(selectedTool.accentColor)
            Text("Crafting your \(selectedTool.outputLabel.lowercased())…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Generate Bar

    private var generateBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                inputFocused = false
                vm.generate(tool: selectedTool)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Generate")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(
                        vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(.tertiarySystemBackground)
                        : selectedTool.accentColor
                    )
                )
                .foregroundStyle(
                    vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Color(.placeholderText)
                    : .white
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isGenerating)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Image Generation Panel (Day 9 — Scripture Canvas)

private struct StudioImageGenerationPanel: View {
    @ObservedObject var vm: StudioAICreationViewModel
    let accentColor: Color

    private let styleOptions = ["painterly", "realistic", "illustration", "watercolor", "sketch"]
    @State private var selectedStyle = "painterly"
    @State private var showImageShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
                Text("Generate Image")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
                Spacer()
            }

            // Style picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(styleOptions, id: \.self) { style in
                        Button { selectedStyle = style } label: {
                            Text(style.capitalized)
                                .font(.system(size: 12))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selectedStyle == style ? accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                                        .overlay(Capsule().strokeBorder(
                                            selectedStyle == style ? accentColor.opacity(0.4) : Color.clear,
                                            lineWidth: 1))
                                )
                                .foregroundStyle(selectedStyle == style ? accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Generated image or generate button
            if let imageURL = vm.generatedImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    showImageShare = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(.ultraThinMaterial))
                                }
                                .buttonStyle(.plain)
                                .padding(10)
                            }
                    case .failure:
                        Label("Image failed to load", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
                .sheet(isPresented: $showImageShare) {
                    ShareSheet(items: [imageURL])
                }
            } else if vm.isGeneratingImage {
                HStack(spacing: 10) {
                    ProgressView().progressViewStyle(.circular).tint(accentColor).scaleEffect(0.8)
                    Text("Generating image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 60)
            } else {
                if let err = vm.imageError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 4)
                }
                Button {
                    let prompt = vm.scriptureRef.isEmpty ? vm.userInput : "\(vm.scriptureRef) — \(vm.userInput)"
                    vm.generateImage(prompt: prompt, style: selectedStyle)
                } label: {
                    Label("Generate Image", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(accentColor))
                }
                .buttonStyle(.plain)
            }

            // Regenerate image button when one exists
            if vm.generatedImageURL != nil && !vm.isGeneratingImage {
                Button {
                    vm.generatedImageURL = nil
                    let prompt = vm.scriptureRef.isEmpty ? vm.userInput : "\(vm.scriptureRef) — \(vm.userInput)"
                    vm.generateImage(prompt: prompt, style: selectedStyle)
                } label: {
                    Label("New Image", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accentColor.opacity(0.12), lineWidth: 1))
        )
    }
}

// MARK: - Error Card

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation failed")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry", action: onRetry)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.15), lineWidth: 1))
        )
    }
}
