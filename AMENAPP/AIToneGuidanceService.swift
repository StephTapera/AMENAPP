//
//  AIToneGuidanceService.swift
//  AMENAPP
//
//  AI-powered tone analysis, content moderation, and gentle guidance
//  Uses OpenAI Moderation API (FREE) + GPT-4o-mini for suggestions
//

import Foundation
import Combine

@MainActor
class AIToneGuidanceService: ObservableObject {
    static let shared = AIToneGuidanceService()

    @Published var currentFeedback: ToneFeedback?
    @Published var isAnalyzing = false

    private let openAI = OpenAIService.shared
    private var analysisTask: Task<ToneFeedback?, Never>?
    private var debounceTimer: Timer?
    private let apiKey: String

    private init() {
        // Get API key from Info.plist
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            self.apiKey = key
        } else {
            self.apiKey = ""
            print("⚠️ OpenAI API key not found in Info.plist")
        }
        print("✅ AIToneGuidanceService initialized")
    }

    // MARK: - Models

    struct ToneFeedback: Identifiable {
        let id = UUID()
        let type: FeedbackType
        let message: String
        let suggestion: String?
        let scriptureReference: String?

        enum FeedbackType {
            case warning       // Harsh, divisive, or inappropriate
            case caution       // Could be misinterpreted
            case encouragement // Positive, uplifting
            case flagged       // Content moderation issue
        }

        var icon: String {
            switch type {
            case .warning: return "exclamationmark.triangle.fill"
            case .caution: return "info.circle.fill"
            case .encouragement: return "checkmark.circle.fill"
            case .flagged: return "xmark.octagon.fill"
            }
        }

        var color: String {
            switch type {
            case .warning: return "orange"
            case .caution: return "blue"
            case .encouragement: return "green"
            case .flagged: return "red"
            }
        }
    }

    struct ModerationResult: Codable {
        let flagged: Bool
        let categories: Categories

        struct Categories: Codable {
            let sexual: Bool
            let hate: Bool
            let harassment: Bool
            let selfHarm: Bool
            let sexualMinors: Bool
            let hateThreatening: Bool
            let violenceGraphic: Bool
            let selfHarmIntent: Bool
            let selfHarmInstructions: Bool
            let harassmentThreatening: Bool
            let violence: Bool

            enum CodingKeys: String, CodingKey {
                case sexual, hate, harassment, violence
                case selfHarm = "self-harm"
                case sexualMinors = "sexual/minors"
                case hateThreatening = "hate/threatening"
                case violenceGraphic = "violence/graphic"
                case selfHarmIntent = "self-harm/intent"
                case selfHarmInstructions = "self-harm/instructions"
                case harassmentThreatening = "harassment/threatening"
            }
        }
    }

    // MARK: - Public Methods

    /// Analyze comment text with debouncing (500ms)
    func analyzeText(_ text: String) {
        // Cancel previous timer
        debounceTimer?.invalidate()

        // Clear feedback if text is too short
        guard text.count >= 10 else {
            currentFeedback = nil
            return
        }

        // Debounce analysis
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performAnalysis(text)
            }
        }
    }

    /// Analyze without debouncing (for submit validation)
    func analyzeTextImmediate(_ text: String) async -> ToneFeedback? {
        return await performAnalysis(text)
    }

    // MARK: - Analysis Logic

    private func performAnalysis(_ text: String) async -> ToneFeedback? {
        // Cancel previous analysis
        analysisTask?.cancel()

        isAnalyzing = true

        analysisTask = Task {
            var result: ToneFeedback? = nil
            
            do {
                // Step 1: FREE Content Moderation Check (OpenAI Moderation API)
                if let moderationIssue = try await checkContentModeration(text) {
                    await MainActor.run {
                        currentFeedback = moderationIssue
                        isAnalyzing = false
                    }
                    result = moderationIssue
                    return result
                }

                // Step 2: Tone Analysis (GPT-4o - configured model)
                let toneFeedback = try await analyzeTone(text)

                await MainActor.run {
                    currentFeedback = toneFeedback
                    isAnalyzing = false
                }
                result = toneFeedback
            } catch {
                print("❌ [TONE] Analysis failed: \(error)")
                await MainActor.run {
                    isAnalyzing = false
                }
            }
            
            return result
        }

        return await analysisTask?.value
    }

    // MARK: - Content Moderation (FREE)

    private func checkContentModeration(_ text: String) async throws -> ToneFeedback? {
        // Call OpenAI Moderation API (completely FREE)
        let moderationEndpoint = "https://api.openai.com/v1/moderations"

        var request = URLRequest(url: URL(string: moderationEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first else {
            return nil
        }

        let flagged = firstResult["flagged"] as? Bool ?? false

        if flagged {
            // Determine specific issue
            if let categories = firstResult["categories"] as? [String: Bool] {
                var issueType = "inappropriate content"

                if categories["hate"] == true || categories["hate/threatening"] == true {
                    issueType = "hateful or divisive language"
                } else if categories["harassment"] == true || categories["harassment/threatening"] == true {
                    issueType = "harassing language"
                } else if categories["violence"] == true || categories["violence/graphic"] == true {
                    issueType = "violent content"
                } else if categories["sexual"] == true || categories["sexual/minors"] == true {
                    issueType = "inappropriate content"
                } else if categories["self-harm"] == true {
                    issueType = "concerning content about self-harm"
                }

                return ToneFeedback(
                    type: .flagged,
                    message: "This comment contains \(issueType) that goes against our community guidelines.",
                    suggestion: "Please revise your comment to be respectful and faith-focused.",
                    scriptureReference: "Ephesians 4:29 - Do not let any unwholesome talk come out of your mouths"
                )
            }
        }

        return nil
    }

    // MARK: - Tone Analysis (GPT-4o-mini)

    private func analyzeTone(_ text: String) async throws -> ToneFeedback? {
        let prompt = """
        Analyze the tone of this comment for a faith-based social app. Provide brief guidance.

        Comment: "\(text)"

        Respond in JSON:
        {
          "tone": "harsh" | "divisive" | "neutral" | "encouraging" | "grace-filled",
          "needsGuidance": true | false,
          "message": "brief feedback (1 sentence)",
          "suggestion": "gentler alternative (optional, only if needsGuidance=true)",
          "scripture": "relevant verse reference (optional)"
        }

        Guidelines:
        - Flag harsh, judgmental, or divisive language
        - Encourage grace, kindness, and biblical love
        - Celebrate encouraging, supportive comments
        - Keep feedback brief and gentle
        """

        let response = try await openAI.sendMessageSync(prompt)

        // Parse JSON response
        guard let jsonData = response.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let tone = json["tone"] as? String,
              let needsGuidance = json["needsGuidance"] as? Bool,
              let message = json["message"] as? String else {
            return nil
        }

        let suggestion = json["suggestion"] as? String
        let scripture = json["scripture"] as? String

        // Determine feedback type
        var feedbackType: ToneFeedback.FeedbackType
        switch tone {
        case "harsh", "divisive":
            feedbackType = .warning
        case "neutral":
            return nil  // No feedback for neutral comments
        case "encouraging", "grace-filled":
            feedbackType = .encouragement
        default:
            feedbackType = .caution
        }

        // Only show guidance if needed OR if highly encouraging
        if !needsGuidance && feedbackType != .encouragement {
            return nil
        }

        return ToneFeedback(
            type: feedbackType,
            message: message,
            suggestion: suggestion,
            scriptureReference: scripture
        )
    }

    // MARK: - Helper Methods

    func clearFeedback() {
        currentFeedback = nil
        debounceTimer?.invalidate()
        analysisTask?.cancel()
    }
}

// MARK: - Cost Optimization Notes
/*
 COST BREAKDOWN:

 1. Content Moderation: $0.00 (OpenAI Moderation API is FREE)
 2. Tone Analysis: ~$0.0002 per comment (GPT-4o-mini)

 For 5,000 comments/day:
 - Moderation: $0/day
 - Tone Analysis: $1/day = $30/month

 TOTAL: ~$30/month (vs $75/month without optimization)

 FURTHER OPTIMIZATION:
 - Cache common phrases/patterns
 - Only analyze when user types 50+ chars
 - Skip analysis for known users with good history
 - Could reduce to $15-20/month
 */
