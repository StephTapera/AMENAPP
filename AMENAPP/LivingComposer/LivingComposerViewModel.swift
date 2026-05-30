import Foundation
import SwiftUI
import PhotosUI

@MainActor
final class LivingComposerViewModel: ObservableObject {
    // MARK: - Draft State
    @Published var draftText = ""
    @Published var selectedImages: [UIImage] = []
    @Published var selectedPhotoItems: [PhotosPickerItem] = []
    @Published var composerMode: ComposerMode = .standard
    @Published var selectedIntent: PostIntent = .general

    // MARK: - Intelligence State
    @Published private(set) var intelligenceResult: PostingIntelligenceResult = .empty
    @Published private(set) var isAnalyzing = false
    @Published private(set) var mediaAnalysis: MediaAnalysisResult?

    // MARK: - Audience State
    @Published private(set) var audienceRoutes: [AudienceRoute] = [.personalFeed()]

    // MARK: - Posting State
    @Published private(set) var isPosting = false
    @Published private(set) var postSuccess = false
    @Published private(set) var postError: String?

    // MARK: - UI State
    @Published var showIntentPicker = false
    @Published var showAudienceSelector = false
    @Published var showAIAssist = false
    @Published var activeAISuggestion: SmartSuggestion?

    private let contextEngine = ComposerContextEngine.shared
    private let audienceRouter = SmartAudienceRouter.shared
    private let intelligence = PostingIntelligenceLayer.shared
    private var analysisTask: Task<Void, Never>?

    var canPost: Bool {
        (!draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty) && !isPosting
    }

    var currentContext: PostingContext {
        contextEngine.currentContext
    }

    var uiHint: ComposerUIHint {
        composerMode.uiHint
    }

    var activeSafetyFlags: [PostSafetyFlag] {
        intelligence.intelligenceResult.safetyFlags.filter { $0.severity != .info }
    }

    var hasBlockingFlag: Bool {
        intelligence.intelligenceResult.safetyFlags.contains { $0.severity == .block }
    }

    // MARK: - Initialization

    func onAppear() {
        contextEngine.evaluateFromCurrentState()
        composerMode = contextEngine.suggestedMode
        audienceRoutes = contextEngine.contextualAudienceRoutes

        Task { await audienceRouter.loadAvailableRoutes(context: currentContext, locationContext: LocationContextService.shared.currentContext) }
    }

    // MARK: - Text Changes

    func onDraftChanged(_ text: String) {
        analysisTask?.cancel()
        guard text.count > 20 else { return }
        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await intelligence.analyze(draft: text, context: currentContext, images: selectedImages)
            intelligenceResult = intelligence.intelligenceResult
            isAnalyzing = false
        }
        isAnalyzing = true
    }

    // MARK: - Mode

    func setMode(_ mode: ComposerMode) {
        composerMode = mode
    }

    func setIntent(_ intent: PostIntent) {
        selectedIntent = intent
        showIntentPicker = false
    }

    // MARK: - Photo Selection

    func loadSelectedPhotos() {
        Task {
            var loaded: [UIImage] = []
            for item in selectedPhotoItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            selectedImages = loaded
            if let first = loaded.first {
                Task {
                    mediaAnalysis = await intelligence.analyzeMedia(first)
                    if let caption = mediaAnalysis?.suggestedCaption, draftText.isEmpty {
                        draftText = caption
                    }
                }
            }
        }
    }

    // MARK: - AI Assist

    func applySuggestion(_ suggestion: ComposerSuggestion) {
        switch suggestion.type {
        case .captionAssist:
            if draftText.isEmpty { draftText = suggestion.text }
        case .ocrExtract:
            if let extracted = mediaAnalysis?.extractedText {
                draftText = extracted
            }
        default:
            break
        }
        activeAISuggestion = nil
    }

    func generatePost() {
        Task {
            let generated = await intelligence.generateStructuredPost(from: draftText, intent: selectedIntent)
            if let generated { draftText = generated }
        }
    }

    // MARK: - Publish

    func publish() async {
        guard canPost else { return }
        isPosting = true
        defer { isPosting = false }
        let content = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let category: Post.PostCategory = composerMode == .reflective ? .testimonies : .openTable
        do {
            try await FirebasePostService.shared.createPost(content: content, category: category)
            postSuccess = true
            reset()
        } catch {
            postError = error.localizedDescription
        }
    }

    // MARK: - Reset

    func reset() {
        draftText = ""
        selectedImages = []
        selectedPhotoItems = []
        postSuccess = false
        postError = nil
        intelligence.reset()
        intelligenceResult = .empty
        mediaAnalysis = nil
    }
}
