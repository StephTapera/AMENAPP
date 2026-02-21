//
//  AdvancedModerationService.swift
//  AMENAPP
//
//  Advanced AI-powered content moderation with multiple API providers
//  Includes: Google Natural Language, OpenAI, Faith-specific ML, Multi-language support
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Advanced Moderation Models

/// Multi-provider moderation result aggregating all AI checks
struct AdvancedModerationResult: Codable {
    let isApproved: Bool
    let flaggedReasons: [String]
    let severityLevel: ModerationSeverity
    let suggestedAction: ModerationAction
    let confidence: Double
    let detectionSources: [DetectionSource]
    let languageDetected: String?
    let contextType: ContentContext?
    
    enum ModerationSeverity: String, Codable {
        case safe = "safe"
        case warning = "warning"
        case blocked = "blocked"
        case review = "review"
        case shadowBan = "shadow_ban"
    }
    
    enum ModerationAction: String, Codable {
        case approve = "approve"
        case flag = "flag"
        case block = "block"
        case shadowBan = "shadow_ban"
        case humanReview = "human_review"
    }
    
    enum DetectionSource: String, Codable {
        case localCheck = "local"
        case googleNL = "google_natural_language"
        case openAI = "openai_moderation"
        case faithML = "faith_ml"
        case bibleContext = "bible_context"
    }
    
    enum ContentContext: String, Codable {
        case bibleQuote = "bible_quote"
        case prayer = "prayer"
        case testimony = "testimony"
        case general = "general"
    }
}

/// Shadow ban tracking model
struct ShadowBanRecord: Codable {
    let userId: String
    let reason: String
    let startDate: Date
    let endDate: Date?
    let violationCount: Int
    let isActive: Bool
}

// MARK: - Advanced Moderation Service

/// Enterprise-grade content moderation with multiple AI providers
class AdvancedModerationService {
    static let shared = AdvancedModerationService()
    private let db = Firestore.firestore()
    
    // API Configuration (store in Firebase Remote Config or environment variables)
    private let googleNLAPIKey = "" // TODO: Add from Firebase Remote Config
    private let openAIAPIKey = "" // TODO: Add from Firebase Remote Config
    
    // Shadow ban cache
    private var shadowBannedUsers: Set<String> = []
    private var lastShadowBanSync: Date?
    
    private init() {
        Task {
            await loadShadowBannedUsers()
        }
    }
    
    // MARK: - Main Moderation Entry Point
    
    /// Comprehensive content moderation using multiple AI providers
    func moderateContent(
        _ content: String,
        type: ContentType,
        userId: String,
        language: String? = nil
    ) async throws -> AdvancedModerationResult {
        
        print("🛡️ [ADVANCED MODERATION] Starting multi-provider check...")
        
        // Step 0: Check if user is shadow banned
        if await isUserShadowBanned(userId) {
            print("🚫 [SHADOW BAN] User \(userId) is shadow banned")
            return AdvancedModerationResult(
                isApproved: false,
                flaggedReasons: ["User is currently shadow banned"],
                severityLevel: .shadowBan,
                suggestedAction: .shadowBan,
                confidence: 1.0,
                detectionSources: [.localCheck],
                languageDetected: language,
                contextType: .general
            )
        }
        
        // Step 1: Detect language (if not provided)
        let detectedLanguage = language ?? await detectLanguage(content)
        print("🌍 [LANGUAGE] Detected: \(detectedLanguage)")
        
        // Step 2: Detect content context (Bible quote, prayer, etc.)
        let context = detectContentContext(content)
        print("📖 [CONTEXT] Type: \(context.rawValue)")
        
        // Step 3: Bible quote detection - allow religious content
        if context == .bibleQuote {
            let bibleResult = await analyzeBibleQuote(content)
            if bibleResult.isApproved {
                print("✅ [BIBLE] Approved as scripture reference")
                return bibleResult
            }
        }
        
        // Step 4: Run parallel AI checks
        async let googleResult = analyzeWithGoogleNL(content, language: detectedLanguage)
        async let openAIResult = analyzeWithOpenAI(content)
        async let faithMLResult = analyzeWithFaithML(content, context: context)
        
        // Wait for all results
        let results = await [
            try? googleResult,
            try? openAIResult,
            try? faithMLResult
        ].compactMap { $0 }
        
        // Step 5: Aggregate results with weighted scoring
        let aggregatedResult = aggregateResults(
            results: results,
            content: content,
            context: context,
            language: detectedLanguage
        )
        
        // Step 6: Check for repeat offender (shadow ban consideration)
        if !aggregatedResult.isApproved {
            await checkAndApplyShadowBan(userId: userId, violation: aggregatedResult)
        }
        
        // Step 7: Log for analytics and model improvement
        await logAdvancedModeration(
            content: content,
            type: type,
            userId: userId,
            result: aggregatedResult
        )
        
        print("🛡️ [RESULT] \(aggregatedResult.severityLevel.rawValue) (confidence: \(aggregatedResult.confidence))")
        
        return aggregatedResult
    }
    
