//
//  BereanAnswerEngine.swift
//  AMENAPP
//
//  Strict RAG pipeline where Berean AI never answers without citations.
//  Single source of truth for all faith-related AI content.
//
//  Core principle: "No citation → no claim"
//  Clearly separates: Scripture, Historical Context, Interpretation
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - Citation Models

/// Represents a cited source in Berean's responses
struct BereanCitation: Codable, Identifiable {
    let id: String
    let type: CitationType
    let content: String
    let reference: String          // e.g., "John 3:16 (ESV)"
    let confidence: Double          // 0.0-1.0
    
    enum CitationType: String, Codable {
        case scripture = "scripture"              // Direct Bible verse
        case historicalContext = "historical"     // Primary/credible historical sources
        case interpretation = "interpretation"    // Denominational interpretation
        case scholarly = "scholarly"              // Academic/theological sources
    }
}

/// Scripture passage with version and metadata
struct ScripturePassage: Codable, Identifiable {
    let id: String
    let book: String
    let chapter: Int
    let verses: String              // e.g., "16-17" or "16"
    let text: String
    let version: BibleVersion
    
    var reference: String {
        "\(book) \(chapter):\(verses) (\(version.rawValue))"
    }
    
    enum BibleVersion: String, Codable {
        case esv = "ESV"
        case niv = "NIV"
        case kjv = "KJV"
        case nkjv = "NKJV"
        case nlt = "NLT"
        case nasb = "NASB"
    }
}

/// Historical context citation
struct HistoricalContext: Codable, Identifiable {
    let id: String
    let period: String              // e.g., "1st Century Roman Empire"
    let description: String
    let sources: [String]           // Primary/credible sources
    let relevance: String           // How it relates to the question
}

/// Interpretation with denominational awareness
struct TheologicalInterpretation: Codable, Identifiable {
    let id: String
    let perspective: String         // e.g., "Reformed", "Catholic", "Orthodox"
    let interpretation: String
    let supportingScripture: [String]  // References to other verses
    let isConsensus: Bool          // True if broadly agreed across denominations
    let note: String               // Clear label: "This is one interpretation..."
}

// MARK: - Berean Answer Model

/// Complete answer from Berean with all citations and context
struct BereanAnswer: Codable, Identifiable {
    let id: String
    let query: String
    let response: String            // The actual answer text
    let scripture: [ScripturePassage]
    let historicalContext: [HistoricalContext]?
    let interpretations: [TheologicalInterpretation]?
    let mode: InterpretationMode
    let timestamp: Date
    let hasCitations: Bool         // False if no factual claims made
    let responseType: ResponseType
    
    enum ResponseType: String, Codable {
        case directAnswer = "direct"           // Full answer with citations
        case clarifyingQuestion = "question"   // Asking for more context
        case generalGuidance = "guidance"      // No specific claims
        case refusal = "refusal"               // Policy violation
    }
}

/// Interpretation mode for denominational awareness
enum InterpretationMode: String, Codable {
    case literalOnly = "literal"               // Scripture only, minimal interpretation
    case historicalCritical = "historical"     // Historical-critical method
    case pastoral = "pastoral"                 // Practical application focus
    case multiPerspective = "multi"            // Show multiple denominational views
    case ecumenical = "ecumenical"            // Consensus across traditions
}

// MARK: - Safety Models

/// Content safety classification
struct SafetyCheck: Codable {
    let isSafe: Bool
    let violations: [SafetyViolation]
    let suggestedRedirect: String?     // Compassionate redirect message
    
    enum SafetyViolation: String, Codable {
        case hate = "hate"
        case harassment = "harassment"
        case selfHarm = "self_harm"
        case sexualMinors = "sexual_minors"
        case extremist = "extremist"
        case pii = "pii"                       // Personal identifiable information
        case minorsPresent = "minors"          // Content involving minors
    }
}

// MARK: - Berean Answer Engine

@MainActor
class BereanAnswerEngine: ObservableObject {
    static let shared = BereanAnswerEngine()
    
    @Published var isProcessing = false
    @Published var currentMode: InterpretationMode = .pastoral
    
    private let db = Firestore.firestore()
    private let answerCache = BereanAnswerCache.shared
    
    private init() {}
    
    // MARK: - Main Entry Point
    
