//
//  ReputationScoringService.swift
//  AMENAPP
//
//  Trust and reputation scoring system
//  Tracks user behavior to determine trustworthiness and unlock features
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Trust Level

enum TrustLevel: String, Codable {
    case new = "new"                    // 0-24 score
    case basic = "basic"                // 25-49 score
    case trusted = "trusted"            // 50-74 score
    case verified = "verified"          // 75-89 score
    case exemplary = "exemplary"        // 90-100 score
    
    var displayName: String {
        switch self {
        case .new: return "New Member"
        case .basic: return "Member"
        case .trusted: return "Trusted Member"
        case .verified: return "Verified Member"
        case .exemplary: return "Exemplary Member"
        }
    }
    
    var badgeColor: String {
        switch self {
        case .new: return "gray"
        case .basic: return "blue"
        case .trusted: return "purple"
        case .verified: return "gold"
        case .exemplary: return "platinum"
        }
    }
    
    init(score: Double) {
        switch score {
        case 0..<25:
            self = .new
        case 25..<50:
            self = .basic
        case 50..<75:
            self = .trusted
        case 75..<90:
            self = .verified
        default:
            self = .exemplary
        }
    }
}

// MARK: - Reputation Score Model

struct ReputationScore: Codable {
    var totalScore: Double = 0.0        // 0-100
    var trustLevel: TrustLevel = .new
    
    // Component scores
    var verificationScore: Double = 0.0     // Email, phone, photo verification
    var engagementScore: Double = 0.0       // Quality interactions
    var communityScore: Double = 0.0        // Helpfulness, kindness
    var consistencyScore: Double = 0.0      // Regular, non-spammy activity
    var moderationScore: Double = 0.0       // Clean record (no violations)
    
    // Tracking
    var lastUpdated: Date = Date()
    var scoreHistory: [ScoreSnapshot] = []
    
    struct ScoreSnapshot: Codable {
        let score: Double
        let date: Date
        let reason: String
    }
}

// MARK: - Reputation Actions

enum ReputationAction {
    // Positive actions
    case emailVerified
    case phoneVerified
    case photoVerified
    case profileCompleted
    case helpfulComment
    case prayedForSomeone
    case attendedChurch
    case completedBibleStudy
    case consistentActivity(days: Int)
    case receivedAmen
    case receivedHelpfulVote
    
    // Negative actions
    case contentFlagged
    case spamDetected
    case harassmentWarning
    case temporaryRestriction
    case permanentBan

    // Sexual content violations (escalating penalties)
    case sexualContentWarning       // First-time: explicit text in post/DM
    case sexualSolicitationStrike   // Advertising sexual services
    case groomingAttemptDetected    // Grooming signal in DM
    case repeatSexualViolation      // 3+ sexual content violations
    
    var scoreChange: Double {
        switch self {
        // Verification (one-time bonuses)
        case .emailVerified: return 10.0
        case .phoneVerified: return 15.0
        case .photoVerified: return 10.0
        case .profileCompleted: return 5.0
            
        // Positive engagement
        case .helpfulComment: return 2.0
        case .prayedForSomeone: return 3.0
        case .attendedChurch: return 5.0
        case .completedBibleStudy: return 4.0
        case .receivedAmen: return 0.5
        case .receivedHelpfulVote: return 1.0
            
        // Consistency bonuses
        case .consistentActivity(let days):
            if days >= 30 { return 10.0 }
            else if days >= 14 { return 5.0 }
            else if days >= 7 { return 2.0 }
            return 0.0
            
        // Negative actions (penalties)
        case .contentFlagged: return -5.0
        case .spamDetected: return -10.0
        case .harassmentWarning: return -15.0
        case .temporaryRestriction: return -20.0
        case .permanentBan: return -100.0

        // Sexual content violations — heavier penalties than generic flags
        case .sexualContentWarning:     return -20.0
        case .sexualSolicitationStrike: return -35.0
        case .groomingAttemptDetected:  return -50.0
        case .repeatSexualViolation:    return -40.0
        }
    }
    
