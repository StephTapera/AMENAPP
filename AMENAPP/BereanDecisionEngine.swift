//
//  BereanDecisionEngine.swift
//  AMENAPP
//
//  Biblical wisdom for real-life decisions — not preachy, applied intelligence.
//  BereanScriptureRef is defined in BereanWordStudyService.swift.
//

import Foundation
import Combine

// MARK: - Decision Models

enum DecisionCategory: String, CaseIterable {
    case business, relationships, career, finances, family, faith, health, creativity, conflict, unknown

    var systemPromptHint: String {
        switch self {
        case .business:
            return "This is a business or entrepreneurship question. Apply biblical principles of stewardship, integrity, and service alongside practical strategy."
        case .relationships:
            return "This is a relationships question. Apply biblical principles of love, forgiveness, covenant, and healthy boundaries with pastoral care."
        case .career:
            return "This is a career or vocation question. Apply biblical principles of calling, excellence, diligence, and serving others through work."
        case .finances:
            return "This is a finances or stewardship question. Apply biblical principles of generosity, contentment, wise planning, and debt avoidance."
        case .family:
            return "This is a family question. Apply biblical principles of honor, love, sacrifice, and healthy communication within the household."
        case .faith:
            return "This is a faith, doubt, or spiritual question. Apply careful biblical reasoning, compassion, and honest theological engagement."
        case .health:
            return "This is a health or body question. Apply biblical principles of stewardship of the body as a temple, rest, and reliance on God in suffering."
        case .creativity:
            return "This is a creativity or creative work question. Apply biblical principles of beauty, craftsmanship, image-bearing, and glorifying God through art."
        case .conflict:
            return "This is a conflict or confrontation question. Apply biblical principles of peacemaking, truth-telling, reconciliation, and Matthew 18."
        case .unknown:
            return "Apply broad biblical wisdom, common sense, and practical guidance. Be honest if more context would help."
        }
    }

    var suggestedMode: BereanPersonalityMode {
        switch self {
        case .business, .finances, .career:  return .strategist
        case .relationships, .family:        return .shepherd
        case .faith:                         return .scholar
        case .conflict:                      return .coach
        case .creativity:                    return .creator
        case .health:                        return .coach
        case .unknown:                       return .shepherd
        }
    }
}

struct DecisionAnalysis: Identifiable {
    let id = UUID()
    let question: String
    let category: DecisionCategory
    let biblicalPrinciples: [String]
    let wisdomSummary: String
    let practicalSteps: [String]
    let risks: [String]
    let scriptures: [BereanScriptureRef]
    let christCenteredClose: String
    let suggestedMode: BereanPersonalityMode
}

// MARK: - Service

@MainActor
final class BereanDecisionEngine: ObservableObject {

    static let shared = BereanDecisionEngine()

    @Published var isAnalyzing = false
    @Published var currentAnalysis: DecisionAnalysis?

    private init() {}

    // MARK: - Public API

    /// Analyze a decision question with biblical grounding and practical steps.
    @discardableResult
    func analyzeDecision(_ question: String) async throws -> DecisionAnalysis {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BereanDecisionError.emptyQuestion
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let category = detectCategory(question)
        let prompt = buildDecisionPrompt(question, category: category)
        let mode = category.suggestedMode

        dlog("BereanDecisionEngine: analyzing '\(question.prefix(60))...' [category: \(category.rawValue), mode: \(mode.rawValue)]")

        let response = try await ClaudeService.shared.sendMessageSync(prompt, mode: mode)
        let analysis = parseDecisionResponse(response, question: question, category: category)

        currentAnalysis = analysis
        dlog("BereanDecisionEngine: analysis complete for category \(category.rawValue)")
        return analysis
    }

    // MARK: - Category Detection

    private func detectCategory(_ question: String) -> DecisionCategory {
        let lower = question.lowercased()

        let keywords: [(DecisionCategory, [String])] = [
            (.business,       ["business", "startup", "company", "entrepreneur", "client", "product", "market", "revenue", "investor", "pitch", "venture", "launch", "brand"]),
            (.finances,       ["money", "finance", "invest", "debt", "budget", "savings", "loan", "tithe", "giving", "salary", "income", "spend", "afford"]),
            (.career,         ["job", "career", "work", "promotion", "boss", "fired", "quit", "vocation", "calling", "office", "profession", "hired", "résumé", "resume"]),
            (.relationships,  ["relationship", "marriage", "dating", "boyfriend", "girlfriend", "spouse", "husband", "wife", "partner", "divorce", "single", "love", "friend", "toxic"]),
            (.family,         ["family", "parent", "child", "son", "daughter", "brother", "sister", "mother", "father", "mom", "dad", "kid", "teen", "sibling"]),
            (.faith,          ["faith", "god", "jesus", "church", "bible", "prayer", "doubt", "believe", "sin", "forgive", "salvation", "scripture", "spirit", "worship"]),
            (.health,         ["health", "sick", "doctor", "anxiety", "depression", "mental", "body", "exercise", "diet", "medication", "therapy", "wellness", "pain"]),
            (.creativity,     ["creative", "art", "write", "music", "design", "film", "story", "content", "create", "build", "make", "song", "book", "poem", "brand"]),
            (.conflict,       ["conflict", "fight", "argument", "confrontation", "disagree", "offend", "hurt", "reconcile", "forgive", "anger", "dispute", "tension"])
        ]

        for (category, terms) in keywords {
            if terms.contains(where: { lower.contains($0) }) {
                return category
            }
        }
        return .unknown
    }