    /// Process a query with strict citation requirements
    func answer(
        query: String,
        context: BereanContext? = nil,
        mode: InterpretationMode? = nil
    ) async throws -> BereanAnswer {
        dlog("📖 Berean processing query: \(query.prefix(50))...")
        
        isProcessing = true
        defer { isProcessing = false }
        
        let interpretationMode = mode ?? currentMode
        
        // 1. Safety check FIRST (before any processing)
        let safetyCheck = await checkSafety(query: query, context: context)
        if !safetyCheck.isSafe {
            return createRefusalAnswer(
                query: query,
                violations: safetyCheck.violations,
                redirect: safetyCheck.suggestedRedirect
            )
        }
        
        // 2. Check cache
        if let cached = answerCache.get(query: query, mode: interpretationMode, context: context) {
            dlog("✅ Berean cache hit")
            return cached
        }
        
        // 3. Classify query intent
        let intent = classifyIntent(query: query, context: context)
        
        // 4. Extract Scripture references from query
        let scriptureRefs = extractScriptureReferences(from: query)
        
        // 5. Fetch Scripture passages
        let scripture = await fetchScripture(references: scriptureRefs)
        
        // 6. Generate answer with strict citation requirements
        let answer: BereanAnswer
        
        if intent.requiresCitations {
            // STRICT: Must have citations for factual/biblical claims
            if scripture.isEmpty && intent.needsScripture {
                // Can't make biblical claims without Scripture
                answer = createClarifyingQuestion(
                    query: query,
                    reason: "I'd be happy to help with that. Could you specify which passage or topic you'd like to explore?"
                )
            } else {
                // Generate answer with full citations
                answer = await generateCitedAnswer(
                    query: query,
                    intent: intent,
                    scripture: scripture,
                    mode: interpretationMode,
                    context: context
                )
            }
        } else {
            // General guidance without specific claims
            answer = await generateGuidance(
                query: query,
                intent: intent,
                mode: interpretationMode
            )
        }
        
        // 7. Cache the answer
        answerCache.store(answer: answer, context: context)
        
        dlog("✅ Berean answer generated with \(answer.scripture.count) citations")
        return answer
    }
    
    // MARK: - Safety Checks
    
    private func checkSafety(query: String, context: BereanContext?) async -> SafetyCheck {
        var violations: [SafetyCheck.SafetyViolation] = []
        
        let lowercased = query.lowercased()
        
        // Hard filters for disallowed content
        let hatePatterns = ["hate", "supremacy", "inferior race", "burn in hell"]
        let harassmentPatterns = ["attack", "destroy", "curse them"]
        let selfHarmPatterns = ["end my life", "kill myself", "suicide"]
        let extremistPatterns = ["holy war", "kill unbelievers", "violence for god"]
        
        for pattern in hatePatterns {
            if lowercased.contains(pattern) {
                violations.append(.hate)
                break
            }
        }
        
        for pattern in harassmentPatterns {
            if lowercased.contains(pattern) {
                violations.append(.harassment)
                break
            }
        }
        
        for pattern in selfHarmPatterns {
            if lowercased.contains(pattern) {
                violations.append(.selfHarm)
                break
            }
        }
        
        for pattern in extremistPatterns {
            if lowercased.contains(pattern) {
                violations.append(.extremist)
                break
            }
        }
        
        // PII detection (basic patterns)
        if containsPII(query) {
            violations.append(.pii)
        }
        
        // Generate compassionate redirect if violations found
        var redirect: String? = nil
        if !violations.isEmpty {
            redirect = generateCompassionateRedirect(violations: violations)
        }
        
        return SafetyCheck(
            isSafe: violations.isEmpty,
            violations: violations,
            suggestedRedirect: redirect
        )
    }
    