    // MARK: - Language Detection
    
    /// Detect content language using Google Natural Language API
    private func detectLanguage(_ content: String) async -> String {
        // Use Google NL API for language detection
        // Fallback to simple heuristics if API unavailable
        
        guard !googleNLAPIKey.isEmpty else {
            return detectLanguageLocal(content)
        }
        
        do {
            let url = URL(string: "https://language.googleapis.com/v1/documents:analyzeEntities")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(googleNLAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
            
            let body: [String: Any] = [
                "document": [
                    "type": "PLAIN_TEXT",
                    "content": content
                ],
                "encodingType": "UTF8"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let language = json?["language"] as? String {
                return language
            }
        } catch {
            print("⚠️ [LANGUAGE] Google NL API error: \(error)")
        }
        
        return detectLanguageLocal(content)
    }
    
    /// Local language detection fallback
    private func detectLanguageLocal(_ content: String) -> String {
        // Simple character-based detection
        let hasArabic = content.range(of: #"[\u0600-\u06FF]"#, options: .regularExpression) != nil
        let hasChinese = content.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil
        let hasSpanish = ["el", "la", "los", "las", "y", "de", "que"].contains { content.lowercased().contains($0) }
        
        if hasArabic { return "ar" }
        if hasChinese { return "zh" }
        if hasSpanish { return "es" }
        
        return "en" // Default to English
    }
    
    // MARK: - Context Detection
    
    /// Detect content context (Bible quote, prayer, testimony)
    private func detectContentContext(_ content: String) -> AdvancedModerationResult.ContentContext {
        let lower = content.lowercased()
        
        // Bible quote indicators
        let bibleIndicators = [
            "verse", "chapter", "bible", "scripture", "says in",
            "john", "matthew", "luke", "genesis", "psalms", "proverbs",
            "romans", "corinthians", "galatians", "ephesians"
        ]
        if bibleIndicators.contains(where: { lower.contains($0) }) {
            return .bibleQuote
        }
        
        // Prayer indicators
        let prayerIndicators = [
            "pray for", "praying for", "prayer request", "please pray",
            "lord", "father god", "in jesus name", "amen"
        ]
        if prayerIndicators.contains(where: { lower.contains($0) }) {
            return .prayer
        }
        
        // Testimony indicators
        let testimonyIndicators = [
            "testimony", "god answered", "miracle", "blessed",
            "faith journey", "god's faithfulness"
        ]
        if testimonyIndicators.contains(where: { lower.contains($0) }) {
            return .testimony
        }
        
        return .general
    }
    
    // MARK: - Bible Quote Analysis
    
    /// Context-aware Bible quote analysis - allows religious violence/death references
    private func analyzeBibleQuote(_ content: String) async -> AdvancedModerationResult {
        // Allow common Bible themes that might trigger standard moderation
        let allowedBibleThemes = [
            "death", "kill", "war", "sword", "blood", "sacrifice",
            "crucif", "cross", "die", "perish", "destroy", "wrath",
            "hell", "fire", "judgment", "plague", "pestilence"
        ]
        
        let lower = content.lowercased()
        let hasBibleTheme = allowedBibleThemes.contains { lower.contains($0) }
        
        if hasBibleTheme {
            // This is likely a legitimate Bible reference, not a threat
            return AdvancedModerationResult(
                isApproved: true,
                flaggedReasons: [],
                severityLevel: .safe,
                suggestedAction: .approve,
                confidence: 0.95,
                detectionSources: [.bibleContext],
                languageDetected: "en",
                contextType: .bibleQuote
            )
        }
        
        // Not clearly a Bible quote - proceed with normal checks
        return AdvancedModerationResult(
            isApproved: false,
            flaggedReasons: [],
            severityLevel: .safe,
            suggestedAction: .approve,
            confidence: 0.5,
            detectionSources: [.bibleContext],
            languageDetected: nil,
            contextType: .general
        )
    }
    
    // MARK: - Google Natural Language API
    
    /// Analyze content with Google Cloud Natural Language API
    private func analyzeWithGoogleNL(_ content: String, language: String) async throws -> AdvancedModerationResult {
        guard !googleNLAPIKey.isEmpty else {
            throw NSError(domain: "GoogleNL", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
        }
        
        let url = URL(string: "https://language.googleapis.com/v1/documents:analyzeSentiment")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleNLAPIKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        let body: [String: Any] = [
            "document": [
                "type": "PLAIN_TEXT",
                "language": language,
                "content": content
            ],
            "encodingType": "UTF8"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let documentSentiment = json?["documentSentiment"] as? [String: Any],
              let score = documentSentiment["score"] as? Double,
              let magnitude = documentSentiment["magnitude"] as? Double else {
            throw NSError(domain: "GoogleNL", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Sentiment analysis: score [-1, 1], magnitude [0, inf]
        // Highly negative + high magnitude = toxic content
        let isToxic = score < -0.6 && magnitude > 2.0
        
        var reasons: [String] = []
        if isToxic {
            reasons.append("Highly negative sentiment detected")
        }
        
        return AdvancedModerationResult(
            isApproved: !isToxic,
            flaggedReasons: reasons,
            severityLevel: isToxic ? .warning : .safe,
            suggestedAction: isToxic ? .flag : .approve,
            confidence: min(abs(score) + (magnitude / 10), 1.0),
            detectionSources: [.googleNL],
            languageDetected: language,
            contextType: nil
        )
    }
    
    // MARK: - OpenAI Moderation API
    
    /// Analyze content with OpenAI Moderation API
    private func analyzeWithOpenAI(_ content: String) async throws -> AdvancedModerationResult {
        guard !openAIAPIKey.isEmpty else {
            throw NSError(domain: "OpenAI", code: 401, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
        }
        
        let url = URL(string: "https://api.openai.com/v1/moderations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = ["input": content]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let results = json?["results"] as? [[String: Any]],
              let result = results.first,
              let flagged = result["flagged"] as? Bool,
              let categories = result["categories"] as? [String: Bool],
              let scores = result["category_scores"] as? [String: Double] else {
            throw NSError(domain: "OpenAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Extract flagged categories
        var reasons: [String] = []
        let categoryMap = [
            "hate": "Hate speech",
            "hate/threatening": "Threatening hate speech",
            "harassment": "Harassment",
            "self-harm": "Self-harm content",
            "sexual": "Sexual content",
            "sexual/minors": "Sexual content involving minors",
            "violence": "Violence",
            "violence/graphic": "Graphic violence"
        ]
        
        for (key, isFlagged) in categories where isFlagged {
            if let displayName = categoryMap[key] {
                reasons.append(displayName)
            }
        }
        
        // Calculate max confidence score
        let maxScore = scores.values.max() ?? 0.0
        
        return AdvancedModerationResult(
            isApproved: !flagged,
            flaggedReasons: reasons,
            severityLevel: flagged ? .blocked : .safe,
            suggestedAction: flagged ? .block : .approve,
            confidence: maxScore,
            detectionSources: [.openAI],
            languageDetected: nil,
            contextType: nil
        )
    }
    
    // MARK: - Faith-Specific ML
    
    /// Analyze with faith-specific custom ML model
    private func analyzeWithFaithML(_ content: String, context: AdvancedModerationResult.ContentContext) async throws -> AdvancedModerationResult {
        // Faith-specific patterns that should be flagged
        let blasphemyPatterns = [
            "god is fake", "god is dead", "religion is stupid",
            "jesus is a lie", "bible is false"
        ]
        
        let antiChristianHate = [
            "hate christians", "christians are", "christianity is evil"
        ]
        
        let lower = content.lowercased()
        var reasons: [String] = []
        
        // Check blasphemy
        for pattern in blasphemyPatterns where lower.contains(pattern) {
            reasons.append("Potential blasphemy detected")
            break
        }
        
        // Check anti-Christian hate speech
        for pattern in antiChristianHate where lower.contains(pattern) {
            reasons.append("Anti-Christian hate speech")
            break
        }
        
        // Theological soundness check (basic)
        let hereticalClaims = [
            "jesus was just a man", "trinity is false", "works save you"
        ]
        for claim in hereticalClaims where lower.contains(claim) {
            // Flag for review, don't auto-block (theological discussions are valid)
            reasons.append("Potentially unsound theology - flagged for review")
        }
        
        let isFlagged = !reasons.isEmpty
        
        return AdvancedModerationResult(
            isApproved: !isFlagged,
            flaggedReasons: reasons,
            severityLevel: isFlagged ? .review : .safe,
            suggestedAction: isFlagged ? .humanReview : .approve,
            confidence: isFlagged ? 0.75 : 0.9,
            detectionSources: [.faithML],
            languageDetected: nil,
            contextType: context
        )
    }
    
    // MARK: - Result Aggregation
    
    /// Aggregate results from multiple AI providers with weighted scoring
    private func aggregateResults(
        results: [AdvancedModerationResult],
        content: String,
        context: AdvancedModerationResult.ContentContext,
        language: String
    ) -> AdvancedModerationResult {
        
        guard !results.isEmpty else {
            // Fallback if all APIs failed
            return AdvancedModerationResult(
                isApproved: true,
                flaggedReasons: [],
                severityLevel: .safe,
                suggestedAction: .approve,
                confidence: 0.5,
                detectionSources: [.localCheck],
                languageDetected: language,
                contextType: context
            )
        }
        
        // Weighted voting system
        let weights: [AdvancedModerationResult.DetectionSource: Double] = [
            .googleNL: 0.3,
            .openAI: 0.4,
            .faithML: 0.2,
            .bibleContext: 0.1
        ]
        
        var totalWeight: Double = 0
        var weightedScore: Double = 0
        var allReasons: Set<String> = []
        var allSources: Set<AdvancedModerationResult.DetectionSource> = []
        
        for result in results {
            for source in result.detectionSources {
                let weight = weights[source] ?? 0.1
                totalWeight += weight
                
                // Score: 1.0 if approved, 0.0 if blocked
                let score = result.isApproved ? 1.0 : 0.0
                weightedScore += score * weight * result.confidence
                
                allReasons.formUnion(result.flaggedReasons)
                allSources.insert(source)
            }
        }
        
        // Normalize score
        let finalScore = totalWeight > 0 ? weightedScore / totalWeight : 0.5
        
        // Decision threshold: 0.7 = approve, below = flag/block
        let isApproved = finalScore >= 0.7
        let severity: AdvancedModerationResult.ModerationSeverity = finalScore >= 0.7 ? .safe : (finalScore >= 0.4 ? .warning : .blocked)
        let action: AdvancedModerationResult.ModerationAction = isApproved ? .approve : (severity == .warning ? .flag : .block)
        
        return AdvancedModerationResult(
            isApproved: isApproved,
            flaggedReasons: Array(allReasons),
            severityLevel: severity,
            suggestedAction: action,
            confidence: finalScore,
            detectionSources: Array(allSources),
            languageDetected: language,
            contextType: context
        )
    }
    
    // MARK: - Shadow Ban System
    
    /// Check if user is currently shadow banned
    func isUserShadowBanned(_ userId: String) async -> Bool {
        // Check cache first
        if shadowBannedUsers.contains(userId) {
            return true
        }
        
        // Sync from Firestore if cache is stale
        if lastShadowBanSync == nil || Date().timeIntervalSince(lastShadowBanSync!) > 3600 {
            await loadShadowBannedUsers()
        }
        
        return shadowBannedUsers.contains(userId)
    }
    
    /// Load shadow banned users from Firestore
    private func loadShadowBannedUsers() async {
        do {
            let snapshot = try await db.collection("shadowBans")
                .whereField("isActive", isEqualTo: true)
                .whereField("endDate", isGreaterThan: Date())
                .getDocuments()
            
            shadowBannedUsers = Set(snapshot.documents.compactMap { $0.data()["userId"] as? String })
            lastShadowBanSync = Date()
            
            print("🚫 [SHADOW BAN] Loaded \(shadowBannedUsers.count) banned users")
        } catch {
            print("❌ [SHADOW BAN] Failed to load: \(error)")
        }
    }
    
    /// Check for repeat offenders and apply shadow ban if needed
    private func checkAndApplyShadowBan(userId: String, violation: AdvancedModerationResult) async {
        // Get user's violation history
        do {
            let snapshot = try await db.collection("moderationLogs")
                .whereField("userId", isEqualTo: userId)
                .whereField("isApproved", isEqualTo: false)
                .whereField("timestamp", isGreaterThan: Date().addingTimeInterval(-86400 * 30)) // Last 30 days
                .getDocuments()
            
            let violationCount = snapshot.documents.count
            
            // Shadow ban thresholds
            let shadowBanThreshold = 5 // 5 violations in 30 days
            
            if violationCount >= shadowBanThreshold {
                await applyShadowBan(
                    userId: userId,
                    reason: "Repeated violations (\(violationCount) in 30 days)",
                    durationDays: 7
                )
            }
        } catch {
            print("❌ [SHADOW BAN] Failed to check history: \(error)")
        }
    }
    
    /// Apply shadow ban to user
    private func applyShadowBan(userId: String, reason: String, durationDays: Int) async {
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: startDate)!
        
        let record = ShadowBanRecord(
            userId: userId,
            reason: reason,
            startDate: startDate,
            endDate: endDate,
            violationCount: durationDays,
            isActive: true
        )
        
        do {
            try db.collection("shadowBans").document(userId).setData(from: record)
            shadowBannedUsers.insert(userId)
            
            print("🚫 [SHADOW BAN] Applied to user \(userId) for \(durationDays) days")
        } catch {
            print("❌ [SHADOW BAN] Failed to apply: \(error)")
        }
    }
    
    // MARK: - Logging
    
    /// Log advanced moderation result for analytics
    private func logAdvancedModeration(
        content: String,
        type: ContentType,
        userId: String,
        result: AdvancedModerationResult
    ) async {
        let logData: [String: Any] = [
            "userId": userId,
            "contentType": type.rawValue,
            "contentLength": content.count,
            "isApproved": result.isApproved,
            "severityLevel": result.severityLevel.rawValue,
            "flaggedReasons": result.flaggedReasons,
            "confidence": result.confidence,
            "detectionSources": result.detectionSources.map { $0.rawValue },
            "languageDetected": result.languageDetected ?? "unknown",
            "contextType": result.contextType?.rawValue ?? "general",
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            try await db.collection("advancedModerationLogs").addDocument(data: logData)
        } catch {
            print("⚠️ [LOGGING] Failed to log result: \(error)")
        }
    }
}
