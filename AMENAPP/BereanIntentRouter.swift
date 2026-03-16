//
//  BereanIntentRouter.swift
//  AMENAPP
//
//  Intent classification layer that routes to the right tool/workflow
//  with policy checks before any generation.
//
//  Makes the whole app feel like one coherent brain.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Routing Models

/// The main routing decision
struct RoutingDecision {
    let tool: BereanTool
    let priority: Priority
    let policyChecks: [PolicyCheck]
    let estimatedLatency: TimeInterval
    
    enum Priority {
        case immediate      // <100ms (cached/local)
        case fast          // <500ms (simple generation)
        case standard      // <2s (full RAG)
        case background    // >2s (prefetch/enhancement)
    }
}

/// Available Berean tools
enum BereanTool {
    case ragExegesis           // Cited verse explanation
    case deepThink             // Chain-of-thought multi-perspective theological reasoning
    case prayerDrafting        // Gentle prayer composition
    case notesSummarizer       // Sermon/notes summary
    case safetyChecker         // Content moderation
    case searchAssist          // Church/people/content search
    case firstVisitCoach       // Church visit preparation
    case verseContext          // Quick verse context panel
    case prayerActionCompanion // Prayer-to-action analysis
    case encouragementWriter   // Follow-up messages
    case refusal               // Policy violation handler
}

/// Policy check result
struct PolicyCheck: Codable {
    let checkType: CheckType
    let passed: Bool
    let reason: String?
    let action: PolicyAction
    
    enum CheckType: String, Codable {
        case pii = "pii"
        case minors = "minors"
        case selfHarm = "self_harm"
        case harassment = "harassment"
        case hate = "hate"
        case extremism = "extremism"
        case spam = "spam"
        case authenticity = "authenticity"
    }
    
    enum PolicyAction: String, Codable {
        case allow = "allow"
        case block = "block"
        case warn = "warn"
        case redirect = "redirect"
    }
}

/// Session memory boundaries
struct BereanSession: Codable {
    let id: String
    let userId: String
    let context: BereanContext
    let startedAt: Date
    var messages: [SessionMessage]
    let retentionPolicy: RetentionPolicy
    
    enum RetentionPolicy: String, Codable {
        case ephemeral = "ephemeral"       // Don't retain (prayers, confessions)
        case session = "session"           // Keep during session only
        case saved = "saved"               // User explicitly saved
        case cached = "cached"             // Cache for performance
    }
}

struct SessionMessage: Codable, Identifiable {
    let id: String
    let content: String
    let role: MessageRole
    let timestamp: Date
    let redacted: Bool  // True if sensitive content was redacted
    
    enum MessageRole: String, Codable {
        case user = "user"
        case assistant = "assistant"
    }
}

// MARK: - Berean Intent Router

@MainActor
class BereanIntentRouter: ObservableObject {
    static let shared = BereanIntentRouter()
    
    @Published var activeSession: BereanSession?
    @Published var isProcessing = false
    
    private let answerEngine = BereanAnswerEngine.shared
    private let db = Firestore.firestore()
    private var sessions: [String: BereanSession] = [:]
    
    private init() {}
    
    // MARK: - Main Entry Point
    
    /// Single entry point for all Berean interactions
    func process(
        input: String,
        context: BereanContext,
        sessionId: String? = nil
    ) async throws -> BereanResponse {
        print("🧠 Berean routing request from \(context.featureContext.rawValue)...")
        
        isProcessing = true
        defer { isProcessing = false }
        
        // 1. Get or create session
        let session = getOrCreateSession(id: sessionId, userId: context.userId, context: context)

        // 1a. Scrupulosity / repetition detection — before generation to break shame loops early
        if let scrupulosityResponse = detectScrupulosityLoop(input: input, session: session) {
            await updateSession(session: session, input: input, response: scrupulosityResponse)
            return scrupulosityResponse
        }
        
        // 2. Pre-generation policy checks
        let policyResults = await runPolicyChecks(input: input, context: context)
        
        // Check if any policy check failed with BLOCK action
        if let blocked = policyResults.first(where: { $0.action == .block }) {
            return createRefusalResponse(
                input: input,
                reason: blocked.reason ?? "Policy violation",
                context: context
            )
        }
        
        // 3. Classify intent and route to tool
        let routing = classifyAndRoute(input: input, context: context, policyResults: policyResults)
        
        // 4. Execute the appropriate tool
        let response = await executeTool(
            tool: routing.tool,
            input: input,
            context: context,
            session: session,
            policyResults: policyResults
        )
        
        // 5. Update session (with retention policy)
        await updateSession(session: session, input: input, response: response)
        
        print("✅ Berean routed to \(routing.tool) with \(routing.priority) priority")
        return response
    }
    
