//
//  NewAccountRestrictionService.swift
//  AMENAPP
//
//  Smart rate limiting and restrictions for new accounts
//  Prevents spam, harassment, and bot abuse while allowing organic growth
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Account Age Tier

enum AccountAgeTier {
    case newborn      // 0-2 days
    case infant       // 3-6 days
    case young        // 7-13 days
    case established  // 14-29 days
    case mature       // 30+ days
    
    init(accountAge: TimeInterval) {
        let days = Int(accountAge / 86400) // seconds to days
        
        switch days {
        case 0...2:
            self = .newborn
        case 3...6:
            self = .infant
        case 7...13:
            self = .young
        case 14...29:
            self = .established
        default:
            self = .mature
        }
    }
    
    var displayName: String {
        switch self {
        case .newborn: return "New Account"
        case .infant: return "Getting Started"
        case .young: return "Growing"
        case .established: return "Established"
        case .mature: return "Trusted"
        }
    }
}

// MARK: - Rate Limit Type

enum RateLimitType {
    case follow
    case comment
    case post
    case dm
    case reaction
    case mediaUpload  // Images/video in posts or DMs
    case linkPost     // External links in posts or DMs

    var displayName: String {
        switch self {
        case .follow:       return "following"
        case .comment:      return "commenting"
        case .post:         return "posting"
        case .dm:           return "messaging"
        case .reaction:     return "reacting"
        case .mediaUpload:  return "media_upload"
        case .linkPost:     return "link_post"
        }
    }
}

// MARK: - Rate Limit Result

struct RateLimitResult {
    let allowed: Bool
    let currentCount: Int
    let limit: Int
    let resetTime: Date
    let message: String?
    let tier: AccountAgeTier
    
    var remainingActions: Int {
        max(0, limit - currentCount)
    }
}

// MARK: - New Account Restriction Service

@MainActor
class NewAccountRestrictionService: ObservableObject {
    static let shared = NewAccountRestrictionService()
    
    private let db = Firestore.firestore()
    @Published var currentUserTier: AccountAgeTier = .mature
    @Published var dailyFollowCount: Int = 0
    @Published var dailyCommentCount: Int = 0
    @Published var dailyPostCount: Int = 0
    @Published var dailyDMCount: Int = 0
    
    // MARK: - Rate Limits by Tier
    
    private let followLimits: [AccountAgeTier: Int] = [
        .newborn: 10,        // 0-2 days: 10 follows/day
        .infant: 20,         // 3-6 days: 20 follows/day
        .young: 30,          // 7-13 days: 30 follows/day
        .established: 50,    // 14-29 days: 50 follows/day
        .mature: 100         // 30+ days: 100 follows/day
    ]
    
    private let commentLimits: [AccountAgeTier: Int] = [
        .newborn: 5,         // 0-2 days: 5 comments/day
        .infant: 10,         // 3-6 days: 10 comments/day
        .young: 20,          // 7-13 days: 20 comments/day
        .established: 50,    // 14-29 days: 50 follows/day
        .mature: 200         // 30+ days: 200 comments/day
    ]
    
    private let postLimits: [AccountAgeTier: Int] = [
        .newborn: 3,         // 0-2 days: 3 posts/day
        .infant: 5,          // 3-6 days: 5 posts/day
        .young: 10,          // 7-13 days: 10 posts/day
        .established: 20,    // 14-29 days: 20 posts/day
        .mature: 50          // 30+ days: 50 posts/day
    ]
    
    private let dmLimits: [AccountAgeTier: Int] = [
        .newborn: 0,         // 0-2 days: No DMs to strangers
        .infant: 3,          // 3-6 days: 3 DMs/day
        .young: 10,          // 7-13 days: 10 DMs/day
        .established: 20,    // 14-29 days: 20 DMs/day
        .mature: 50          // 30+ days: 50 DMs/day
    ]

    /// Media (images/video) upload limits — stricter than DMs.
    /// Newborn and infant accounts cannot upload media at all (anti-CSAM/porn-bot measure).
    private let mediaLimits: [AccountAgeTier: Int] = [
        .newborn: 0,         // 0-2 days: No media uploads
        .infant: 0,          // 3-6 days: No media (profile photo exempt)
        .young: 5,           // 7-13 days: 5 media uploads/day
        .established: 20,    // 14-29 days: 20/day
        .mature: 50          // 30+ days: 50/day
    ]

    /// External link post limits — prevents link-spam and adult-domain promotion.
    private let linkLimits: [AccountAgeTier: Int] = [
        .newborn: 0,         // 0-2 days: No links
        .infant: 0,          // 3-6 days: No links
        .young: 3,           // 7-13 days: 3 links/day
        .established: 10,    // 14-29 days: 10/day
        .mature: 30          // 30+ days: 30/day
    ]
    
    // MARK: - Check Rate Limit
    
