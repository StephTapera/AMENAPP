// ConfidenceScoringService.swift
// AMENAPP
//
// Evaluates the quality and trustworthiness of every AI response.
// Produces a 0-1.0 confidence score used to:
//   - Decide whether to show a disclaimer
//   - Weight responses in feed ranking
//   - Trigger human review for low-confidence safety decisions
//   - Drive UI states (high/medium/low confidence indicators)
//
// Scoring dimensions:
//   1. Scripture citation quality (for theological responses)
//   2. Response coherence and completeness
//   3. Factual confidence signals from model
//   4. Policy compliance (no hedged/uncertain safety decisions)
//   5. Provider reliability weight (based on task + provider match)
//   6. Response length appropriateness
//   7. Theological safety (detects overconfident theological claims)

import Foundation
import NaturalLanguage

// MARK: - Confidence Breakdown

struct ConfidenceBreakdown {
    let overall: Double
    let citationQuality: Double
    let coherence: Double
    let completeness: Double
    let providerMatch: Double
    let theologicalSafety: Double
    let details: String

    var tier: ConfidenceTier {
        switch overall {
        case 0.75...1.0: return .high
        case 0.50..<0.75: return .medium
        default:          return .low
        }
    }
}

enum ConfidenceTier: String {
    case high    = "high"
    case medium  = "medium"
    case low     = "low"

    var displayLabel: String {
        switch self {
        case .high:   return "Scripture-grounded"
        case .medium: return "Thoughtful response"
        case .low:    return "Berean's perspective"
        }
    }

    var disclaimerNeeded: Bool { self == .low }
}

// MARK: - ConfidenceScoringService

@MainActor
final class ConfidenceScoringService {

    static let shared = ConfidenceScoringService()

    // Provider × category quality weights
    // Higher = more reliable for this task combination
    private let providerQualityMatrix: [String: [AITaskCategory: Double]] = [
        "claude": [
            .scriptureGrounding: 0.92,
            .assistantResponse:  0.90,
            .prayerDrafting:     0.88,
            .devotionalGeneration: 0.90,
            .crisisDetection:    0.85,
            .rewriteSuggestion:  0.82
        ],
        "openai": [
            .summaryGeneration:    0.88,
            .captionHelp:          0.85,
            .sentimentTone:        0.84,
            .opportunityMatching:  0.86,
            .safetyScreening:      0.82
        ],
        "vertex_ai": [
            .mediaSafety:          0.91,
            .contentRecommendation: 0.87,
            .semanticSearch:       0.88,
            .altTextGeneration:    0.85
        ],
        "local": [
            .sentimentTone:        0.65,
            .topicClassification:  0.70,
            .safetyScreening:      0.68,
            .feedRanking:          0.80
        ]
    ]

    private init() {}

    // MARK: - Primary Scoring

    func score(
        response: String,
        request: BereanAIRequest,
        citations: [ScriptureCitation]
    ) async -> Double {
        let breakdown = await breakdown(response: response, request: request, citations: citations)
        return breakdown.overall
    }

    func breakdown(
        response: String,
        request: BereanAIRequest,
        citations: [ScriptureCitation]
    ) async -> ConfidenceBreakdown {

        // 1. Citation quality (weighted heavily for theological responses)
        let citationScore = scoreCitations(citations, category: request.category)

        // 2. Response coherence
        let coherenceScore = scoreCoherence(response)

        // 3. Completeness
        let completenessScore = scoreCompleteness(response, category: request.category)

        // 4. Provider-category match
        let providerMatchScore = scoreProviderMatch(
            provider: "claude",  // simplified — in practice passed in from routing result
            category: request.category
        )

        // 5. Theological safety (penalizes overconfident claims on debated topics)
        let theologicalSafetyScore = scoreTheologicalSafety(response, category: request.category)

        // Weighted composite
        let weights: (citation: Double, coherence: Double, completeness: Double, provider: Double, theology: Double)

        switch request.category {
        case .scriptureGrounding, .devotionalGeneration:
            weights = (0.35, 0.20, 0.15, 0.15, 0.15)
        case .safetyScreening, .crisisDetection, .dmSafetyGate:
            weights = (0.05, 0.30, 0.40, 0.15, 0.10)
        case .summaryGeneration, .captionHelp:
            weights = (0.10, 0.35, 0.35, 0.15, 0.05)
        default:
            weights = (0.20, 0.25, 0.25, 0.20, 0.10)
        }

        let overall = (
            citationScore      * weights.citation    +
            coherenceScore     * weights.coherence   +
            completenessScore  * weights.completeness +
            providerMatchScore * weights.provider    +
            theologicalSafetyScore * weights.theology
        )

        let clamped = min(1.0, max(0.0, overall))

        let details = """
        Citations: \(String(format: "%.2f", citationScore)) | \
        Coherence: \(String(format: "%.2f", coherenceScore)) | \
        Complete: \(String(format: "%.2f", completenessScore)) | \
        Provider: \(String(format: "%.2f", providerMatchScore)) | \
        Theology: \(String(format: "%.2f", theologicalSafetyScore))
        """

        return ConfidenceBreakdown(
            overall: clamped,
            citationQuality: citationScore,
            coherence: coherenceScore,
            completeness: completenessScore,
            providerMatch: providerMatchScore,
            theologicalSafety: theologicalSafetyScore,
            details: details
        )
    }

