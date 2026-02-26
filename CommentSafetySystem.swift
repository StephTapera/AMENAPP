//
//  CommentSafetySystem.swift
//  AMENAPP
//
//  World-Class Comment Safety System
//  Real-time checks, pile-on detection, harassment prevention, smart nudges
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Comment Safety System

/// Fast, smart, safe comment moderation system
/// Prevents harassment, pile-ons, toxicity while maintaining low latency
class CommentSafetySystem {
    static let shared = CommentSafetySystem()
    
    private let db = Firestore.firestore()
    private let moderationService = ContentModerationService.self
    
    // MARK: - Safety Check Result
    
    struct SafetyCheckResult {
        let action: EnforcementAction
        let violations: [PolicyViolation]
        let confidence: Double
        let userMessage: String?
        let suggestedRevisions: [String]?
        let cooldownSeconds: Int?
        let requiresRevision: Bool
        
        var isBlocked: Bool {
            return action.isBlocking
        }
        
        var canPostWithWarning: Bool {
            return action == .warnAndAllow || action == .nudgeOnly
        }
    }
    
    // MARK: - Main Safety Check (Pre-Submit)
    
    /// Fast safety check before comment is submitted
    /// Runs multiple checks in parallel for speed
    func checkCommentSafety(
        content: String,
        postId: String,
        postAuthorId: String,
        commenterId: String,
        parentCommentId: String? = nil
    ) async throws -> SafetyCheckResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // PARALLEL CHECKS for speed
        async let toxicityCheck = checkToxicity(content: content)
        async let pileOnCheck = checkPileOn(
            postId: postId,
            postAuthorId: postAuthorId,
            commenterId: commenterId
        )
        async let repeatHarassmentCheck = checkRepeatHarassment(
            commenterId: commenterId,
            targetUserId: postAuthorId
        )
        async let spamCheck = checkSpam(
            commenterId: commenterId,
            content: content
        )
        async let rateCheck = checkRateLimit(
            commenterId: commenterId
        )
        
        // Wait for all checks
        let (toxicity, pileOn, repeatHarassment, spam, rateLimit) = try await (
            toxicityCheck,
            pileOnCheck,
            repeatHarassmentCheck,
            spamCheck,
            rateCheck
        )
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("⚡️ [SAFETY] All checks completed in \(String(format: "%.0f", elapsed))ms")
        
        // AGGREGATE RESULTS
        var violations: [PolicyViolation] = []
        var highestSeverity: ViolationSeverity = .light
        var maxConfidence: Double = 0.0
        var suggestedRevisions: [String] = []
        
        // Toxicity violations
        if let toxicViolation = toxicity.violation {
            violations.append(toxicViolation)
            highestSeverity = max(highestSeverity, toxicViolation.severity)
            maxConfidence = max(maxConfidence, toxicity.confidence)
            if let suggestions = toxicity.suggestions {
                suggestedRevisions.append(contentsOf: suggestions)
            }
        }
        
        // Pile-on violations
        if pileOn.isPileOn {
            violations.append(.targetedBullying)
            highestSeverity = max(highestSeverity, .severe)
            suggestedRevisions.append("This user is receiving many comments. Consider giving them space.")
        }
        
        // Repeat harassment
        if repeatHarassment.isRepeatOffender {
            violations.append(.harassment)
            highestSeverity = max(highestSeverity, .severe)
            suggestedRevisions.append("You've interacted with this user multiple times. Please be respectful.")
        }
        
        // Spam
        if spam.isSpam {
            violations.append(.spam)
            highestSeverity = max(highestSeverity, .moderate)
        }
        
        // Rate limit
        if rateLimit.isLimited {
            return SafetyCheckResult(
                action: .temporaryDelay,
                violations: [],
                confidence: 1.0,
                userMessage: "You're commenting very quickly. Please take a moment before continuing.",
                suggestedRevisions: nil,
                cooldownSeconds: rateLimit.cooldownSeconds,
                requiresRevision: false
            )
        }
        