    /// Check if user can perform an action based on their account age and current usage
    func checkRateLimit(
        for actionType: RateLimitType,
        userId: String? = nil
    ) async -> RateLimitResult {
        guard let userId = userId ?? Auth.auth().currentUser?.uid else {
            return RateLimitResult(
                allowed: false,
                currentCount: 0,
                limit: 0,
                resetTime: Date(),
                message: "Not authenticated",
                tier: .mature
            )
        }
        
        // Get account age
        let accountAge = await getAccountAge(userId: userId)
        let tier = AccountAgeTier(accountAge: accountAge)
        
        // Get current usage for today
        let todayCount = await getTodayUsageCount(userId: userId, actionType: actionType)
        
        // Get limit for this tier
        let limit = getLimit(for: actionType, tier: tier)
        
        // Check if allowed
        let allowed = todayCount < limit
        
        // Generate user-friendly message
        let message: String? = allowed ? nil : generateLimitMessage(
            actionType: actionType,
            tier: tier,
            limit: limit
        )
        
        return RateLimitResult(
            allowed: allowed,
            currentCount: todayCount,
            limit: limit,
            resetTime: getNextResetTime(),
            message: message,
            tier: tier
        )
    }
    
    // MARK: - Record Action
    
    /// Record that user performed an action (increments count)
    func recordAction(
        _ actionType: RateLimitType,
        userId: String? = nil
    ) async {
        guard let userId = userId ?? Auth.auth().currentUser?.uid else { return }
        
        let today = getTodayKey()
        let actionKey = actionType.displayName
        
        do {
            let docRef = db.collection("user_rate_limits").document(userId)
            
            // Check if the stored date has rolled over to a new day.
            // If so, overwrite (not merge) to clear all yesterday's counts.
            let existing = try await docRef.getDocument()
            let storedDate = existing.data()?["date"] as? String ?? ""
            
            if storedDate != today {
                // New day — write fresh document with count = 1, no merge
                try await docRef.setData([
                    "userId": userId,
                    "date": today,
                    actionKey: 1,
                    "lastUpdated": FieldValue.serverTimestamp()
                ])
            } else {
                // Same day — safe to increment
                try await docRef.setData([
                    "userId": userId,
                    "date": today,
                    actionKey: FieldValue.increment(Int64(1)),
                    "lastUpdated": FieldValue.serverTimestamp()
                ], merge: true)
            }
            
            // Update local state
            await updateLocalCounts(userId: userId)
            
            dlog("✅ Recorded \(actionType.displayName) action for user \(userId)")
        } catch {
            dlog("❌ Failed to record action: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Special Checks
    
    /// Check if new account can DM strangers (non-followers)
    func canDMStrangers(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        guard let userId = userId ?? Auth.auth().currentUser?.uid else {
            return (false, "Not authenticated")
        }
        
        let accountAge = await getAccountAge(userId: userId)
        let tier = AccountAgeTier(accountAge: accountAge)
        
        // Newborn accounts (0-2 days) cannot DM strangers at all
        if tier == .newborn {
            return (false, "New accounts must wait 3 days before messaging users who don't follow them. You can still message your followers!")
        }
        
        // Check rate limit for other tiers
        let result = await checkRateLimit(for: .dm, userId: userId)
        return (result.allowed, result.message)
    }
    
    /// Check if account can comment (with reason)
    func canComment(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        let result = await checkRateLimit(for: .comment, userId: userId)
        return (result.allowed, result.message)
    }
    
    /// Check if account can follow (with reason)
    func canFollow(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        let result = await checkRateLimit(for: .follow, userId: userId)
        return (result.allowed, result.message)
    }

    /// Check if account can post (with reason)
    func canPost(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        let result = await checkRateLimit(for: .post, userId: userId)
        return (result.allowed, result.message)
    }

    /// Check if account can upload media (images/video).
    /// Newborn and infant accounts are blocked entirely.
    func canUploadMedia(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        let result = await checkRateLimit(for: .mediaUpload, userId: userId)
        if !result.allowed && result.limit == 0 {
            return (false, "New accounts must wait a few days before uploading photos or videos. This helps keep AMEN safe.")
        }
        return (result.allowed, result.message)
    }

    /// Check if account can post external links.
    /// Newborn and infant accounts are blocked entirely.
    func canPostLink(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        let result = await checkRateLimit(for: .linkPost, userId: userId)
        if !result.allowed && result.limit == 0 {
            return (false, "New accounts must wait a few days before posting external links.")
        }
        return (result.allowed, result.message)
    }

    /// Check if account can share contact information (phone/email).
    /// Blocked for newborn/infant accounts; warning for young accounts.
    func canShareContactInfo(userId: String? = nil) async -> (allowed: Bool, reason: String?) {
        guard let userId = userId ?? Auth.auth().currentUser?.uid else {
            return (false, "Not authenticated")
        }
        let accountAge = await getAccountAge(userId: userId)
        let tier = AccountAgeTier(accountAge: accountAge)
        switch tier {
        case .newborn, .infant:
            return (false, "New accounts cannot share personal contact information. Build your trust on AMEN first.")
        case .young:
            return (true, "Be careful sharing personal contact information with people you don't know.")
        default:
            return (true, nil)
        }
    }

    // MARK: - Helper Methods
    
    private func getAccountAge(userId: String) async -> TimeInterval {
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            if let createdAt = userDoc.data()?["createdAt"] as? Timestamp {
                let accountCreationDate = createdAt.dateValue()
                return Date().timeIntervalSince(accountCreationDate)
            }
            
            // Fallback: use Firebase Auth creation date
            if let user = Auth.auth().currentUser {
                if let creationDate = user.metadata.creationDate {
                    return Date().timeIntervalSince(creationDate)
                }
            }
            
            // Default: assume mature account if we can't determine
            return TimeInterval(90 * 86400) // 90 days
            
        } catch {
            dlog("⚠️ Could not fetch account age: \(error.localizedDescription)")
            return TimeInterval(90 * 86400) // Default to mature on error (fail open)
        }
    }
    
    private func getTodayUsageCount(userId: String, actionType: RateLimitType) async -> Int {
        let today = getTodayKey()
        
        do {
            let doc = try await db.collection("user_rate_limits").document(userId).getDocument()
            
            guard let data = doc.data(),
                  let dateKey = data["date"] as? String,
                  dateKey == today else {
                // Different day or no data - reset to 0
                return 0
            }
            
            let actionKey = actionType.displayName
            return data[actionKey] as? Int ?? 0
            
        } catch {
            dlog("⚠️ Could not fetch usage count: \(error.localizedDescription)")
            return 0 // Fail open
        }
    }
    
    private func getLimit(for actionType: RateLimitType, tier: AccountAgeTier) -> Int {
        switch actionType {
        case .follow:
            return followLimits[tier] ?? 100
        case .comment:
            return commentLimits[tier] ?? 200
        case .post:
            return postLimits[tier] ?? 50
        case .dm:
            return dmLimits[tier] ?? 50
        case .reaction:
            return 500 // Generous limit for reactions (not age-restricted)
        case .mediaUpload:
            return mediaLimits[tier] ?? 50
        case .linkPost:
            return linkLimits[tier] ?? 30
        }
    }
    
    private func getTodayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func getNextResetTime() -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // Next midnight
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let nextMidnight = calendar.startOfDay(for: tomorrow)
        
        return nextMidnight
    }
    
    private func generateLimitMessage(
        actionType: RateLimitType,
        tier: AccountAgeTier,
        limit: Int
    ) -> String {
        let resetTime = getNextResetTime()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let resetString = formatter.string(from: resetTime)
        
        switch actionType {
        case .follow:
            return "You've reached your daily follow limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        case .comment:
            return "You've reached your daily comment limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        case .post:
            return "You've reached your daily post limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        case .dm:
            if tier == .newborn {
                return "New accounts must wait 3 days before messaging users. You can message your followers!"
            }
            return "You've reached your daily message limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        case .reaction:
            return "You've reached your daily reaction limit. Please try again later."
        case .mediaUpload:
            if tier == .newborn || tier == .infant {
                return "New accounts must wait a few days before uploading media."
            }
            return "You've reached your daily media upload limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        case .linkPost:
            if tier == .newborn || tier == .infant {
                return "New accounts must wait a few days before posting external links."
            }
            return "You've reached your daily link limit (\(limit)) for \(tier.displayName) accounts. Limit resets at \(resetString)."
        }
    }
    
    private func updateLocalCounts(userId: String) async {
        let today = getTodayKey()
        
        do {
            let doc = try await db.collection("user_rate_limits").document(userId).getDocument()
            
            guard let data = doc.data(),
                  let dateKey = data["date"] as? String,
                  dateKey == today else {
                // Reset counts if different day
                dailyFollowCount = 0
                dailyCommentCount = 0
                dailyPostCount = 0
                dailyDMCount = 0
                return
            }
            
            dailyFollowCount = data["following"] as? Int ?? 0
            dailyCommentCount = data["commenting"] as? Int ?? 0
            dailyPostCount = data["posting"] as? Int ?? 0
            dailyDMCount = data["messaging"] as? Int ?? 0
            
        } catch {
            dlog("⚠️ Could not update local counts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load User Tier
    
    /// Load current user's account tier on app launch
    func loadCurrentUserTier() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let accountAge = await getAccountAge(userId: userId)
        currentUserTier = AccountAgeTier(accountAge: accountAge)
        
        await updateLocalCounts(userId: userId)
        
        dlog("✅ User account tier: \(currentUserTier.displayName)")
    }
}

// MARK: - Firestore Schema

/*
 Collection: user_rate_limits/{userId}
 {
   userId: string
   date: string (YYYY-MM-DD)
   following: number
   commenting: number
   posting: number
   messaging: number
   reacting: number
   lastUpdated: timestamp
 }
 
 Note: Document auto-resets when date changes (detected in getTodayUsageCount)
 */
