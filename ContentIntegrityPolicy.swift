//
//  ContentIntegrityPolicy.swift
//  AMENAPP
//
//  Organic Content Integrity + Moderation Policy
//  Production-ready policy architecture with graduated enforcement
//

import Foundation

// MARK: - Content Categories

enum ContentCategory: String, Codable {
    case post = "post"
    case comment = "comment"
    case reply = "reply"
    case profileBio = "profile_bio"
    case caption = "caption"
    case mediaUpload = "media_upload"
    
    var moderationStrictness: ModerationStrictness {
        switch self {
        case .post, .profileBio, .caption:
            return .standard
        case .comment, .reply:
            return .strict  // Comments need stricter anti-spam
        case .mediaUpload:
            return .standard
        }
    }
    
    var maxLengthChars: Int {
        switch self {
        case .post: return 5000
        case .comment, .reply: return 1000
        case .profileBio: return 500
        case .caption: return 2000
        case .mediaUpload: return 0  // N/A
        }
    }
}

enum ModerationStrictness {
    case standard
    case strict
    
    var aiSuspicionThreshold: Double {
        switch self {
        case .standard: return 0.7  // 70% confidence to flag
        case .strict: return 0.5    // 50% confidence to flag comments
        }
    }
    
    var spamThreshold: Double {
        switch self {
        case .standard: return 0.7
        case .strict: return 0.6
        }
    }
}

// MARK: - Content Behaviors

enum ContentBehavior: String, Codable {
    // ✅ Allowed behaviors
    case organicPersonal = "organic_personal"
    case scriptureQuoted = "scripture_quoted"
    case sermonExcerpt = "sermon_excerpt"
    case attributedQuote = "attributed_quote"
    case personalReflection = "personal_reflection"
    
    // ⚠️ Suspicious behaviors
    case largePaste = "large_paste"
    case aiSuspected = "ai_suspected"
    case nearDuplicate = "near_duplicate"
    case rapidPosting = "rapid_posting"
    
    // 🚫 Restricted behaviors
    case spamDetected = "spam_detected"
    case toxicContent = "toxic_content"
    case harassment = "harassment"
    case hateSpeech = "hate_speech"
    case sexualContent = "sexual_content"
    case selfHarm = "self_harm"
    case massGenerated = "mass_generated"
    case repeatedAbuse = "repeated_abuse"
}

// MARK: - Enforcement Ladder

enum ContentIntegrityAction: String, Codable {
    case allow = "allow"
    case nudgeRewrite = "nudge_rewrite"
    case requireRevision = "require_revision"
    case holdForReview = "hold_for_review"
    case rateLimit = "rate_limit"
    case shadowRestrict = "shadow_restrict"  // Down-rank in feeds
    case reject = "reject"
    
    var userFacingMessage: String {
        switch self {
        case .allow:
            return ""
        case .nudgeRewrite:
            return "Consider adding your own reflection or context to make this more personal"
        case .requireRevision:
            return "This content may need some personal touches. Could you share your own thoughts?"
        case .holdForReview:
            return "Your post is being reviewed to ensure it aligns with community guidelines"
        case .rateLimit:
            return "You're posting quite frequently. Take a moment to reflect before sharing more"
        case .shadowRestrict:
            return ""  // Silent action
        case .reject:
            return "This content doesn't meet our community guidelines. Please review and try again"
        }
    }
    
    var isBlocking: Bool {
        switch self {
        case .allow, .nudgeRewrite, .shadowRestrict:
            return false
        case .requireRevision, .holdForReview, .rateLimit, .reject:
            return true
        }
    }
}

// MARK: - Moderation Decision

struct ModerationDecision: Codable {
    let action: ContentIntegrityAction
    let confidence: Double  // 0.0 - 1.0
    let reasons: [String]
    let detectedBehaviors: [ContentBehavior]
    let suggestedRevisions: [String]?
    let reviewRequired: Bool
    let appealable: Bool
    
    // Scoring breakdown (internal only, not shown to user)
    let scores: ModerationScores
    
    var shouldBlock: Bool {
        return action.isBlocking
    }
    
    var userMessage: String {
        return action.userFacingMessage
    }
}

struct ModerationScores: Codable {
    let toxicity: Double           // 0.0 - 1.0
    let spam: Double               // 0.0 - 1.0
    let aiSuspicion: Double        // 0.0 - 1.0
    let duplicateMatch: Double     // 0.0 - 1.0
    let authenticity: Double       // 0.0 - 1.0 (inverse of AI suspicion)
    let userRiskScore: Double      // 0.0 - 1.0 (behavioral signals)
}

// MARK: - Review States

enum ReviewState: String, Codable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case appealed = "appealed"
    case resolved = "resolved"
}

struct ReviewQueueItem: Codable {
    let id: String
    let contentId: String
    let contentType: ContentCategory
    let userId: String
    let contentText: String?
    let contentMediaURLs: [String]?
    let moderationDecision: ModerationDecision
    let state: ReviewState
    let createdAt: Date
    let resolvedAt: Date?
    let resolvedBy: String?  // Admin user ID
    let resolutionNotes: String?
}