        // DETERMINE ACTION
        let context = PolicyContext(
            userId: commenterId,
            targetUserId: postAuthorId,
            contentType: .comment,
            previousViolations: repeatHarassment.violationHistory,
            recentActivityCount: spam.recentCommentCount,
            isRepeatTarget: repeatHarassment.isRepeatOffender,
            targetReportedUser: repeatHarassment.hasBeenReportedByTarget,
            communityReports: 0,  // Would come from reports table
            createdAt: Date()
        )
        
        let action: EnforcementAction
        let userMessage: String?
        let requiresRevision: Bool
        
        if violations.isEmpty {
            // All clear
            action = .allow
            userMessage = nil
            requiresRevision = false
        } else if highestSeverity == .critical {
            // Critical violations - immediate block
            action = .blockAndEscalate
            userMessage = violations.first?.userFacingMessage
            requiresRevision = false
        } else if highestSeverity == .severe {
            // Severe violations - context-aware action
            if context.shouldEscalate(for: violations.first!) {
                action = .blockAndEscalate
                userMessage = violations.first?.userFacingMessage
                requiresRevision = false
            } else {
                action = .requireRevision
                userMessage = violations.first?.userFacingMessage
                requiresRevision = true
            }
        } else if highestSeverity == .moderate {
            // Moderate violations - warn or require revision
            if maxConfidence > 0.85 {
                action = .requireRevision
                userMessage = "Want to rephrase this more constructively?"
                requiresRevision = true
            } else {
                action = .warnAndAllow
                userMessage = "This language may come across negatively. Consider rephrasing."
                requiresRevision = false
            }
        } else {
            // Light violations - nudge only
            action = .nudgeOnly
            userMessage = violations.first?.userFacingMessage
            requiresRevision = false
        }
        
