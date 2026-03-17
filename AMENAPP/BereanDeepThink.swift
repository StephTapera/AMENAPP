//
//  BereanDeepThink.swift
//  AMENAPP
//
//  Deep Think mode for complex theological questions.
//  Breaks questions into sub-questions, researches each against Scripture (RAG),
//  synthesizes with explicit reasoning chain, and presents multiple
//  orthodox perspectives with denominational attribution.
//
//  Uses Claude Opus for maximum reasoning quality.
//

import Foundation

// MARK: - Deep Think Models

struct DeepThinkResult: Identifiable {
    let id: String
    let query: String
    let subQuestions: [SubQuestion]
    let synthesis: String
    let perspectives: [TheologicalPerspective]
    let keyScriptures: [ScripturePassage]
    let reasoning: String          // Visible chain-of-thought
    let confidence: Double
    let processingTimeMs: Int
}

struct SubQuestion: Identifiable {
    let id: String
    let question: String
    let answer: String
    let supportingScripture: [String]
    let status: SubQuestionStatus

    enum SubQuestionStatus {
        case answered
        case partiallyAnswered
        case requiresFurtherStudy
    }
}

struct TheologicalPerspective: Identifiable {
    let id: String
    let tradition: String          // e.g., "Reformed", "Catholic", "Orthodox", "Wesleyan"
    let position: String           // Brief summary of this tradition's view
    let supportingScripture: [String]
    let keyTheologians: [String]   // Notable thinkers who hold this view
    let isConsensus: Bool          // Broadly agreed across traditions?
}

// MARK: - Deep Think Service

@MainActor
final class BereanDeepThink: ObservableObject {
    static let shared = BereanDeepThink()

    @Published var isThinking = false
    @Published var currentStep: String = ""
    @Published var progress: Double = 0.0

    private let claude = ClaudeService.shared
    private let semanticSearch = BereanSemanticSearch.shared
    private let youVersion = YouVersionBibleService.shared

    private init() {}

    // MARK: - Main Entry Point

    /// Process a complex theological question with deep reasoning
    func think(query: String) async throws -> DeepThinkResult {
        let start = Date()

        isThinking = true
        currentStep = "Analyzing your question..."
        progress = 0.0
        defer {
            isThinking = false
            currentStep = ""
            progress = 1.0
        }

        // Step 1: Decompose the question into sub-questions
        progress = 0.1
        currentStep = "Breaking down the question..."
        let subQuestionTexts = try await decomposeQuestion(query)

        // Step 2: Research each sub-question with RAG
        progress = 0.3
        currentStep = "Searching Scripture..."
        var subQuestions: [SubQuestion] = []
        var allScripture: [ScripturePassage] = []

        for (index, sq) in subQuestionTexts.enumerated() {
            progress = 0.3 + (0.3 * Double(index) / Double(subQuestionTexts.count))
            currentStep = "Researching: \(sq.prefix(50))..."

            let result = await researchSubQuestion(sq)
            subQuestions.append(result.subQuestion)
            allScripture.append(contentsOf: result.passages)
        }

        // Step 3: Generate multi-perspective analysis
        progress = 0.7
        currentStep = "Analyzing perspectives..."
        let perspectives = try await generatePerspectives(
            query: query,
            subQuestions: subQuestions,
            scripture: allScripture
        )

        // Step 4: Synthesize final answer with reasoning chain
        progress = 0.85
        currentStep = "Synthesizing answer..."
        let (synthesis, reasoning) = try await synthesize(
            query: query,
            subQuestions: subQuestions,
            perspectives: perspectives,
            scripture: allScripture
        )

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        return DeepThinkResult(
            id: UUID().uuidString,
            query: query,
            subQuestions: subQuestions,
            synthesis: synthesis,
            perspectives: perspectives,
            keyScriptures: allScripture,
            reasoning: reasoning,
            confidence: calculateConfidence(subQuestions: subQuestions, perspectives: perspectives),
            processingTimeMs: elapsed
        )
    }

    // MARK: - Step 1: Decompose Question