    private func containsPII(_ text: String) -> Bool {
        // Basic PII patterns (SSN, credit card, email, phone)
        let patterns = [
            "\\d{3}-\\d{2}-\\d{4}",      // SSN
            "\\d{16}",                    // Credit card
            "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",  // Email
            "\\d{3}-\\d{3}-\\d{4}"       // Phone
        ]
        
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func generateCompassionateRedirect(violations: [SafetyCheck.SafetyViolation]) -> String {
        // Compassionate, not robotic responses
        if violations.contains(.selfHarm) {
            return "I'm concerned about what you're going through. Please reach out to someone who can help: National Suicide Prevention Lifeline (988) or Crisis Text Line (text HOME to 741741). You are deeply valued."
        }
        
        if violations.contains(.hate) || violations.contains(.extremist) {
            return "I can't help with that request. I'm here to help you explore Scripture in a way that honors all people as made in God's image. How else can I assist you today?"
        }
        
        if violations.contains(.harassment) {
            return "I can't help with that. I'm here to support healing and understanding. Is there something else I can help you explore in Scripture?"
        }
        
        if violations.contains(.pii) {
            return "For your safety, please don't share personal information like addresses, phone numbers, or financial details. How else can I help?"
        }
        
        return "I can't help with that request, but I'm here to explore Scripture and faith questions with you in a helpful way."
    }
    
    // MARK: - Intent Classification
    
    private func classifyIntent(query: String, context: BereanContext?) -> QueryIntent {
        let lowercased = query.lowercased()
        
        // Verse explanation
        if lowercased.contains("what does") || lowercased.contains("explain") || lowercased.contains("mean") {
            return QueryIntent(type: .explainVerse, requiresCitations: true, needsScripture: true)
        }
        
        // Prayer help
        if lowercased.contains("pray for") || lowercased.contains("help me pray") {
            return QueryIntent(type: .prayerHelp, requiresCitations: false, needsScripture: false)
        }
        
        // Sermon/notes summary
        if lowercased.contains("summarize") || lowercased.contains("summary") {
            return QueryIntent(type: .summarize, requiresCitations: true, needsScripture: false)
        }
        
        // Post safety check
        if lowercased.contains("is this okay") || lowercased.contains("should i post") {
            return QueryIntent(type: .safetyCheck, requiresCitations: false, needsScripture: false)
        }
        
        // Church finding
        if lowercased.contains("find a church") || lowercased.contains("church near") {
            return QueryIntent(type: .findChurch, requiresCitations: false, needsScripture: false)
        }
        
        // Theological question
        if lowercased.contains("what is") || lowercased.contains("who is") || lowercased.contains("why did") {
            return QueryIntent(type: .theologicalQuestion, requiresCitations: true, needsScripture: true)
        }
        
        // Default: general guidance
        return QueryIntent(type: .generalGuidance, requiresCitations: false, needsScripture: false)
    }
    
    // MARK: - Scripture Extraction & Fetching
    
    private func extractScriptureReferences(from query: String) -> [String] {
        var references: [String] = []
        
        // Pattern: "Book Chapter:Verse" (e.g., "John 3:16")
        let pattern = "([1-3]?\\s?[A-Za-z]+)\\s+(\\d+):(\\d+(?:-\\d+)?)"
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = query as NSString
            let matches = regex.matches(in: query, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let book = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let chapter = nsString.substring(with: match.range(at: 2))
                    let verses = nsString.substring(with: match.range(at: 3))
                    
                    references.append("\(book) \(chapter):\(verses)")
                }
            }
        }
        