        return SafetyCheckResult(
            action: action,
            violations: violations,
            confidence: maxConfidence,
            userMessage: userMessage,
            suggestedRevisions: suggestedRevisions.isEmpty ? nil : suggestedRevisions,
            cooldownSeconds: nil,
            requiresRevision: requiresRevision
        )
    }
    
    // MARK: - Toxicity Detection
    
    struct ToxicityResult {
        let violation: PolicyViolation?
        let confidence: Double
        let suggestions: [String]?
    }
    
    private func checkToxicity(content: String) async throws -> ToxicityResult {
        // Fast client-side checks first (no network)
        if let quickViolation = detectObviousToxicity(content) {
            return ToxicityResult(
                violation: quickViolation,
                confidence: 0.95,
                suggestions: ["Consider using kinder language", "Focus on the idea, not the person"]
            )
        }
        
        // If not obviously toxic, defer to full AI moderation
        // (This would be called as part of the full moderation pipeline)
        return ToxicityResult(
            violation: nil,
            confidence: 0.0,
            suggestions: nil
        )
    }
    
    /// Fast client-side toxicity detection (no network call)
    private func detectObviousToxicity(_ content: String) -> PolicyViolation? {
        let lower = content.lowercased()
        
        // Personal attacks - detect insulting patterns
        let personalAttackPatterns = [
            "you're stupid", "you're an idiot", "you're dumb", "you're ugly",
            "you suck", "you're trash", "you're pathetic", "you're worthless",
            "shut up", "nobody likes you", "everyone hates you", "you're fake",
            "fake christian", "hypocrite", "liar", "moron", "loser"
        ]
        
        for pattern in personalAttackPatterns {
            if lower.contains(pattern) {
                return .personalAttacks
            }
        }
        
        // Hostile language - aggressive/threatening patterns
        let hostilePatterns = [
            "i hate you", "i hope you", "you deserve", "you should die",
            "kill yourself", "go to hell", "you're going to hell"
        ]
        
        for pattern in hostilePatterns {
            if lower.contains(pattern) {
                if pattern.contains("kill") || pattern.contains("die") {
                    return .threatOfViolence
                }
                return .hostileLanguage
            }
        }
        
        // Excessive caps (yelling)
        let uppercaseCount = content.filter { $0.isUppercase }.count
        if Double(uppercaseCount) / Double(content.count) > 0.7 && content.count > 20 {
            return .hostileLanguage
        }
        
        return nil
    }
    
    // MARK: - Pile-On Detection
    
    struct PileOnResult {
        let isPileOn: Bool
        let commentCount: Int
        let negativeCommentCount: Int
        let timeWindow: TimeInterval
    }
    
    /// Detect if a post/user is being pile-on attacked
    private func checkPileOn(
        postId: String,
        postAuthorId: String,
        commenterId: String
    ) async throws -> PileOnResult {
        
        // Query recent comments on this post (last 1 hour)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        
        let recentComments = try await db
            .collection("postInteractions")
            .document(postId)
            .collection("comments")
            .whereField("createdAt", isGreaterThan: Timestamp(date: oneHourAgo))
            .getDocuments()
        
        let totalCount = recentComments.documents.count
        
        // Count potentially negative comments (would need sentiment analysis)
        // For now, use heuristics: short comments, multiple from same users, high frequency
        var negativeCount = 0
        var commenterIds = Set<String>()
        
        for doc in recentComments.documents {
            if let authorId = doc.data()["authorId"] as? String {
                commenterIds.insert(authorId)
            }
            
            // Simple heuristic: very short comments (<10 chars) often negative
            if let content = doc.data()["content"] as? String, content.count < 10 {
                negativeCount += 1
            }
        }
        
        // PILE-ON THRESHOLDS
        // - 10+ comments in 1 hour = potential pile-on
        // - 5+ unique commenters + high frequency = coordinated
        // - High ratio of short/negative comments = attack
        
        let isPileOn = (
            totalCount >= 10 ||
            (commenterIds.count >= 5 && totalCount >= 8) ||
            (Double(negativeCount) / Double(max(totalCount, 1)) > 0.6 && totalCount >= 5)
        )
        
        if isPileOn {
            print("🚨 [PILE-ON DETECTED] Post: \(postId), Comments: \(totalCount), Unique: \(commenterIds.count)")
        }
        
        return PileOnResult(
            isPileOn: isPileOn,
            commentCount: totalCount,
            negativeCommentCount: negativeCount,
            timeWindow: 3600
        )
    }
    
    // MARK: - Repeat Harassment Detection
    
    struct RepeatHarassmentResult {
        let isRepeatOffender: Bool
        let interactionCount: Int
        let violationHistory: [PolicyViolation]
        let hasBeenReportedByTarget: Bool
    }
    
    /// Check if user has repeatedly harassed same target
    private func checkRepeatHarassment(
        commenterId: String,
        targetUserId: String
    ) async throws -> RepeatHarassmentResult {
        
        // Query user's comment history targeting this person (last 7 days)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        
        // Query posts by target user
        let targetPosts = try await db
            .collection("posts")
            .whereField("authorId", isEqualTo: targetUserId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .limit(to: 50)
            .getDocuments()
        
        var interactionCount = 0
        var violations: [PolicyViolation] = []
        
        // Count comments by commenter on target's posts
        for postDoc in targetPosts.documents {
            let postId = postDoc.documentID
            
            let commenterComments = try await db
                .collection("postInteractions")
                .document(postId)
                .collection("comments")
                .whereField("authorId", isEqualTo: commenterId)
                .getDocuments()
            
            interactionCount += commenterComments.documents.count
            
            // Check for past violations
            for commentDoc in commenterComments.documents {
                if let moderationFlags = commentDoc.data()["moderationFlags"] as? [String] {
                    for flag in moderationFlags {
                        if let violation = PolicyViolation(rawValue: flag) {
                            violations.append(violation)
                        }
                    }
                }
            }
        }
        
        // Check if target has reported commenter
        let hasReport = try await checkUserReport(
            reporterId: targetUserId,
            reportedUserId: commenterId
        )
        
        // REPEAT OFFENDER THRESHOLDS
        // - 5+ interactions with same person in 7 days = potential pattern
        // - 3+ interactions + past violations = harassment
        // - Target reported user = escalate
        
        let isRepeatOffender = (
            interactionCount >= 5 ||
            (interactionCount >= 3 && !violations.isEmpty) ||
            (hasReport && interactionCount >= 2)
        )
        
        if isRepeatOffender {
            print("🚨 [REPEAT HARASSMENT] Commenter: \(commenterId), Target: \(targetUserId), Interactions: \(interactionCount)")
        }
        
        return RepeatHarassmentResult(
            isRepeatOffender: isRepeatOffender,
            interactionCount: interactionCount,
            violationHistory: violations,
            hasBeenReportedByTarget: hasReport
        )
    }
    
    private func checkUserReport(reporterId: String, reportedUserId: String) async throws -> Bool {
        let reports = try await db
            .collection("userReports")
            .whereField("reporterId", isEqualTo: reporterId)
            .whereField("reportedUserId", isEqualTo: reportedUserId)
            .limit(to: 1)
            .getDocuments()
        
        return !reports.documents.isEmpty
    }
    
    // MARK: - Spam Detection
    
    struct SpamResult {
        let isSpam: Bool
        let reason: String?
        let recentCommentCount: Int
    }
    
    private func checkSpam(commenterId: String, content: String) async throws -> SpamResult {
        // Check for duplicate/near-duplicate content
        let contentHash = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Query user's recent comments (last 1 hour)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        
        // Note: This would ideally be a more efficient query
        // For now, simplified version
        let recentCommentCount = try await getUserRecentCommentCount(
            userId: commenterId,
            since: oneHourAgo
        )
        
        // SPAM THRESHOLDS
        // - 20+ comments in 1 hour = spam burst
        // - Very short generic comments repeated
        
        if recentCommentCount > 20 {
            return SpamResult(
                isSpam: true,
                reason: "Too many comments in short time",
                recentCommentCount: recentCommentCount
            )
        }
        
        // Check for generic spam patterns
        let spamPatterns = [
            "click here", "free", "winner", "congratulations",
            "dm me", "check my bio", "link in bio"
        ]
        
        for pattern in spamPatterns {
            if contentHash.contains(pattern) {
                return SpamResult(
                    isSpam: true,
                    reason: "Spam pattern detected",
                    recentCommentCount: recentCommentCount
                )
            }
        }
        
        return SpamResult(
            isSpam: false,
            reason: nil,
            recentCommentCount: recentCommentCount
        )
    }
    
    private func getUserRecentCommentCount(userId: String, since: Date) async throws -> Int {
        // This would need a better indexing strategy in production
        // For now, return estimated count
        // TODO: Implement efficient user activity tracking
        return 0
    }
    
    // MARK: - Rate Limiting
    
    struct RateLimitResult {
        let isLimited: Bool
        let cooldownSeconds: Int
        let recentActivityCount: Int
    }
    
    private func checkRateLimit(commenterId: String) async throws -> RateLimitResult {
        // Check comment rate limit (already implemented in ComposerRateLimiter)
        let rateLimiter = ComposerRateLimiter.shared
        
        let isLimited = rateLimiter.isRateLimited(for: .comment)
        let remaining = rateLimiter.getRemainingPosts(for: .comment)
        
        if isLimited {
            return RateLimitResult(
                isLimited: true,
                cooldownSeconds: 300,  // 5 minutes
                recentActivityCount: 10 - remaining
            )
        }
        
        return RateLimitResult(
            isLimited: false,
            cooldownSeconds: 0,
            recentActivityCount: 10 - remaining
        )
    }
    
    // MARK: - Post-Submit Async Checks
    
    /// Deeper analysis after comment is posted (async, doesn't block UI)
    func asyncDeepCheck(
        commentId: String,
        content: String,
        postId: String,
        commenterId: String
    ) async {
        // This runs AFTER comment is posted for deeper analysis
        // Can flag content for review without blocking initial submission
        
        do {
            // Run full AI moderation
            let signals = AuthenticitySignals(
                typedCharacters: content.count,
                pastedCharacters: 0,
                typedVsPastedRatio: 1.0,
                largestPasteLength: 0,
                pasteEventCount: 0,
                typingDurationSeconds: 0,
                hasLargePaste: false
            )
            
            let decision = try await ContentModerationService.moderateContent(
                text: content,
                category: .comment,
                signals: signals,
                parentContentId: postId
            )
            
            if decision.shouldBlock {
                print("🚨 [ASYNC CHECK] Comment \(commentId) flagged for review: \(decision.reasons.joined(separator: ", "))")
                
                // Flag for review (don't delete immediately to avoid race conditions)
                try await db
                    .collection("postInteractions")
                    .document(postId)
                    .collection("comments")
                    .document(commentId)
                    .updateData([
                        "moderationFlags": decision.reasons,
                        "moderationConfidence": decision.confidence,
                        "flaggedForReview": true,
                        "flaggedAt": Timestamp(date: Date())
                    ])
            }
        } catch {
            print("⚠️ [ASYNC CHECK] Failed: \(error)")
        }
    }
    
    // MARK: - Pile-On Protection Actions
    
    /// Apply pile-on protection when detected
    func applyPileOnProtection(postId: String, authorId: String) async throws {
        // Temporarily slow down comments on this post
        try await db
            .collection("posts")
            .document(postId)
            .updateData([
                "pileOnProtectionActive": true,
                "pileOnProtectionStarted": Timestamp(date: Date()),
                "commentCooldown": 60  // 60 seconds between comments
            ])
        
        print("🛡️ [PILE-ON PROTECTION] Activated for post: \(postId)")
        
        // TODO: Notify post author via NotificationService
        // try await NotificationService.shared.sendSystemNotification(
        //     to: authorId,
        //     title: "We're here for you",
        //     body: "We've noticed increased activity on your post and are monitoring for supportive conversation.",
        //     data: ["type": "pile_on_protection", "postId": postId]
        // )
    }
}