    var description: String {
        switch self {
        case .emailVerified: return "Email verified"
        case .phoneVerified: return "Phone verified"
        case .photoVerified: return "Photo verified"
        case .profileCompleted: return "Profile completed"
        case .helpfulComment: return "Helpful comment"
        case .prayedForSomeone: return "Prayed for someone"
        case .attendedChurch: return "Attended church"
        case .completedBibleStudy: return "Completed Bible study"
        case .consistentActivity(let days): return "\(days) days active"
        case .receivedAmen: return "Received Amen"
        case .receivedHelpfulVote: return "Received helpful vote"
        case .contentFlagged: return "Content flagged"
        case .spamDetected: return "Spam detected"
        case .harassmentWarning: return "Harassment warning"
        case .temporaryRestriction: return "Temporary restriction"
        case .permanentBan: return "Permanent ban"
        case .sexualContentWarning:     return "Sexual content warning"
        case .sexualSolicitationStrike: return "Sexual solicitation strike"
        case .groomingAttemptDetected:  return "Grooming attempt detected"
        case .repeatSexualViolation:    return "Repeat sexual violation"
        }
    }
}

// MARK: - Reputation Scoring Service

@MainActor
class ReputationScoringService: ObservableObject {
    static let shared = ReputationScoringService()
    
    @Published var currentScore: ReputationScore = ReputationScore()
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    private init() {
        Task {
            await loadReputationScore()
        }
    }
    
    // MARK: - Load Score
    
    /// Load reputation score from Firestore
    func loadReputationScore() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Not authenticated - cannot load reputation")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let docRef = db.collection("user_reputation").document(userId)
            let document = try await docRef.getDocument()
            