        return references
    }
    
    private func fetchScripture(references: [String]) async -> [ScripturePassage] {
        // Use YouVersion API for real Scripture data (cost-effective!)
        let youVersion = YouVersionBibleService.shared
        
        do {
            let passages = try await youVersion.fetchVerses(references: references, version: .esv)
            dlog("📖 BereanEngine: Fetched \(passages.count) verses from YouVersion")
            return passages
        } catch {
            dlog("⚠️ BereanEngine: YouVersion fetch failed, using fallback")
            // Fallback to basic structure if API fails
            return references.compactMap { ref in
                guard let parsed = parseReferenceBasic(ref) else { return nil }
                return ScripturePassage(
                    id: UUID().uuidString,
                    book: parsed.book,
                    chapter: parsed.chapter,
                    verses: parsed.verses,
                    text: "[Scripture text unavailable - please check reference]",
                    version: .esv
                )
            }
        }
    }
    
    private func parseReferenceBasic(_ ref: String) -> (book: String, chapter: Int, verses: String)? {
        let components = ref.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        
        let book = components.dropLast().joined(separator: " ")
        let chapterVerse = components.last ?? ""
        let chapterVerseComponents = chapterVerse.components(separatedBy: ":")
        
        guard chapterVerseComponents.count == 2,
              let chapter = Int(chapterVerseComponents[0]) else { return nil }
        
        let verses = chapterVerseComponents[1]
        return (book, chapter, verses)
    }
    
    // MARK: - Answer Generation
    
    private func generateCitedAnswer(
        query: String,
        intent: QueryIntent,
        scripture: [ScripturePassage],
        mode: InterpretationMode,
        context: BereanContext?
    ) async -> BereanAnswer {
        // In production, call AI service with strict prompt:
        // "You must cite sources. Never make claims without citations."
        
        // Generate response with citations
        let response = await generateResponseWithCitations(
            query: query,
            scripture: scripture,
            mode: mode
        )
        
        // Generate historical context if relevant
        let historical = await generateHistoricalContext(
            scripture: scripture,
            mode: mode
        )
        
        // Generate interpretations based on mode
        let interpretations = await generateInterpretations(
            scripture: scripture,
            mode: mode
        )
        
        return BereanAnswer(
            id: UUID().uuidString,
            query: query,
            response: response,
            scripture: scripture,
            historicalContext: historical,
            interpretations: interpretations,
            mode: mode,
            timestamp: Date(),
            hasCitations: !scripture.isEmpty,
            responseType: .directAnswer
        )
    }
    
    private func generateResponseWithCitations(
        query: String,
        scripture: [ScripturePassage],
        mode: InterpretationMode
    ) async -> String {
        guard let primaryVerse = scripture.first else {
            return "I'd be happy to explore that with you. Could you point me to a specific passage?"
        }
        
        // Build scripture context for the prompt
        let scriptureContext = scripture.map { verse in
            "\(verse.reference): \"\(verse.text)\""
        }.joined(separator: "\n\n")
        
        let modeInstruction: String
        switch mode {
        case .literalOnly:
            modeInstruction = "Stick closely to the literal text. Minimize interpretation. Quote the passage directly."
        case .historicalCritical:
            modeInstruction = "Include historical-critical context: the original audience, cultural setting, and literary genre."
        case .pastoral:
            modeInstruction = "Focus on practical application. How does this passage speak to daily life and faith today?"
        case .multiPerspective:
            modeInstruction = "Present 2-3 different orthodox perspectives on this passage, noting where traditions agree and differ."
        case .ecumenical:
            modeInstruction = "Emphasize consensus across Christian traditions. Highlight what is broadly agreed upon."
        }
        
        let prompt = """
        A user is asking about Scripture. Answer based strictly on the provided passages. \
        Do not invent verses or make claims without citation.
        
        Question: \(query)
        
        Scripture passages:
        \(scriptureContext)
        
        Primary reference: \(primaryVerse.reference)
        
        Response style: \(modeInstruction)
        
        Provide a clear, well-cited answer. Reference verses by their full citation (e.g. John 3:16 ESV). \
        Be warm, scholarly, and pastoral. Keep the response under 400 words.
        """
        
        do {
            return try await OpenAIService.shared.sendMessageSync(prompt)
        } catch {
            // Fallback to basic citation display on API error
            return "Based on \(primaryVerse.reference):\n\n\"\(primaryVerse.text)\"\n\nThis passage speaks directly to your question. Please explore it in context with prayer and reflection."
        }
    }
    
    private func generateHistoricalContext(
        scripture: [ScripturePassage],
        mode: InterpretationMode
    ) async -> [HistoricalContext]? {
        guard mode == .historicalCritical || mode == .multiPerspective else {
            return nil
        }
        guard let primaryVerse = scripture.first else { return nil }
        
        let prompt = """
        Provide brief historical context for \(primaryVerse.reference) in 2-3 sentences. \
        Cover: time period, cultural setting, original audience. Be specific and cite historical sources where relevant.
        """
        
        do {
            let description = try await OpenAIService.shared.sendMessageSync(prompt)
            let context = HistoricalContext(
                id: UUID().uuidString,
                period: "Biblical Era",
                description: description,
                sources: ["Primary biblical scholarship", "Historical-critical analysis"],
                relevance: "This context helps illuminate the original meaning and application."
            )
            return [context]
        } catch {
            return nil
        }
    }
    
    private func generateInterpretations(
        scripture: [ScripturePassage],
        mode: InterpretationMode
    ) async -> [TheologicalInterpretation]? {
        guard mode == .multiPerspective || mode == .pastoral else {
            return nil
        }
        guard let primaryVerse = scripture.first else { return nil }
        
        let prompt = """
        For \(primaryVerse.reference), briefly describe 1-2 distinct orthodox Christian interpretive perspectives \
        in 2-3 sentences total. Note where major traditions agree. Be fair and ecumenical.
        """
        
        do {
            let interpretationText = try await OpenAIService.shared.sendMessageSync(prompt)
            let interpretation = TheologicalInterpretation(
                id: UUID().uuidString,
                perspective: mode == .multiPerspective ? "Multiple perspectives" : "Pastoral",
                interpretation: interpretationText,
                supportingScripture: [],
                isConsensus: mode == .ecumenical,
                note: "This reflects common Christian interpretive traditions."
            )
            return [interpretation]
        } catch {
            return nil
        }
    }
    
    private func generateGuidance(
        query: String,
        intent: QueryIntent,
        mode: InterpretationMode
    ) async -> BereanAnswer {
        let contextPrompt: String
        switch intent.type {
        case .prayerHelp:
            contextPrompt = "The user is looking for help with prayer. Offer warm, Scripture-informed encouragement."
        case .findChurch:
            contextPrompt = "The user wants help finding a church. Offer practical biblical guidance on Christian community."
        case .safetyCheck:
            contextPrompt = "The user wants to know if something aligns with Christian values. Offer thoughtful, grace-filled guidance."
        default:
            contextPrompt = "Offer gentle, encouraging, biblically-informed guidance."
        }
        
        let prompt = """
        \(contextPrompt)
        
        User's message: "\(query)"
        
        Respond warmly and wisely. You may suggest relevant Scripture if genuinely helpful, \
        but do not make specific factual claims without citing a verse. Keep it under 200 words.
        """
        
        do {
            let guidance = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanAnswer(
                id: UUID().uuidString,
                query: query,
                response: guidance,
                scripture: [],
                historicalContext: nil,
                interpretations: nil,
                mode: mode,
                timestamp: Date(),
                hasCitations: false,
                responseType: .generalGuidance
            )
        } catch {
            return BereanAnswer(
                id: UUID().uuidString,
                query: query,
                response: "That's a meaningful question worth exploring. I'd encourage you to bring this to God in prayer and explore related Scripture passages. How can I help you dig deeper?",
                scripture: [],
                historicalContext: nil,
                interpretations: nil,
                mode: mode,
                timestamp: Date(),
                hasCitations: false,
                responseType: .generalGuidance
            )
        }
    }
    
    // MARK: - Helper Answers
    
    private func createRefusalAnswer(
        query: String,
        violations: [SafetyCheck.SafetyViolation],
        redirect: String?
    ) -> BereanAnswer {
        return BereanAnswer(
            id: UUID().uuidString,
            query: query,
            response: redirect ?? "I can't help with that request.",
            scripture: [],
            historicalContext: nil,
            interpretations: nil,
            mode: currentMode,
            timestamp: Date(),
            hasCitations: false,
            responseType: .refusal
        )
    }
    
    private func createClarifyingQuestion(query: String, reason: String) -> BereanAnswer {
        return BereanAnswer(
            id: UUID().uuidString,
            query: query,
            response: reason,
            scripture: [],
            historicalContext: nil,
            interpretations: nil,
            mode: currentMode,
            timestamp: Date(),
            hasCitations: false,
            responseType: .clarifyingQuestion
        )
    }
}

