import Foundation
import UIKit
import FirebaseFunctions

// Provides AI-powered posting intelligence: intent detection, safety pre-screening,
// media analysis, and caption generation.
@MainActor
final class PostingIntelligenceLayer: ObservableObject {
    static let shared = PostingIntelligenceLayer()

    @Published private(set) var intelligenceResult: PostingIntelligenceResult = .empty
    @Published private(set) var isAnalyzing = false
    @Published private(set) var mediaAnalysis: MediaAnalysisResult?

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // Analyze draft text + context to get intent, mode, suggestions
    func analyze(draft: String, context: PostingContext, images: [UIImage] = []) async {
        guard !draft.isEmpty || !images.isEmpty else {
            intelligenceResult = .empty
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let contextRoutes = ComposerContextEngine.shared.contextualAudienceRoutes
        let payload: [String: Any] = [
            "draft": draft,
            "postingContext": context.rawValue,
            "broadArea": LocationContextService.shared.currentContext.broadAreaLabel,
            "hasImages": !images.isEmpty
        ]

        do {
            let result = try await functions.httpsCallable("analyzePostingIntent").call(payload)
            guard let data = result.data as? [String: Any] else { return }

            let intent = PostIntent(rawValue: data["intent"] as? String ?? "") ?? .shareM
            let mode = ComposerMode(rawValue: data["composerMode"] as? String ?? "") ?? .standard
            let suggestionData = data["suggestions"] as? [[String: Any]] ?? []
            let suggestions = suggestionData.prefix(5).map { s in
                SmartSuggestion(
                    id: s["id"] as? String ?? UUID().uuidString,
                    type: SmartSuggestionType(rawValue: s["type"] as? String ?? "") ?? .captionAssist,
                    text: s["text"] as? String ?? "",
                    actionLabel: s["actionLabel"] as? String,
                    confidence: s["confidence"] as? Double ?? 0.5
                )
            }
            let safetyData = data["safetyFlags"] as? [[String: Any]] ?? []
            let safetyFlags = safetyData.map { f in
                SafetyFlag(
                    id: UUID().uuidString,
                    type: SafetyFlagType(rawValue: f["type"] as? String ?? "") ?? .sensitiveInfo,
                    message: f["message"] as? String ?? "",
                    severity: SafetyFlagSeverity(rawValue: f["severity"] as? String ?? "info") ?? .info
                )
            }

            intelligenceResult = PostingIntelligenceResult(
                detectedIntent: intent,
                suggestedMode: mode,
                suggestions: Array(suggestions),
                audienceRoutes: contextRoutes,
                safetyFlags: safetyFlags,
                postingContext: context,
                aiCaption: data["suggestedCaption"] as? String
            )
        } catch {
            // Fall back gracefully — AI is additive, not required
            intelligenceResult = PostingIntelligenceResult(
                detectedIntent: .shareM,
                suggestedMode: context.composerMode,
                suggestions: [],
                audienceRoutes: contextRoutes,
                safetyFlags: [],
                postingContext: context
            )
        }
    }

    // Analyze an image for media type, OCR text, caption suggestions
    func analyzeMedia(_ image: UIImage) async -> MediaAnalysisResult {
        guard let imageData = image.jpegData(compressionQuality: 0.6) else {
            return MediaAnalysisResult(detectedType: .general, suggestedTags: [], recommendedAudiences: [], hasSensitiveContent: false)
        }
        let base64 = imageData.base64EncodedString()

        do {
            let result = try await functions.httpsCallable("analyzePostMedia").call(["imageBase64": base64])
            guard let data = result.data as? [String: Any] else { throw URLError(.badServerResponse) }
            let analysis = MediaAnalysisResult(
                detectedType: DetectedMediaType(rawValue: data["type"] as? String ?? "") ?? .general,
                extractedText: data["extractedText"] as? String,
                suggestedCaption: data["suggestedCaption"] as? String,
                suggestedTags: data["tags"] as? [String] ?? [],
                recommendedAudiences: (data["audiences"] as? [String] ?? []).compactMap { AudienceRouteType(rawValue: $0) },
                hasSensitiveContent: data["hasSensitiveContent"] as? Bool ?? false,
                sensitivityReason: data["sensitivityReason"] as? String
            )
            mediaAnalysis = analysis
            return analysis
        } catch {
            let fallback = MediaAnalysisResult(detectedType: .general, suggestedTags: [], recommendedAudiences: [], hasSensitiveContent: false)
            mediaAnalysis = fallback
            return fallback
        }
    }

    // Generate a structured post from raw notes, photos, or text
    func generateStructuredPost(from rawText: String, intent: PostIntent) async -> String? {
        let payload: [String: Any] = ["rawText": rawText, "intent": intent.rawValue]
        do {
            let result = try await functions.httpsCallable("generateStructuredPost").call(payload)
            return (result.data as? [String: Any])?["post"] as? String
        } catch {
            return nil
        }
    }

    func reset() {
        intelligenceResult = .empty
        mediaAnalysis = nil
    }
}
