//
//  BereanIntegrationService.swift
//  AMENAPP
//
//  Integration layer that connects existing features to the new Berean system.
//  Ensures all AI-powered features use the same engine with consistent safety/quality.
//

import Foundation
import Combine
import FirebaseAuth
import SwiftUI

// MARK: - Berean Integration Service

@MainActor
class BereanIntegrationService: ObservableObject {
    static let shared = BereanIntegrationService()
    
    private let router = BereanIntentRouter.shared
    private let fastMode = BereanFastMode.shared
    private let answerEngine = BereanAnswerEngine.shared
    
    @Published var isProcessing = false
    
    private init() {}
    
    // MARK: - Chat Integration (for BereanAIAssistantView)
    
    /// Send message through Berean system
    func sendMessage(
        text: String,
        userId: String?,
        sessionId: String? = nil
    ) async throws -> BereanChatResponse {
        let context = BereanContext(
            userId: userId,
            featureContext: .chat,
            sessionId: sessionId
        )
        
        let response = try await router.process(
            input: text,
            context: context,
            sessionId: sessionId
        )
        
        return BereanChatResponse(
            text: response.content,
            citations: response.answer?.scripture ?? [],
            confidence: response.confidence,
            hasWarnings: !response.warnings.isEmpty,
            warnings: response.warnings
        )
    }
    
    /// Stream message for real-time response (faster UX)
    func streamMessage(
        text: String,
        userId: String?
    ) -> AsyncStream<BereanStreamChunk> {
        let context = BereanContext(
            userId: userId,
            featureContext: .chat,
            sessionId: nil
        )
        
        return AsyncStream { continuation in
            Task {
                let stream = await fastMode.getFastAnswer(query: text, context: context)
                
                for await chunk in stream {
                    let bereanChunk = BereanStreamChunk(
                        content: chunk.content,
                        isPartial: chunk.isPartial,
                        citations: chunk.metadata?.citations ?? []
                    )
                    continuation.yield(bereanChunk)
                }
                
                continuation.finish()
            }
        }
    }
    
    // MARK: - Prayer Integration
    
    /// Analyze prayer for Prayer-to-Action Companion
    func analyzePrayer(
        text: String,
        authorId: String
    ) async throws -> PrayerAnalysisResult {
        let context = BereanContext(
            userId: authorId,
            featureContext: .prayer,
            sessionId: nil
        )
        
        let response = try await router.process(
            input: "Analyze this prayer: \(text)",
            context: context
        )
        
        return PrayerAnalysisResult(
            summary: response.content,
            suggestedActions: extractActions(from: response.content),
            verseReferences: response.answer?.scripture.map { $0.reference } ?? []
        )
    }
    
    /// Generate prayer draft
    func draftPrayer(
        topic: String,
        userId: String
    ) async throws -> String {
        let context = BereanContext(
            userId: userId,
            featureContext: .prayer,
            sessionId: nil
        )
        
        let response = try await router.process(
            input: "Help me pray for \(topic)",
            context: context
        )
        
        return response.content
    }
    
    // MARK: - Post Integration
    
    /// Check if post is safe to publish
    func checkPostSafety(
        content: String,
        authorId: String
    ) async -> PostSafetyResult {
        let context = BereanContext(
            userId: authorId,
            featureContext: .post,
            sessionId: nil
        )
        
        do {
            let response = try await router.process(
                input: "Is this post okay to publish? \(content)",
                context: context
            )
            
            return PostSafetyResult(
                isSafe: response.warnings.isEmpty,
                warnings: response.warnings,
                suggestions: extractSuggestions(from: response.content)
            )
        } catch {
            // Fail closed: any error in the safety pipeline means we cannot
            // confirm the content is safe. Return isSafe=false so the caller
            // surfaces an error rather than silently publishing unsafe content.
            return PostSafetyResult(
                isSafe: false,
                warnings: ["Safety check failed — please try again before publishing."],
                suggestions: []
            )
        }
    }
    
    /// Generate verse context panel for post
    func generateVerseContext(
        for post: Post,
        userId: String?
    ) async -> VerseContextPanel? {
        // Use FastMode for instant cached context
        if let panel = await fastMode.generateContextPanel(for: post) {
            return VerseContextPanel(
                verses: panel.verses.map { verse in
                    BereanVerseReference(
                        reference: verse.reference,
                        text: verse.text,
                        version: verse.version
                    )
                },
                summary: panel.summary
            )
        }
        
        return nil
    }
    
    // MARK: - Notes Integration
    
    /// Summarize sermon notes
    func summarizeNotes(
        content: String,
        userId: String
    ) async throws -> NotesSummary {
        let context = BereanContext(
            userId: userId,
            featureContext: .notes,
            sessionId: nil
        )
        
        let response = try await router.process(
            input: "Summarize these notes: \(content)",
            context: context
        )
        
        return NotesSummary(
            summary: response.content,
            keyPoints: extractKeyPoints(from: response.content),
            verseReferences: response.answer?.scripture.map { $0.reference } ?? []
        )
    }
    
    // MARK: - Church Finding Integration
    
    /// Generate first visit coach advice
    func getFirstVisitAdvice(
        churchName: String,
        userId: String
    ) async throws -> FirstVisitAdvice {
        let context = BereanContext(
            userId: userId,
            featureContext: .findChurch,
            sessionId: nil
        )
        
        let response = try await router.process(
            input: "I'm visiting \(churchName) for the first time. What should I expect?",
            context: context
        )
        
        return FirstVisitAdvice(
            advice: response.content,
            tips: extractTips(from: response.content)
        )
    }
    