    // MARK: - Policy Checks
    
    private func runPolicyChecks(input: String, context: BereanContext) async -> [PolicyCheck] {
        var checks: [PolicyCheck] = []
        
        // 0. Jailbreak / impersonation check — runs first so we short-circuit before any generation
        checks.append(checkForJailbreak(input: input))
        
        // 1. PII check
        checks.append(checkForPII(input: input))
        
        // 2. Minors check
        checks.append(checkForMinors(input: input))
        
        // 3. Self-harm check
        checks.append(checkForSelfHarm(input: input))
        
        // 4. Harassment check
        checks.append(checkForHarassment(input: input))
        
        // 5. Hate speech check
        checks.append(checkForHate(input: input))
        
        // 6. Extremism check
        checks.append(checkForExtremism(input: input))
        
        // 7. Spam check (if posting content)
        if context.featureContext == .post {
            checks.append(checkForSpam(input: input))
        }
        
        // 8. Authenticity check (if posting content)
        if context.featureContext == .post {
            checks.append(await checkAuthenticity(input: input))
        }
        
        return checks
    }
    
    // MARK: - Jailbreak / Impersonation Check
    
    /// Detects attempts to override Berean's identity, guidelines, or safety constraints.
    /// Uses canonical patterns from BereanSafetyPolicy — do not duplicate patterns here.
    private func checkForJailbreak(input: String) -> PolicyCheck {
        let lowercased = input.lowercased()
        
        for pattern in BereanSafetyPolicy.jailbreakPatterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .authenticity,
                    passed: false,
                    reason: BereanSafetyPolicy.refusal(for: .jailbreak),
                    action: .block
                )
            }
        }
        
        return PolicyCheck(checkType: .authenticity, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForPII(input: String) -> PolicyCheck {
        let patterns = [
            "\\d{3}-\\d{2}-\\d{4}",      // SSN
            "\\d{16}",                    // Credit card
            "\\d{3}-\\d{3}-\\d{4}"       // Phone
        ]
        
        for pattern in patterns {
            if input.range(of: pattern, options: .regularExpression) != nil {
                return PolicyCheck(
                    checkType: .pii,
                    passed: false,
                    reason: "Please don't share personal information like SSN, credit cards, or phone numbers",
                    action: .warn
                )
            }
        }
        
        return PolicyCheck(checkType: .pii, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForMinors(input: String) -> PolicyCheck {
        let minorPatterns = ["my child", "my kid", "my son", "my daughter", "student", "teenager"]
        let inappropriatePatterns = ["sexual", "nude", "explicit"]
        
        let lowercased = input.lowercased()
        let hasMinor = minorPatterns.contains { lowercased.contains($0) }
        let hasInappropriate = inappropriatePatterns.contains { lowercased.contains($0) }
        
        if hasMinor && hasInappropriate {
            return PolicyCheck(
                checkType: .minors,
                passed: false,
                reason: "Content involving minors and inappropriate material is not allowed",
                action: .block
            )
        }
        
        return PolicyCheck(checkType: .minors, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForSelfHarm(input: String) -> PolicyCheck {
        let patterns = [
            "end my life", "kill myself", "suicide", "want to die",
            "harm myself", "cut myself", "no reason to live"
        ]
        
        let lowercased = input.lowercased()
        
        for pattern in patterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .selfHarm,
                    passed: false,
                    reason: "I'm concerned about what you're sharing. Please reach out: 988 Suicide & Crisis Lifeline or text HOME to 741741",
                    action: .redirect
                )
            }
        }
        
        return PolicyCheck(checkType: .selfHarm, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForHarassment(input: String) -> PolicyCheck {
        let patterns = [
            "attack them", "destroy them", "curse them out",
            "make them suffer", "ruin their life", "get revenge"
        ]
        
        let lowercased = input.lowercased()
        
        for pattern in patterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .harassment,
                    passed: false,
                    reason: "I can't help with that. I'm here to support healing and understanding.",
                    action: .block
                )
            }
        }
        
        return PolicyCheck(checkType: .harassment, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForHate(input: String) -> PolicyCheck {
        // Use multi-word phrase patterns to avoid false positives on common words like "hate".
        // "hate" alone is a valid word in many scripture questions ("what does God say about hate?").
        // Only block clear dehumanizing phrases.
        let blockPatterns = [
            "white supremacy", "racial supremacy", "inferior race", "subhuman",
            "god hates fags", "god hates", "deserve to die because",
            "kill all", "exterminate the", "race is inferior",
            "burn those", "wipe out the"
        ]
        
        let lowercased = input.lowercased()
        
        for pattern in blockPatterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .hate,
                    passed: false,
                    reason: "I can't help with that. I'm here to help you explore Scripture in a way that honors all people as made in God's image.",
                    action: .block
                )
            }
        }
        
        return PolicyCheck(checkType: .hate, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForExtremism(input: String) -> PolicyCheck {
        let patterns = [
            "holy war", "kill unbelievers", "violence for god",
            "jihad", "crusade against", "god wants us to fight"
        ]
        
        let lowercased = input.lowercased()
        
        for pattern in patterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .extremism,
                    passed: false,
                    reason: "I can't help with that request. I'm here to explore faith in a way that promotes peace and understanding.",
                    action: .block
                )
            }
        }
        
        return PolicyCheck(checkType: .extremism, passed: true, reason: nil, action: .allow)
    }
    
    private func checkForSpam(input: String) -> PolicyCheck {
        // Simple spam detection: excessive caps, repeated characters, links
        let uppercaseRatio = Double(input.filter { $0.isUppercase }.count) / Double(max(input.count, 1))
        
        if uppercaseRatio > 0.6 && input.count > 20 {
            return PolicyCheck(
                checkType: .spam,
                passed: false,
                reason: "Please use normal capitalization",
                action: .warn
            )
        }
        
        // Check for repeated characters (e.g. "aaaaaaa" or "!!!!!!")
        if input.range(of: "(.)\\1{5,}", options: .regularExpression) != nil {
            return PolicyCheck(
                checkType: .spam,
                passed: false,
                reason: "Please avoid excessive repeated characters",
                action: .warn
            )
        }
        
        return PolicyCheck(checkType: .spam, passed: true, reason: nil, action: .allow)
    }
    
    private func checkAuthenticity(input: String) async -> PolicyCheck {
        // Basic AI-generated content detection
        let aiPatterns = [
            "as an ai language model",
            "i don't have personal",
            "i cannot provide medical advice",
            "in my training data"
        ]
        
        let lowercased = input.lowercased()
        
        for pattern in aiPatterns {
            if lowercased.contains(pattern) {
                return PolicyCheck(
                    checkType: .authenticity,
                    passed: false,
                    reason: "This looks like AI-generated content. We encourage authentic, personal sharing.",
                    action: .warn
                )
            }
        }
        
        return PolicyCheck(checkType: .authenticity, passed: true, reason: nil, action: .allow)
    }
    
    // MARK: - Intent Classification & Routing
    
    private func classifyAndRoute(
        input: String,
        context: BereanContext,
        policyResults: [PolicyCheck]
    ) -> RoutingDecision {
        let lowercased = input.lowercased()
        
        // Route based on feature context + input analysis
        switch context.featureContext {
        case .prayer:
            return routePrayerIntent(input: lowercased)
            
        case .post:
            return routePostIntent(input: lowercased, policyResults: policyResults)
            
        case .notes:
            return routeNotesIntent(input: lowercased)
            
        case .findChurch:
            return routeChurchIntent(input: lowercased)
            
        case .chat:
            return routeChatIntent(input: lowercased)
        }
    }
    
    private func routePrayerIntent(input: String) -> RoutingDecision {
        if input.contains("help me pray") || input.contains("how should i pray") {
            return RoutingDecision(
                tool: .prayerDrafting,
                priority: .fast,
                policyChecks: [],
                estimatedLatency: 0.5
            )
        }
        
        if input.contains("action") || input.contains("what can i do") {
            return RoutingDecision(
                tool: .prayerActionCompanion,
                priority: .standard,
                policyChecks: [],
                estimatedLatency: 1.5
            )
        }
        
        // Default: verse context for prayer
        return RoutingDecision(
            tool: .verseContext,
            priority: .immediate,
            policyChecks: [],
            estimatedLatency: 0.1
        )
    }
    
    private func routePostIntent(input: String, policyResults: [PolicyCheck]) -> RoutingDecision {
        if input.contains("is this okay") || input.contains("should i post") {
            return RoutingDecision(
                tool: .safetyChecker,
                priority: .fast,
                policyChecks: policyResults,
                estimatedLatency: 0.3
            )
        }
        
        // Default: verse context
        return RoutingDecision(
            tool: .verseContext,
            priority: .immediate,
            policyChecks: policyResults,
            estimatedLatency: 0.1
        )
    }
    
    private func routeNotesIntent(input: String) -> RoutingDecision {
        if input.contains("summarize") || input.contains("summary") {
            return RoutingDecision(
                tool: .notesSummarizer,
                priority: .standard,
                policyChecks: [],
                estimatedLatency: 1.0
            )
        }
        
        // Default: RAG for note enhancement
        return RoutingDecision(
            tool: .ragExegesis,
            priority: .standard,
            policyChecks: [],
            estimatedLatency: 1.5
        )
    }
    
    private func routeChurchIntent(input: String) -> RoutingDecision {
        if input.contains("first visit") || input.contains("what to expect") {
            return RoutingDecision(
                tool: .firstVisitCoach,
                priority: .fast,
                policyChecks: [],
                estimatedLatency: 0.5
            )
        }
        
        // Default: search assist
        return RoutingDecision(
            tool: .searchAssist,
            priority: .fast,
            policyChecks: [],
            estimatedLatency: 0.3
        )
    }
    
    private func routeChatIntent(input: String) -> RoutingDecision {
        // Deep theological questions → deep think mode (uses Opus for reasoning)
        let deepThinkTriggers = [
            "is baptism required", "predestination", "free will",
            "once saved always saved", "speaking in tongues",
            "trinity", "problem of evil", "why does god allow",
            "different denominations", "catholic vs protestant",
            "compare perspectives", "deep dive", "analyze deeply",
            "theological debate", "what do different", "calvinist",
            "arminian", "both sides"
        ]
        if deepThinkTriggers.contains(where: { input.contains($0) }) {
            return RoutingDecision(
                tool: .deepThink,
                priority: .background,
                policyChecks: [],
                estimatedLatency: 8.0
            )
        }

        if input.contains("explain") || input.contains("what does") || input.contains("mean") {
            return RoutingDecision(
                tool: .ragExegesis,
                priority: .standard,
                policyChecks: [],
                estimatedLatency: 1.5
            )
        }

        if input.contains("encourage") || input.contains("message") {
            return RoutingDecision(
                tool: .encouragementWriter,
                priority: .fast,
                policyChecks: [],
                estimatedLatency: 0.5
            )
        }

        // Default: RAG
        return RoutingDecision(
            tool: .ragExegesis,
            priority: .standard,
            policyChecks: [],
            estimatedLatency: 1.5
        )
    }
    
    // MARK: - Tool Execution
    
    private func executeTool(
        tool: BereanTool,
        input: String,
        context: BereanContext,
        session: BereanSession,
        policyResults: [PolicyCheck]
    ) async -> BereanResponse {
        switch tool {
        case .ragExegesis:
            return await executeRAGExegesis(input: input, context: context)

        case .deepThink:
            return await executeDeepThink(input: input, context: context)

        case .prayerDrafting:
            return await executePrayerDrafting(input: input, context: context)
            
        case .notesSummarizer:
            return await executeNotesSummarizer(input: input, context: context)
            
        case .safetyChecker:
            return executeSafetyChecker(input: input, policyResults: policyResults)
            
        case .searchAssist:
            return executeSearchAssist(input: input, context: context)
            
        case .firstVisitCoach:
            return await executeFirstVisitCoach(input: input)
            
        case .verseContext:
            return await executeVerseContext(input: input)
            
        case .prayerActionCompanion:
            return await executePrayerActionCompanion(input: input, context: context)
            
        case .encouragementWriter:
            return await executeEncouragementWriter(input: input)
            
        case .refusal:
            return createRefusalResponse(input: input, reason: "Policy violation", context: context)
        }
    }
    
    private func executeDeepThink(input: String, context: BereanContext) async -> BereanResponse {
        do {
            let result = try await BereanDeepThink.shared.think(query: input)

            // Format the deep think result into a rich response
            var content = result.synthesis

            // Append perspectives section
            if !result.perspectives.isEmpty {
                content += "\n\nPerspectives explored:"
                for perspective in result.perspectives {
                    let consensusTag = perspective.isConsensus ? " (broad consensus)" : ""
                    content += "\n\n\(perspective.tradition)\(consensusTag): \(perspective.position)"
                    if !perspective.supportingScripture.isEmpty {
                        content += "\nScripture: \(perspective.supportingScripture.joined(separator: ", "))"
                    }
                }
            }

            return BereanResponse(
                content: content,
                answer: nil,
                tool: .deepThink,
                confidence: result.confidence,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "I encountered an issue with deep analysis. Let me give a simpler answer.",
                answer: nil,
                tool: .deepThink,
                confidence: 0.0,
                warnings: [error.localizedDescription]
            )
        }
    }

    private func executeRAGExegesis(input: String, context: BereanContext) async -> BereanResponse {
        do {
            let answer = try await answerEngine.answer(query: input, context: context)
            return BereanResponse(
                content: answer.response,
                answer: answer,
                tool: .ragExegesis,
                confidence: answer.hasCitations ? 0.9 : 0.5,
                warnings: []
            )
        } catch {
            return createErrorResponse(error: error, context: context)
        }
    }
    
    private func executePrayerDrafting(input: String, context: BereanContext) async -> BereanResponse {
        let prompt = """
        You are Berean, a warm and prayerful Bible study companion. \
        A user is asking for help with prayer: "\(input)"
        
        Write a heartfelt, Scripture-grounded prayer (3-5 sentences) that addresses their request. \
        Use conversational, sincere language — not overly formal. \
        Include one brief Scripture reference where it fits naturally. \
        End with an encouraging closing line. Do not use placeholder text.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .prayerDrafting,
                confidence: 0.85,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "Here is a prayer you might use:\n\nLord, I come to you today with this on my heart. You know my needs better than I do, and I trust in Your wisdom and love. Guide me, strengthen me, and let Your will be done. Amen.\n\nFeel free to make it your own.",
                answer: nil,
                tool: .prayerDrafting,
                confidence: 0.6,
                warnings: []
            )
        }
    }
    
    private func executeNotesSummarizer(input: String, context: BereanContext) async -> BereanResponse {
        let prompt = """
        You are Berean, an intelligent Bible study assistant. \
        A user has shared sermon or Bible study notes and wants a summary.
        
        Notes: "\(input)"
        
        Provide a concise summary with:
        1. **Main Themes** (2-3 bullet points)
        2. **Key Scripture References** (list any passages mentioned or implied)
        3. **Core Message** (1-2 sentences capturing the essential teaching)
        4. **Application** (1 practical takeaway)
        
        Be clear, faithful to the content, and biblically accurate. Do not invent information.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .notesSummarizer,
                confidence: 0.88,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "I wasn't able to summarize those notes right now. Please try again in a moment.",
                answer: nil,
                tool: .notesSummarizer,
                confidence: 0.0,
                warnings: [error.localizedDescription]
            )
        }
    }
    
    private func executeSafetyChecker(input: String, policyResults: [PolicyCheck]) -> BereanResponse {
        let warnings = policyResults.filter { !$0.passed }
        
        if warnings.isEmpty {
            return BereanResponse(
                content: "Your post looks good to share!",
                answer: nil,
                tool: .safetyChecker,
                confidence: 0.9,
                warnings: []
            )
        } else {
            let warningMessages = warnings.compactMap { $0.reason }.joined(separator: "\n")
            return BereanResponse(
                content: "A few things to consider:\n\n\(warningMessages)",
                answer: nil,
                tool: .safetyChecker,
                confidence: 0.7,
                warnings: warnings.map { $0.reason ?? "" }
            )
        }
    }
    
    private func executeSearchAssist(input: String, context: BereanContext) -> BereanResponse {
        return BereanResponse(
            content: "Let me help you search for that...",
            answer: nil,
            tool: .searchAssist,
            confidence: 0.8,
            warnings: []
        )
    }
    
    private func executeFirstVisitCoach(input: String) async -> BereanResponse {
        let prompt = """
        You are Berean, a warm and knowledgeable church guide. \
        Someone is preparing to visit a church for the first time and has this question or context: "\(input)"
        
        Provide practical, encouraging guidance covering:
        • What to generally expect at a first visit (arrival, service format, culture)
        • One or two tips for feeling comfortable and welcomed
        • A brief, encouraging Scripture on Christian community (cite the reference)
        
        Keep it warm, practical, and under 150 words. No bullet-point overload.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .firstVisitCoach,
                confidence: 0.85,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "Preparing for your first visit:\n\n• Arrive a few minutes early to get oriented\n• Most churches have a welcome team happy to help\n• You don't need to know anything to belong — come as you are\n\nHebrews 10:25 reminds us not to give up meeting together. You're welcome there!",
                answer: nil,
                tool: .firstVisitCoach,
                confidence: 0.7,
                warnings: []
            )
        }
    }
    
    private func executeVerseContext(input: String) async -> BereanResponse {
        let prompt = """
        You are Berean. Extract any Scripture references from this text and provide brief, \
        helpful context for each (1-2 sentences per verse). If no specific verses are mentioned, \
        identify the main biblical theme and offer a relevant verse.
        
        Text: "\(input)"
        
        Format: For each reference, write: [Reference]: [brief context / meaning]
        Keep it concise — this is a quick context card, not a full study.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .verseContext,
                confidence: 0.9,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "I wasn't able to retrieve verse context right now.",
                answer: nil,
                tool: .verseContext,
                confidence: 0.0,
                warnings: [error.localizedDescription]
            )
        }
    }
    
    private func executePrayerActionCompanion(input: String, context: BereanContext) async -> BereanResponse {
        let prompt = """
        You are Berean, a thoughtful prayer companion. \
        A user has shared a prayer request or prayer: "\(input)"
        
        Help them move from prayer to action with:
        **Prayer Focus**: A one-sentence distillation of the core need being lifted up
        **Scripture**: One relevant verse that speaks to this situation (cite it)
        **Suggested Action**: One concrete, practical step they can take this week — \
        something small and doable that aligns with their prayer
        
        Be warm, specific, and faith-grounded. Avoid generic advice.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .prayerActionCompanion,
                confidence: 0.88,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "I wasn't able to process that prayer right now. Please try again.",
                answer: nil,
                tool: .prayerActionCompanion,
                confidence: 0.0,
                warnings: [error.localizedDescription]
            )
        }
    }
    
    private func executeEncouragementWriter(input: String) async -> BereanResponse {
        let prompt = """
        You are Berean. A user wants to send an encouraging message to someone. Context: "\(input)"
        
        Write a warm, genuine encouragement message (3-5 sentences) that:
        • Acknowledges what the person is going through (based on context)
        • Includes one specific, relevant Scripture verse (cite it inline)
        • Ends with a brief, heartfelt closing
        
        Write in first person as if the user is sending it. \
        Keep it personal and authentic — not a generic template. \
        Do not include "Here's a message:" — just write the message itself.
        """
        
        do {
            let response = try await OpenAIService.shared.sendMessageSync(prompt)
            return BereanResponse(
                content: response,
                answer: nil,
                tool: .encouragementWriter,
                confidence: 0.85,
                warnings: []
            )
        } catch {
            return BereanResponse(
                content: "I'm thinking of you and praying for you during this season. Romans 8:28 reminds us that God works all things together for good for those who love Him. You are not alone in this.",
                answer: nil,
                tool: .encouragementWriter,
                confidence: 0.7,
                warnings: []
            )
        }
    }
    
    // MARK: - Scrupulosity / Repetition Detection

    /// Detects when a user is circling the same salvation/shame concern 3+ times in a
    /// 10-message window — a pattern consistent with religious scrupulosity or OCD.
    ///
    /// When detected, returns a pastoral "pattern-break" response instead of feeding
    /// the loop with another doctrinal answer. Returns nil if no loop detected.
    private func detectScrupulosityLoop(
        input: String,
        session: BereanSession
    ) -> BereanResponse? {
        let lowercased = input.lowercased()

        // Check if the current message matches any scrupulosity keyword
        let currentMatchesKeyword = BereanSafetyPolicy.scrupulosityKeywords.contains { lowercased.contains($0) }
        guard currentMatchesKeyword else { return nil }

        // Count how many of the last 10 user messages also matched a scrupulosity keyword
        let recentUserMessages = session.messages
            .filter { $0.role == .user && !$0.redacted }
            .suffix(10)
            .map { $0.content.lowercased() }

        let repeatCount = recentUserMessages.filter { msgContent in
            BereanSafetyPolicy.scrupulosityKeywords.contains { msgContent.contains($0) }
        }.count

        // Trigger pattern-break after 2 prior matches (3 total including current)
        guard repeatCount >= 2 else { return nil }

        print("🔁 Berean: Scrupulosity loop detected (\(repeatCount + 1) occurrences in last 10 messages)")

        return BereanResponse(
            content: BereanSafetyPolicy.refusal(for: .scrupulosity),
            answer: nil,
            tool: .refusal,
            confidence: 1.0,
            warnings: ["scrupulosity_pattern_detected"]
        )
    }

    // MARK: - Session Management
    
    private func getOrCreateSession(
        id: String?,
        userId: String?,
        context: BereanContext
    ) -> BereanSession {
        if let sessionId = id, let existing = sessions[sessionId] {
            return existing
        }
        
        // Determine retention policy based on context
        let retention: BereanSession.RetentionPolicy = {
            switch context.featureContext {
            case .prayer:
                return .ephemeral  // Don't retain prayers
            case .post:
                return .session    // Keep during session only
            case .notes:
                return .saved      // User's notes are saved
            case .chat:
                return .session
            case .findChurch:
                return .cached
            }
        }()
        
        let session = BereanSession(
            id: id ?? UUID().uuidString,
            userId: userId ?? "anonymous",
            context: context,
            startedAt: Date(),
            messages: [],
            retentionPolicy: retention
        )
        
        sessions[session.id] = session
        activeSession = session
        
        return session
    }
    
    private func updateSession(
        session: BereanSession,
        input: String,
        response: BereanResponse
    ) async {
        var updatedSession = session
        
        // Add user message (potentially redacted)
        let shouldRedact = session.retentionPolicy == .ephemeral
        let userMessage = SessionMessage(
            id: UUID().uuidString,
            content: shouldRedact ? "[Redacted for privacy]" : input,
            role: .user,
            timestamp: Date(),
            redacted: shouldRedact
        )
        updatedSession.messages.append(userMessage)
        
        // Add assistant response
        let assistantMessage = SessionMessage(
            id: UUID().uuidString,
            content: response.content,
            role: .assistant,
            timestamp: Date(),
            redacted: false
        )
        updatedSession.messages.append(assistantMessage)
        
        // Update session
        sessions[session.id] = updatedSession
        activeSession = updatedSession
        
        // Clean up old sessions (keep max 10)
        if sessions.count > 10 {
            let oldestId = sessions.sorted { $0.value.startedAt < $1.value.startedAt }.first?.key
            if let id = oldestId {
                sessions.removeValue(forKey: id)
            }
        }
    }
    
    // MARK: - Response Helpers
    
    private func createRefusalResponse(
        input: String,
        reason: String,
        context: BereanContext
    ) -> BereanResponse {
        return BereanResponse(
            content: reason,
            answer: nil,
            tool: .refusal,
            confidence: 1.0,
            warnings: [reason]
        )
    }
    
    private func createErrorResponse(error: Error, context: BereanContext) -> BereanResponse {
        return BereanResponse(
            content: "I encountered an issue processing your request. Please try again.",
            answer: nil,
            tool: .ragExegesis,
            confidence: 0.0,
            warnings: [error.localizedDescription]
        )
    }
    
    func endSession(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        if activeSession?.id == sessionId {
            activeSession = nil
        }
    }
}

// MARK: - Response Model

struct BereanResponse {
    let content: String
    let answer: BereanAnswer?
    let tool: BereanTool
    let confidence: Double
    let warnings: [String]
}

// MARK: - String Extension for Regex

extension String {
    func contains(Regex pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}