// MARK: - Safety UI Helpers

extension CommentSafetySystem {
    
    /// Get user-friendly message for safety check result
    func getUserFriendlyMessage(for result: SafetyCheckResult) -> String {
        if let userMessage = result.userMessage {
            return userMessage
        }
        
        switch result.action {
        case .allow:
            return ""
        case .nudgeOnly:
            return "Consider rephrasing to keep the conversation constructive."
        case .warnAndAllow:
            return "This comment may come across negatively. Want to revise?"
        case .requireRevision:
            return "Please revise this comment to align with our community guidelines."
        case .temporaryDelay:
            return "You're commenting very quickly. Please take a \(result.cooldownSeconds ?? 300) second break."
        case .blockAndReview, .blockAndEscalate:
            return result.violations.first?.userFacingMessage ?? "This comment violates our community guidelines."
        default:
            return "This comment couldn't be posted. Please review our community guidelines."
        }
    }
    
    /// Get suggested revisions for user
    func getSuggestedRevisions(for result: SafetyCheckResult) -> [String] {
        if let suggestions = result.suggestedRevisions {
            return suggestions
        }
        
        // Default suggestions based on violation type
        if let firstViolation = result.violations.first {
            switch firstViolation {
            case .personalAttacks, .hostileLanguage:
                return [
                    "Focus on the idea, not the person",
                    "Use 'I' statements instead of 'you' accusations",
                    "Share your perspective respectfully"
                ]
            case .harassment, .targetedBullying:
                return [
                    "Express disagreement without targeting the person",
                    "Take a break if you're feeling frustrated",
                    "Remember there's a real person on the other side"
                ]
            case .spam:
                return [
                    "Share meaningful thoughts instead of generic messages",
                    "Add value to the conversation"
                ]
            default:
                return ["Rephrase to align with community guidelines"]
            }
        }
        
        return []
    }
}