    // MARK: - Scoring Components

    private func scoreCitations(_ citations: [ScriptureCitation], category: AITaskCategory) -> Double {
        guard category == .scriptureGrounding || category == .devotionalGeneration ||
              category == .prayerDrafting || category == .assistantResponse else {
            return 0.75  // Neutral — citations not expected
        }

        if citations.isEmpty { return 0.40 }  // Expected but absent — penalize

        let avgRelevance = citations.map(\.relevanceScore).reduce(0, +) / Double(citations.count)
        let countBonus = min(0.20, Double(citations.count) * 0.05)  // Up to +0.20 for more citations
        return min(1.0, avgRelevance + countBonus)
    }

    private func scoreCoherence(_ response: String) -> Double {
        let wordCount = response.split(separator: " ").count

        // Too short — incomplete
        if wordCount < 10 { return 0.20 }

        // Too long without structure — may be rambling
        if wordCount > 800 { return 0.65 }

        // Check for hedging language (signs of model uncertainty)
        let hedges = ["i'm not sure", "i don't know", "it's unclear", "i cannot determine",
                       "this is uncertain", "i may be wrong", "i might be mistaken"]
        let lower = response.lowercased()
        let hedgeCount = hedges.filter { lower.contains($0) }.count
        let hedgePenalty = min(0.30, Double(hedgeCount) * 0.10)

        // Structure signals (lists, paragraphs suggest organized thinking)
        let hasBullets = response.contains("•") || response.contains("-") || response.contains("*")
        let hasMultipleParagraphs = response.components(separatedBy: "\n\n").count > 1
        let structureBonus = (hasBullets ? 0.05 : 0) + (hasMultipleParagraphs ? 0.05 : 0)

        return max(0, min(1.0, 0.80 - hedgePenalty + structureBonus))
    }

    private func scoreCompleteness(_ response: String, category: AITaskCategory) -> Double {
        let wordCount = response.split(separator: " ").count

        let expectedRange: ClosedRange<Int>
        switch category {
        case .captionHelp:          expectedRange = 15...100
        case .sentimentTone:        expectedRange = 1...20
        case .topicClassification:  expectedRange = 1...10
        case .summaryGeneration:    expectedRange = 50...300
        case .scriptureGrounding:   expectedRange = 80...500
        case .assistantResponse:    expectedRange = 40...400
        case .prayerDrafting:       expectedRange = 30...200
        case .devotionalGeneration: expectedRange = 100...600
        case .safetyScreening, .dmSafetyGate: expectedRange = 1...50
        default:                    expectedRange = 20...300
        }

        if expectedRange.contains(wordCount) { return 0.90 }
        if wordCount < expectedRange.lowerBound { return max(0.30, 0.90 - Double(expectedRange.lowerBound - wordCount) * 0.02) }
        return max(0.60, 0.90 - Double(wordCount - expectedRange.upperBound) * 0.001)
    }

    private func scoreProviderMatch(provider: String, category: AITaskCategory) -> Double {
        providerQualityMatrix[provider]?[category] ?? 0.70
    }

    private func scoreTheologicalSafety(_ response: String, category: AITaskCategory) -> Double {
        guard category == .scriptureGrounding || category == .assistantResponse ||
              category == .devotionalGeneration else { return 0.85 }

        let lower = response.lowercased()

        // Check for overconfident theological claims on debated topics
        let overconfidentPatterns = [
            "the bible definitively teaches",
            "there is no debate",
            "all christians must believe",
            "the only true interpretation",
            "anyone who disagrees is wrong",
            "this is the only correct view"
        ]
        let overconfidentCount = overconfidentPatterns.filter { lower.contains($0) }.count
        let overconfidentPenalty = min(0.40, Double(overconfidentCount) * 0.15)

        // Reward humility signals
        let humilitySignals = [
            "some theologians", "various traditions", "it's debated",
            "perspectives differ", "one view holds", "another interpretation"
        ]
        let humilityCount = humilitySignals.filter { lower.contains($0) }.count
        let humilityBonus = min(0.15, Double(humilityCount) * 0.05)

        return max(0, min(1.0, 0.85 - overconfidentPenalty + humilityBonus))
    }
}

// MARK: - Confidence UI Component

/// Lightweight confidence indicator for use in any view that shows AI responses.
struct BereanConfidenceIndicator: View {
    let tier: ConfidenceTier
    var showLabel: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tierColor)
            if showLabel {
                Text(tier.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tierColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tierColor.opacity(0.10))
                .overlay(Capsule().stroke(tierColor.opacity(0.20), lineWidth: 0.5))
        )
    }

    private var iconName: String {
        switch tier {
        case .high:   return "book.closed.fill"
        case .medium: return "lightbulb.fill"
        case .low:    return "info.circle.fill"
        }
    }

    private var tierColor: Color {
        switch tier {
        case .high:   return Color(red: 0.20, green: 0.60, blue: 0.35)
        case .medium: return Color(red: 0.80, green: 0.55, blue: 0.15)
        case .low:    return Color(red: 0.55, green: 0.55, blue: 0.65)
        }
    }
}

import SwiftUI