    // MARK: - Prompt Construction

    private func buildDecisionPrompt(_ question: String, category: DecisionCategory) -> String {
        """
        User decision question: \(question)

        Category: \(category.rawValue)
        Context hint: \(category.systemPromptHint)

        Provide a structured biblical decision analysis using these exact section labels:

        PRINCIPLE_1: (a biblical principle that applies — one sentence)
        PRINCIPLE_2: (a second biblical principle — one sentence)
        PRINCIPLE_3: (a third biblical principle — one sentence, or "none" if not applicable)
        WISDOM_SUMMARY: (a plain-text recommendation paragraph — 2-4 sentences, direct and practical)
        STEP_1: (practical action step 1)
        STEP_2: (practical action step 2)
        STEP_3: (practical action step 3)
        STEP_4: (practical action step 4, or "none")
        STEP_5: (practical action step 5, or "none")
        RISK_1: (a guardrail or risk to be aware of)
        RISK_2: (a second guardrail or risk)
        RISK_3: (a third guardrail or risk, or "none")
        SCRIPTURE_1: (format: "REFERENCE | verse text | thematic note")
        SCRIPTURE_2: (format: "REFERENCE | verse text | thematic note")
        SCRIPTURE_3: (format: "REFERENCE | verse text | thematic note", or "none")
        CHRIST_CLOSE: (a single closing sentence pointing toward Christ-like wisdom for this decision)

        Rules:
        - Be practical, not preachy.
        - Do not fabricate Bible verses — use accurate references only.
        - Write WISDOM_SUMMARY in plain conversational language.
        - CHRIST_CLOSE should be encouraging and forward-looking, not guilt-inducing.
        """
    }

    // MARK: - Response Parsing

    private func parseDecisionResponse(
        _ response: String,
        question: String,
        category: DecisionCategory
    ) -> DecisionAnalysis {

        func extract(_ label: String) -> String {
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(label):") {
                    return trimmed
                        .dropFirst("\(label):".count)
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            return ""
        }

        // Biblical principles
        var principles: [String] = []
        for i in 1...3 {
            let p = extract("PRINCIPLE_\(i)")
            if !p.isEmpty && p.lowercased() != "none" { principles.append(p) }
        }

        // Wisdom summary
        let wisdomSummary = extract("WISDOM_SUMMARY")

        // Steps
        var steps: [String] = []
        for i in 1...5 {
            let s = extract("STEP_\(i)")
            if !s.isEmpty && s.lowercased() != "none" { steps.append(s) }
        }

        // Risks
        var risks: [String] = []
        for i in 1...3 {
            let r = extract("RISK_\(i)")
            if !r.isEmpty && r.lowercased() != "none" { risks.append(r) }
        }

        // Scriptures
        var scriptures: [BereanScriptureRef] = []
        for i in 1...3 {
            let raw = extract("SCRIPTURE_\(i)")
            if raw.lowercased() == "none" || raw.isEmpty { continue }
            let parts = raw.components(separatedBy: " | ")
            if parts.count >= 3 {
                scriptures.append(BereanScriptureRef(
                    reference: parts[0].trimmingCharacters(in: .whitespaces),
                    text: parts[1].trimmingCharacters(in: .whitespaces),
                    theme: parts[2].trimmingCharacters(in: .whitespaces)
                ))
            }
        }

        let christClose = extract("CHRIST_CLOSE")

        return DecisionAnalysis(
            question: question,
            category: category,
            biblicalPrinciples: principles,
            wisdomSummary: wisdomSummary.isEmpty ? "Seek God first in this decision and trust that He will direct your path." : wisdomSummary,
            practicalSteps: steps,
            risks: risks,
            scriptures: scriptures,
            christCenteredClose: christClose.isEmpty ? "Walk this out with Christ at the center, and let His wisdom guide each step." : christClose,
            suggestedMode: category.suggestedMode
        )
    }
}

// MARK: - Errors

enum BereanDecisionError: LocalizedError {
    case emptyQuestion

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: return "Please enter a question before analyzing."
        }
    }
}