    // MARK: - Prefetching (Performance)
    
    /// Prefetch content when user navigates to a screen
    func prefetchForScreen(_ screen: BereanContext.FeatureContext) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        fastMode.prefetchFor(screen: screen, userId: userId)
    }
    
    /// Prefetch verse context when scrolling through feed
    func prefetchVerseContexts(for posts: [Post]) {
        Task {
            for post in posts.prefix(5) {  // Prefetch first 5 posts
                _ = await fastMode.generateContextPanel(for: post)
            }
        }
    }
    
    // MARK: - Interpretation Mode Control
    
    /// Set interpretation mode (literal, pastoral, multi-perspective, etc.)
    func setInterpretationMode(_ mode: InterpretationMode) {
        answerEngine.currentMode = mode
    }
    
    func getCurrentMode() -> InterpretationMode {
        return answerEngine.currentMode
    }
    
    // MARK: - Cache Management
    
    func getCacheStats() -> CacheStats {
        return fastMode.getCacheStats()
    }
    
    func clearCache() {
        fastMode.clearCache()
    }
    
    // MARK: - Helper Extraction Methods
    
    private func extractActions(from text: String) -> [String] {
        // Extract action suggestions from response
        // Look for bullet points or numbered lists
        let lines = text.components(separatedBy: "\n")
        var actions: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let action = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !action.isEmpty {
                    actions.append(action)
                }
            }
        }
        
        return actions
    }
    
    private func extractSuggestions(from text: String) -> [String] {
        return extractActions(from: text)
    }
    
    private func extractKeyPoints(from text: String) -> [String] {
        return extractActions(from: text)
    }
    
    private func extractTips(from text: String) -> [String] {
        return extractActions(from: text)
    }
}

// MARK: - Response Models

struct BereanChatResponse {
    let text: String
    let citations: [ScripturePassage]
    let confidence: Double
    let hasWarnings: Bool
    let warnings: [String]
}

struct BereanStreamChunk {
    let content: String
    let isPartial: Bool
    let citations: [BereanCitation]
}

struct PrayerAnalysisResult {
    let summary: String
    let suggestedActions: [String]
    let verseReferences: [String]
}

struct PostSafetyResult {
    let isSafe: Bool
    let warnings: [String]
    let suggestions: [String]
}

struct VerseContextPanel {
    let verses: [BereanVerseReference]
    let summary: String
}

struct BereanVerseReference {
    let reference: String
    let text: String
    let version: String
}

struct NotesSummary {
    let summary: String
    let keyPoints: [String]
    let verseReferences: [String]
}

struct FirstVisitAdvice {
    let advice: String
    let tips: [String]
}

// MARK: - View Extensions for Easy Integration

extension View {
    /// Prefetch Berean content when this view appears
    func prefetchBereanContent(for screen: BereanContext.FeatureContext) -> some View {
        self.onAppear {
            BereanIntegrationService.shared.prefetchForScreen(screen)
        }
    }
}

// MARK: - SwiftUI Components

/// Citation badge view (can be used in posts, chat, etc.)
struct CitationBadge: View {
    let citation: BereanCitation
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(citation.reference)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(8)
    }
    
    private var iconName: String {
        switch citation.type {
        case .scripture:
            return "book.closed"
        case .historicalContext:
            return "clock"
        case .interpretation:
            return "lightbulb"
        case .scholarly:
            return "graduationcap"
        }
    }
}

/// Verse context card (can be overlaid on posts)
struct VerseContextCard: View {
    let panel: VerseContextPanel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book.closed")
                    .foregroundColor(.blue)
                Text("Referenced Scripture")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                ForEach(panel.verses, id: \.reference) { verse in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verse.reference)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                        Text(verse.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

/// Interpretation mode picker
struct InterpretationModePicker: View {
    @Binding var selectedMode: InterpretationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interpretation Style")
                .font(.headline)
            
            ForEach(Array(zip(
                [InterpretationMode.literalOnly, .pastoral, .historicalCritical, .multiPerspective, .ecumenical],
                [0, 1, 2, 3, 4]
            )), id: \.1) { mode, _ in
                Button {
                    selectedMode = mode
                    BereanIntegrationService.shared.setInterpretationMode(mode)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(modeName(mode))
                                .font(.subheadline.weight(.medium))
                            Text(modeDescription(mode))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                    .background(selectedMode == mode ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
    
    private func modeName(_ mode: InterpretationMode) -> String {
        switch mode {
        case .literalOnly: return "Literal Only"
        case .pastoral: return "Pastoral"
        case .historicalCritical: return "Historical-Critical"
        case .multiPerspective: return "Multi-Perspective"
        case .ecumenical: return "Ecumenical"
        }
    }
    
    private func modeDescription(_ mode: InterpretationMode) -> String {
        switch mode {
        case .literalOnly:
            return "Scripture only, minimal interpretation"
        case .pastoral:
            return "Practical application focus"
        case .historicalCritical:
            return "Historical context and critical analysis"
        case .multiPerspective:
            return "Multiple denominational views"
        case .ecumenical:
            return "Consensus across Christian traditions"
        }
    }
}