    private func decomposeQuestion(_ query: String) async throws -> [String] {
        let prompt = """
        You are a theological research assistant. Break down this complex question into \
        3-5 specific sub-questions that, when answered, will provide a comprehensive response.

        Question: "\(query)"

        Output ONLY a JSON array of strings. No commentary.
        Example: ["What does the Old Testament say about X?", "How did Jesus address X?", "What do Paul's letters say?"]
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)

        // Parse JSON array
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let questions = try? JSONDecoder().decode([String].self, from: data) {
            return Array(questions.prefix(5))
        }

        // Fallback: split by newline
        return cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 10 }
            .prefix(5)
            .map { String($0) }
    }

    // MARK: - Step 2: Research Sub-Question

    private struct SubQuestionResearch {
        let subQuestion: SubQuestion
        let passages: [ScripturePassage]
    }

    private func researchSubQuestion(_ question: String) async -> SubQuestionResearch {
        // Semantic search for relevant passages
        let ragContext = await semanticSearch.buildRAGContext(query: question)

        // Collect all passages
        var passages: [ScripturePassage] = []
        for result in ragContext.retrievedPassages {
            passages.append(contentsOf: result.relevantPassages)
        }

        // Generate answer for this sub-question
        let scriptureContext = passages.isEmpty
            ? "No specific passages found — answer from general biblical knowledge."
            : passages.map { "\($0.reference): \"\($0.text)\"" }.joined(separator: "\n")

        let prompt = """
        Answer this biblical sub-question concisely (3-5 sentences). \
        Cite specific verses. If uncertain, say so.

        Question: \(question)

        Available Scripture:
        \(scriptureContext)
        """

        do {
            let answer = try await claude.sendMessageSync(prompt, mode: .scholar)
            let refs = passages.map { $0.reference }

            return SubQuestionResearch(
                subQuestion: SubQuestion(
                    id: UUID().uuidString,
                    question: question,
                    answer: answer,
                    supportingScripture: refs,
                    status: passages.isEmpty ? .requiresFurtherStudy : .answered
                ),
                passages: passages
            )
        } catch {
            return SubQuestionResearch(
                subQuestion: SubQuestion(
                    id: UUID().uuidString,
                    question: question,
                    answer: "Unable to research this aspect. Further study recommended.",
                    supportingScripture: [],
                    status: .requiresFurtherStudy
                ),
                passages: []
            )
        }
    }

    // MARK: - Step 3: Generate Perspectives

    private func generatePerspectives(
        query: String,
        subQuestions: [SubQuestion],
        scripture: [ScripturePassage]
    ) async throws -> [TheologicalPerspective] {
        let subQSummary = subQuestions.map { "- \($0.question): \($0.answer.prefix(100))..." }
            .joined(separator: "\n")

        let prompt = """
        For this theological question, present 3-4 major orthodox Christian perspectives.

        Question: "\(query)"

        Research findings:
        \(subQSummary)

        Output strict JSON only:
        [
          {
            "tradition": "string (e.g., Reformed, Catholic, Orthodox, Wesleyan)",
            "position": "string (2-3 sentences summarizing this tradition's view)",
            "supportingScripture": ["string (verse references)"],
            "keyTheologians": ["string (notable thinkers)"],
            "isConsensus": false
          }
        ]
        Include one entry with "isConsensus": true if there's broad agreement on any aspect.
        """

        let response = try await claude.sendMessageSync(prompt, mode: .debater)

        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct PerspectiveDTO: Decodable {
            let tradition: String
            let position: String
            let supportingScripture: [String]
            let keyTheologians: [String]
            let isConsensus: Bool
        }

        if let data = cleaned.data(using: .utf8),
           let dtos = try? JSONDecoder().decode([PerspectiveDTO].self, from: data) {
            return dtos.map { dto in
                TheologicalPerspective(
                    id: UUID().uuidString,
                    tradition: dto.tradition,
                    position: dto.position,
                    supportingScripture: dto.supportingScripture,
                    keyTheologians: dto.keyTheologians,
                    isConsensus: dto.isConsensus
                )
            }
        }

        // Fallback single perspective
        return [TheologicalPerspective(
            id: UUID().uuidString,
            tradition: "General Christian",
            position: cleaned,
            supportingScripture: [],
            keyTheologians: [],
            isConsensus: true
        )]
    }

    // MARK: - Step 4: Synthesize

    private func synthesize(
        query: String,
        subQuestions: [SubQuestion],
        perspectives: [TheologicalPerspective],
        scripture: [ScripturePassage]
    ) async throws -> (synthesis: String, reasoning: String) {
        let subQSummary = subQuestions.enumerated().map { i, sq in
            "\(i + 1). \(sq.question)\n   Answer: \(sq.answer.prefix(200))"
        }.joined(separator: "\n\n")

        let perspectiveSummary = perspectives.map { p in
            "- \(p.tradition): \(p.position.prefix(150))"
        }.joined(separator: "\n")

        let scriptureRefs = scripture.map { $0.reference }.joined(separator: ", ")

        let prompt = """
        You are Berean, a deeply knowledgeable biblical AI assistant.

        A user asked: "\(query)"

        You've researched this question thoroughly. Here are your findings:

        Sub-question research:
        \(subQSummary)

        Theological perspectives:
        \(perspectiveSummary)

        Key Scripture: \(scriptureRefs)

        Now provide TWO things:

        1. REASONING (prefix with "REASONING:"): Show your step-by-step thinking. \
        Walk through the key evidence, note where traditions agree/disagree, \
        and explain how you arrived at your synthesis. 3-5 sentences.

        2. SYNTHESIS (prefix with "SYNTHESIS:"): A comprehensive, warm, pastoral answer \
        that acknowledges different perspectives fairly. Cite specific verses inline. \
        Note where Christians broadly agree vs. where they differ. \
        End with an encouraging, Christ-centered closing. 200-400 words.
        """

        let response = try await claude.sendMessageSync(prompt, mode: .scholar)

        // Parse reasoning and synthesis
        var reasoning = ""
        var synthesis = ""

        if let reasoningRange = response.range(of: "REASONING:"),
           let synthesisRange = response.range(of: "SYNTHESIS:") {
            reasoning = String(response[reasoningRange.upperBound..<synthesisRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            synthesis = String(response[synthesisRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            synthesis = response
            reasoning = "Direct synthesis from research findings."
        }

        return (synthesis, reasoning)
    }

    // MARK: - Confidence Calculation

    private func calculateConfidence(
        subQuestions: [SubQuestion],
        perspectives: [TheologicalPerspective]
    ) -> Double {
        let answeredRatio = Double(subQuestions.filter { $0.status == .answered }.count) /
            Double(max(subQuestions.count, 1))
        let hasConsensus = perspectives.contains { $0.isConsensus }
        let consensusBonus: Double = hasConsensus ? 0.1 : 0.0

        return min(1.0, answeredRatio * 0.8 + 0.1 + consensusBonus)
    }
}