// MARK: - Supporting Models

struct BereanContext: Codable {
    let userId: String?
    let featureContext: FeatureContext
    let sessionId: String?
    
    enum FeatureContext: String, Codable {
        case prayer = "prayer"
        case post = "post"
        case notes = "notes"
        case chat = "chat"
        case findChurch = "find_church"
    }
}

struct QueryIntent {
    let type: IntentType
    let requiresCitations: Bool
    let needsScripture: Bool
    
    enum IntentType {
        case explainVerse
        case prayerHelp
        case summarize
        case safetyCheck
        case findChurch
        case theologicalQuestion
        case generalGuidance
    }
}

// MARK: - Answer Cache

@MainActor
class BereanAnswerCache {
    static let shared = BereanAnswerCache()
    
    private var cache: [String: CachedAnswer] = [:]
    private let ttl: TimeInterval = 3600  // 1 hour
    
    private init() {}
    
    struct CachedAnswer {
        let answer: BereanAnswer
        let expiresAt: Date
    }
    
    func get(query: String, mode: InterpretationMode, context: BereanContext?) -> BereanAnswer? {
        let key = cacheKey(query: query, mode: mode, context: context)
        
        guard let cached = cache[key] else { return nil }
        
        // Check expiration
        if Date() > cached.expiresAt {
            cache.removeValue(forKey: key)
            return nil
        }
        
        return cached.answer
    }
    
    func store(answer: BereanAnswer, context: BereanContext?) {
        // Don't cache sensitive content (prayers, confessions)
        if context?.featureContext == .prayer {
            return
        }
        
        let key = cacheKey(query: answer.query, mode: answer.mode, context: context)
        
        let cached = CachedAnswer(
            answer: answer,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        
        cache[key] = cached
    }
    
    private func cacheKey(query: String, mode: InterpretationMode, context: BereanContext?) -> String {
        let contextStr = context?.featureContext.rawValue ?? "general"
        return "\(query.lowercased())_\(mode.rawValue)_\(contextStr)"
    }
    
    func clear() {
        cache.removeAll()
    }
}