// MARK: - Enforcement Ladder Logic

class EnforcementLadder {
    
    /// Determine enforcement action based on moderation scores and user history
    static func determineAction(
        scores: ModerationScores,
        category: ContentCategory,
        userViolationCount: Int,
        recentSimilarContentCount: Int
    ) -> ModerationDecision {
        
        var detectedBehaviors: [ContentBehavior] = []
        var reasons: [String] = []
        var action: ContentIntegrityAction = .allow
        var confidence: Double = 0.0

        // 1. Hard violations (immediate reject)
        if scores.toxicity > 0.8 {
            action = .reject
            confidence = scores.toxicity
            reasons.append("Toxic or harmful content detected")
            detectedBehaviors.append(.toxicContent)
        }
        else if scores.spam > 0.85 {
            action = .reject
            confidence = scores.spam
            reasons.append("Spam content detected")
            detectedBehaviors.append(.spamDetected)
        }

        // 2. AI/Copy-paste suspicion (graduated response)
        else if scores.aiSuspicion > category.moderationStrictness.aiSuspicionThreshold {
            confidence = scores.aiSuspicion

            if scores.aiSuspicion > 0.9 {
                // Very high confidence AI
                action = userViolationCount >= 3 ? .holdForReview : .requireRevision
                reasons.append("Content appears to be AI-generated or copied")
                detectedBehaviors.append(.aiSuspected)
            }
            else if scores.aiSuspicion > 0.7 {
                // Medium-high confidence
                action = userViolationCount >= 2 ? .requireRevision : .nudgeRewrite
                reasons.append("Consider adding personal reflection")
                detectedBehaviors.append(.aiSuspected)
            }
            else {
                // Medium confidence - gentle nudge only
                action = .nudgeRewrite
                reasons.append("Add your own thoughts to make this more meaningful")
                detectedBehaviors.append(.largePaste)
            }
        }

        // 3. Near-duplicate content
        else if scores.duplicateMatch > 0.8 {
            action = recentSimilarContentCount >= 3 ? .rateLimit : .nudgeRewrite
            confidence = scores.duplicateMatch
            reasons.append("Similar content posted recently")
            detectedBehaviors.append(.nearDuplicate)
        }

        // 4. Rapid posting / spam bursts
        else if scores.userRiskScore > 0.7 {
            action = .rateLimit
            confidence = scores.userRiskScore
            reasons.append("Too many posts in a short time")
            detectedBehaviors.append(.rapidPosting)
        }

        // 5. Repeated violations
        else if userViolationCount >= 5 {
            action = .shadowRestrict
            confidence = 1.0
            reasons.append("Repeated content policy violations")
            detectedBehaviors.append(.repeatedAbuse)
        }

        // Generate suggested revisions for non-blocking actions
        let suggestedRevisions: [String]? = action == .nudgeRewrite || action == .requireRevision ? [
            "Add your own reflection or experience",
            "Share how this relates to your faith journey",
            "Include your personal context or story"
        ] : nil

        return ModerationDecision(
            action: action,
            confidence: confidence,
            reasons: reasons,
            detectedBehaviors: detectedBehaviors,
            suggestedRevisions: suggestedRevisions,
            reviewRequired: action == .holdForReview,
            appealable: action == .reject || action == .holdForReview,
            scores: scores
        )
    }
    
    /// Special handling for Scripture/quotes with attribution
    static func isLegitimateQuotedContent(_ text: String) -> Bool {
        let lowerText = text.lowercased()
        
        // Check for Scripture indicators
        let scriptureIndicators = [
            "bible", "scripture", "verse", "psalm", "proverbs", "john", "matthew",
            "corinthians", "romans", "genesis", "exodus", "kjv", "niv", "esv"
        ]
        
        let hasScriptureIndicator = scriptureIndicators.contains { lowerText.contains($0) }
        
        // Check for attribution patterns
        let quoteChar = "\""
        let leftCurlyQuote = "\u{201C}"  // "
        let rightCurlyQuote = "\u{201D}"  // "
        let emDash = "\u{2014}"  // —
        
        let hasQuoteMarks = text.contains(quoteChar) || text.contains(leftCurlyQuote) || text.contains(rightCurlyQuote)
        let hasAttributionIndicators = text.contains("- ") || text.contains(emDash) || 
                                       text.contains("from ") || text.contains("by ") || 
                                       text.contains("according to") || text.contains("pastor") || 
                                       text.contains("sermon")
        let hasAttribution = hasQuoteMarks || hasAttributionIndicators
        
        return hasScriptureIndicator || hasAttribution
    }
}

// MARK: - Allowlist for Legitimate Content

class ContentAllowlist {
    
    static let scriptureBooks = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
        "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
        "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
        "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
        "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John",
        "Jude", "Revelation"
    ]
    
    static func containsScripture(_ text: String) -> Bool {
        return scriptureBooks.contains { text.contains($0) }
    }
}