            if document.exists, let data = document.data() {
                // Parse reputation score
                let score = try Firestore.Decoder().decode(ReputationScore.self, from: data)
                currentScore = score
                print("✅ Loaded reputation score: \(score.totalScore) (\(score.trustLevel.displayName))")
            } else {
                // Initialize new reputation score
                try await initializeReputationScore(userId: userId)
            }
            
        } catch {
            print("❌ Failed to load reputation score: \(error.localizedDescription)")
        }
    }
    
    /// Initialize reputation score for new user
    private func initializeReputationScore(userId: String) async throws {
        var newScore = ReputationScore()
        newScore.totalScore = 0.0
        newScore.trustLevel = .new
        newScore.lastUpdated = Date()
        
        // Save to Firestore
        try await db.collection("user_reputation")
            .document(userId)
            .setData(try Firestore.Encoder().encode(newScore))
        
        currentScore = newScore
        print("✅ Initialized new reputation score")
    }
    
    // MARK: - Update Score
    
    /// Record a reputation action and update score
    func recordAction(_ action: ReputationAction, userId: String? = nil) async {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else {
            print("⚠️ No user ID provided")
            return
        }
        
        print("📊 Recording reputation action: \(action.description) (\(action.scoreChange > 0 ? "+" : "")\(action.scoreChange))")
        
        do {
            let docRef = db.collection("user_reputation").document(targetUserId)
            
            // Get current score
            let document = try await docRef.getDocument()
            var score: ReputationScore
            
            if document.exists, let data = document.data() {
                score = try Firestore.Decoder().decode(ReputationScore.self, from: data)
            } else {
                score = ReputationScore()
            }
            
            // Apply score change
            let oldScore = score.totalScore
            score.totalScore = max(0, min(100, score.totalScore + action.scoreChange))
            score.trustLevel = TrustLevel(score: score.totalScore)
            score.lastUpdated = Date()
            
            // Add to history
            let snapshot = ReputationScore.ScoreSnapshot(
                score: score.totalScore,
                date: Date(),
                reason: action.description
            )
            score.scoreHistory.append(snapshot)
            
            // Keep only last 50 snapshots
            if score.scoreHistory.count > 50 {
                score.scoreHistory = Array(score.scoreHistory.suffix(50))
            }
            
            // Update component scores
            updateComponentScores(&score, action: action)
            
            // Save to Firestore
            try await docRef.setData(try Firestore.Encoder().encode(score))
            
            // Update local state if current user
            if targetUserId == Auth.auth().currentUser?.uid {
                currentScore = score
            }
            
            print("✅ Reputation updated: \(oldScore) → \(score.totalScore) (\(score.trustLevel.displayName))")
            
        } catch {
            print("❌ Failed to update reputation: \(error.localizedDescription)")
        }
    }
    
    /// Update component scores based on action type
    private func updateComponentScores(_ score: inout ReputationScore, action: ReputationAction) {
        switch action {
        case .emailVerified, .phoneVerified, .photoVerified, .profileCompleted:
            score.verificationScore = min(100, score.verificationScore + action.scoreChange)
            
        case .helpfulComment, .receivedAmen, .receivedHelpfulVote:
            score.engagementScore = min(100, score.engagementScore + action.scoreChange)
            
        case .prayedForSomeone, .attendedChurch, .completedBibleStudy:
            score.communityScore = min(100, score.communityScore + action.scoreChange)
            
        case .consistentActivity:
            score.consistencyScore = min(100, score.consistencyScore + action.scoreChange)
            
        case .contentFlagged, .spamDetected, .harassmentWarning, .temporaryRestriction, .permanentBan,
             .sexualContentWarning, .sexualSolicitationStrike, .groomingAttemptDetected, .repeatSexualViolation:
            score.moderationScore = max(0, score.moderationScore + action.scoreChange)
        }
    }
    
    // MARK: - Feature Unlocks
    
    /// Check if user's reputation allows a specific feature
    func hasAccess(to feature: Feature) -> Bool {
        return currentScore.totalScore >= feature.minimumScore
    }
    
    enum Feature {
        case basicMessaging      // 0+ score
        case advancedMessaging   // 25+ score
        case sendMediaInDMs      // 15+ score (+ account age check)
        case sendLinksInDMs      // 20+ score (+ account age check)
        case communityLeader     // 50+ score
        case verifiedBadge       // 75+ score
        case exemplaryBadge      // 90+ score

        var minimumScore: Double {
            switch self {
            case .basicMessaging:   return 0
            case .sendMediaInDMs:   return 15
            case .sendLinksInDMs:   return 20
            case .advancedMessaging: return 25
            case .communityLeader:  return 50
            case .verifiedBadge:    return 75
            case .exemplaryBadge:   return 90
            }
        }

        /// Minimum trust level (complementary to score).
        var minimumTrustLevel: TrustLevel {
            switch self {
            case .basicMessaging:   return .new
            case .sendMediaInDMs:   return .basic
            case .sendLinksInDMs:   return .basic
            case .advancedMessaging: return .basic
            case .communityLeader:  return .trusted
            case .verifiedBadge:    return .verified
            case .exemplaryBadge:   return .exemplary
            }
        }
    }

    /// Whether the user can send media in DMs.
    /// Checks both score and trust level; sexual violations automatically drop
    /// the score below the threshold.
    func canSendMediaInDMs() -> Bool {
        return hasAccess(to: .sendMediaInDMs)
    }

    /// Whether the user can include external links in DMs.
    func canSendLinksInDMs() -> Bool {
        return hasAccess(to: .sendLinksInDMs)
    }
}

// MARK: - Firestore Schema

/*
 user_reputation/{userId}:
 {
   totalScore: number (0-100)
   trustLevel: string ("new", "basic", "trusted", "verified", "exemplary")
   verificationScore: number
   engagementScore: number
   communityScore: number
   consistencyScore: number
   moderationScore: number
   lastUpdated: timestamp
   scoreHistory: [
     { score: number, date: timestamp, reason: string }
   ]
 }
 */
