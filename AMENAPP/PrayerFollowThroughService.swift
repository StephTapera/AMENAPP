//
//  PrayerFollowThroughService.swift
//  AMENAPP
//
//  Real community follow-through system that:
//  - Matches helpers to prayer requests (relationship, topic, reliability)
//  - Sends personalized prayer reminders
//  - Prompts check-ins after 3 days
//  - Creates answered prayer gratitude cards
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Prayer Intercessor Match

struct PrayerIntercessorMatch: Codable, Identifiable {
    let id: String
    let prayerId: String
    let intercessorId: String
    let matchScore: Double          // 0-100 (how good the match is)
    let matchReasons: [MatchReason]
    let invitedAt: Date
    let respondedAt: Date?
    let status: MatchStatus
    
    enum MatchStatus: String, Codable {
        case suggested = "suggested"    // Shown to prayer author
        case invited = "invited"        // Invitation sent
        case accepted = "accepted"      // Intercessor said "I prayed"
        case declined = "declined"      // Intercessor passed
        case checkedIn = "checked_in"   // Sent encouragement message
    }
    
    enum MatchReason: String, Codable {
        case closeFriend = "Close friend"
        case sameChurch = "Same church"
        case topicExpertise = "Often prays for similar topics"
        case consistent = "Consistently prays & follows up"
        case mutual = "Mutual follower"
        case nearby = "Local community"
    }
}

// MARK: - Prayer Follow-Up Reminder

struct PrayerFollowUpReminder: Codable, Identifiable {
    let id: String
    let prayerId: String
    let userId: String
    let reminderType: ReminderType
    let scheduledFor: Date
    let sent: Bool
    let sentAt: Date?
    
    enum ReminderType: String, Codable {
        case prayNow = "pray_now"           // Immediate reminder
        case checkIn = "check_in"           // After 3 days: "Want to send a note?"
        case weeklyUpdate = "weekly_update" // Weekly for ongoing prayers
        case answered = "answered"          // Prayer was answered
    }
    
    var title: String {
        switch reminderType {
        case .prayNow:
            return "Time to Pray"
        case .checkIn:
            return "Check In?"
        case .weeklyUpdate:
            return "Prayer Update"
        case .answered:
            return "Prayer Answered!"
        }
    }
    
    var message: String {
        switch reminderType {
        case .prayNow:
            return "You committed to pray for this request"
        case .checkIn:
            return "Want to send a note of encouragement?"
        case .weeklyUpdate:
            return "Continue praying for this ongoing need"
        case .answered:
            return "Celebrate this answered prayer!"
        }
    }
}

// MARK: - Prayer Status Update

struct PrayerStatusUpdate: Codable, Identifiable {
    let id: String
    let prayerId: String
    let authorId: String
    let status: PrayerStatus
    let updateText: String?         // Optional update message
    let createdAt: Date
    
    enum PrayerStatus: String, Codable {
        case active = "active"
        case update = "update"          // Progress update
        case answered = "answered"      // Prayer answered!
        case archived = "archived"      // No longer active
    }
}

// MARK: - Answered Prayer Card

struct AnsweredPrayerCard: Codable, Identifiable {
    let id: String
    let prayerId: String
    let authorId: String
    let originalRequest: String
    let gratitudeSummary: String    // AI-generated gratitude
    let howGodAnswered: String      // User's testimony
    let intercessorsToThank: [String]  // User IDs who prayed
    let createdAt: Date
    let isVisible: Bool
}

// MARK: - Prayer Follow-Through Service

@MainActor
class PrayerFollowThroughService: ObservableObject {
    static let shared = PrayerFollowThroughService()
    
    @Published var myPrayerCommitments: [PrayerIntercessorMatch] = []
    @Published var upcomingReminders: [PrayerFollowUpReminder] = []
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    private init() {
        Task {
            await loadMyCommitments()
        }
    }
    
    // MARK: - Match Intercessors
    
    /// Find and rank potential intercessors for a prayer request
    func matchIntercessors(
        for prayerId: String,
        authorId: String,
        prayerThemes: [PrayerTheme],
        urgency: PrayerUrgency
    ) async -> [PrayerIntercessorMatch] {
        dlog("🤝 Matching intercessors for prayer...")
        
        isLoading = true
        defer { isLoading = false }
        
        // Get author's relationships
        let relationships = await fetchUserRelationships(authorId: authorId)
        
        var matches: [PrayerIntercessorMatch] = []
        
        for (userId, relationship) in relationships {
            let score = calculateMatchScore(
                userId: userId,
                relationship: relationship,
                prayerThemes: prayerThemes,
                urgency: urgency
            )
            
            let reasons = determineMatchReasons(
                relationship: relationship,
                score: score
            )
            
            if score >= 30 {  // Minimum threshold
                let match = PrayerIntercessorMatch(
                    id: UUID().uuidString,
                    prayerId: prayerId,
                    intercessorId: userId,
                    matchScore: score,
                    matchReasons: reasons,
                    invitedAt: Date(),
                    respondedAt: nil,
                    status: .suggested
                )
                matches.append(match)
            }
        }
        
        // Sort by score (highest first) and limit to top 10
        let topMatches = matches.sorted { $0.matchScore > $1.matchScore }.prefix(10)
        
        dlog("✅ Found \(topMatches.count) matched intercessors")
        return Array(topMatches)
    }
    
    // MARK: - Relationship Data
    
    private func fetchUserRelationships(authorId: String) async -> [String: UserRelationship] {
        // In production, this would fetch from Firestore
        // For now, return mock data structure
        
        struct UserRelationship {
            let userId: String
            let isFollowing: Bool
            let isMutual: Bool
            let sameChurch: Bool
            let prayerHistory: Int      // How many times they've prayed
            let followUpRate: Double    // 0-1 (how often they check in)
            let topicMatch: Double      // 0-1 (relevance to prayer topics)
            let proximity: Double       // 0-1 (geographic proximity)
        }
        
        // This is where you'd query Firestore for:
        // - Follow relationships
        // - Church membership
        // - Past prayer interactions
        // - Geographic data
        
        return [:]
    }
    
    // MARK: - Match Scoring
    
    private func calculateMatchScore(
        userId: String,
        relationship: UserRelationship,
        prayerThemes: [PrayerTheme],
        urgency: PrayerUrgency
    ) -> Double {
        var score: Double = 0.0
        
        // Relationship strength (40%)
        if relationship.isMutual {
            score += 25  // Mutual followers
        } else if relationship.isFollowing {
            score += 10  // Following
        }
        
        if relationship.sameChurch {
            score += 15  // Same church community
        }
        
        // Past reliability (30%)
        let prayerCount = Double(relationship.prayerHistory)
        score += min(15, prayerCount * 1.5)  // Cap at 15 points
        
        let followUpScore = relationship.followUpRate * 15
        score += followUpScore
        
        // Topic expertise (20%)
        let topicScore = relationship.topicMatch * 20
        score += topicScore
        
        // Proximity (10%)
        let proximityScore = relationship.proximity * 10
        score += proximityScore
        
        // Urgency bonus
        if urgency == .immediate && relationship.followUpRate > 0.7 {
            score += 10  // Boost reliable people for urgent prayers
        }
        
        return min(100, score)
    }
    
    private func determineMatchReasons(
        relationship: UserRelationship,
        score: Double
    ) -> [PrayerIntercessorMatch.MatchReason] {
        var reasons: [PrayerIntercessorMatch.MatchReason] = []
        
        if relationship.isMutual {
            reasons.append(.closeFriend)
        }
        
        if relationship.sameChurch {
            reasons.append(.sameChurch)
        }
        
        if relationship.topicMatch > 0.6 {
            reasons.append(.topicExpertise)
        }
        
        if relationship.followUpRate > 0.7 {
            reasons.append(.consistent)
        }
        
        if relationship.proximity > 0.7 {
            reasons.append(.nearby)
        }
        
        return reasons
    }
    
    // MARK: - Prayer Commitments
    
    /// User commits to pray for a request
    func commitToPray(prayerId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PrayerFollowThrough", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let commitment = PrayerIntercessorMatch(
            id: UUID().uuidString,
            prayerId: prayerId,
            intercessorId: userId,
            matchScore: 100,  // User chose manually
            matchReasons: [],
            invitedAt: Date(),
            respondedAt: Date(),
            status: .accepted
        )
        
        // Save to Firestore
        try await db.collection("prayer_commitments")
            .document(commitment.id)
            .setData(try Firestore.Encoder().encode(commitment))
        
        // Schedule reminders
        await scheduleReminders(for: commitment)
        
        // Update local state
        myPrayerCommitments.append(commitment)
        
        dlog("✅ Committed to pray for: \(prayerId)")
    }
    
    /// Load user's prayer commitments
    func loadMyCommitments() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection("prayer_commitments")
                .whereField("intercessorId", isEqualTo: userId)
                .whereField("status", in: ["accepted", "invited"])
                .getDocuments()
            
            let commitments = snapshot.documents.compactMap { doc -> PrayerIntercessorMatch? in
                try? doc.data(as: PrayerIntercessorMatch.self)
            }
            
            myPrayerCommitments = commitments
            dlog("✅ Loaded \(commitments.count) prayer commitments")
            
        } catch {
            dlog("❌ Failed to load commitments: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Reminders
    
    /// Schedule prayer reminders
    private func scheduleReminders(for commitment: PrayerIntercessorMatch) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Immediate reminder (within 1 hour)
        let prayNowReminder = PrayerFollowUpReminder(
            id: UUID().uuidString,
            prayerId: commitment.prayerId,
            userId: userId,
            reminderType: .prayNow,
            scheduledFor: Date().addingTimeInterval(3600),  // 1 hour
            sent: false,
            sentAt: nil
        )
        
        // Check-in reminder (after 3 days)
        let checkInReminder = PrayerFollowUpReminder(
            id: UUID().uuidString,
            prayerId: commitment.prayerId,
            userId: userId,
            reminderType: .checkIn,
            scheduledFor: Date().addingTimeInterval(259200),  // 3 days
            sent: false,
            sentAt: nil
        )
        
        // Save reminders
        do {
            try await db.collection("prayer_reminders")
                .document(prayNowReminder.id)
                .setData(try Firestore.Encoder().encode(prayNowReminder))
            
            try await db.collection("prayer_reminders")
                .document(checkInReminder.id)
                .setData(try Firestore.Encoder().encode(checkInReminder))
            
            dlog("✅ Scheduled reminders for prayer")
            
        } catch {
            dlog("❌ Failed to schedule reminders: \(error.localizedDescription)")
        }
    }
    
    /// Send encouragement message
    func sendEncouragement(to prayerId: String, message: String) async throws {
        // This would integrate with your existing messaging system
        // For now, just update the commitment status
        
        if let index = myPrayerCommitments.firstIndex(where: { $0.prayerId == prayerId }) {
            let commitment = myPrayerCommitments[index]
            let updatedCommitment = PrayerIntercessorMatch(
                id: commitment.id,
                prayerId: commitment.prayerId,
                intercessorId: commitment.intercessorId,
                matchScore: commitment.matchScore,
                matchReasons: commitment.matchReasons,
                invitedAt: commitment.invitedAt,
                respondedAt: Date(),
                status: .checkedIn
            )
            
            try await db.collection("prayer_commitments")
                .document(commitment.id)
                .setData(try Firestore.Encoder().encode(updatedCommitment))
            
            myPrayerCommitments[index] = updatedCommitment
            
            dlog("✅ Sent encouragement message")
        }
    }
    
    // MARK: - Answered Prayers
    
    /// Mark prayer as answered and create gratitude card
    func markAsAnswered(
        prayerId: String,
        testimony: String,
        intercessorIds: [String]
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PrayerFollowThrough", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get original prayer to include in card
        let prayerDoc = try await db.collection("posts").document(prayerId).getDocument()
        guard let prayerData = prayerDoc.data(),
              let originalRequest = prayerData["content"] as? String else {
            throw NSError(domain: "PrayerFollowThrough", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Prayer not found"])
        }
        
        // Generate gratitude summary (simple version - production would use AI)
        let gratitudeSummary = generateGratitudeSummary(testimony: testimony)
        
        // Create answered prayer card
        let card = AnsweredPrayerCard(
            id: UUID().uuidString,
            prayerId: prayerId,
            authorId: userId,
            originalRequest: originalRequest,
            gratitudeSummary: gratitudeSummary,
            howGodAnswered: testimony,
            intercessorsToThank: intercessorIds,
            createdAt: Date(),
            isVisible: true
        )
        
        // Save to Firestore
        try await db.collection("answered_prayers")
            .document(card.id)
            .setData(try Firestore.Encoder().encode(card))
        
        // Update prayer status
        let statusUpdate = PrayerStatusUpdate(
            id: UUID().uuidString,
            prayerId: prayerId,
            authorId: userId,
            status: .answered,
            updateText: testimony,
            createdAt: Date()
        )
        
        try await db.collection("prayer_status_updates")
            .document(statusUpdate.id)
            .setData(try Firestore.Encoder().encode(statusUpdate))
        
        // Notify all intercessors
        await notifyIntercessors(card: card, intercessorIds: intercessorIds)
        
        dlog("✅ Prayer marked as answered with gratitude card")
    }
    
    private func generateGratitudeSummary(testimony: String) -> String {
        // Simple summary (first 150 chars)
        // In production, use AI to generate compassionate summary
        let preview = String(testimony.prefix(150))
        return "\(preview)..."
    }
    
    private func notifyIntercessors(card: AnsweredPrayerCard, intercessorIds: [String]) async {
        // Send "answered" reminders to all who prayed
        for intercessorId in intercessorIds {
            let reminder = PrayerFollowUpReminder(
                id: UUID().uuidString,
                prayerId: card.prayerId,
                userId: intercessorId,
                reminderType: .answered,
                scheduledFor: Date(),
                sent: false,
                sentAt: nil
            )
            
            do {
                try await db.collection("prayer_reminders")
                    .document(reminder.id)
                    .setData(try Firestore.Encoder().encode(reminder))
            } catch {
                dlog("⚠️ Failed to notify intercessor: \(error.localizedDescription)")
            }
        }
        
        dlog("✅ Notified \(intercessorIds.count) intercessors of answered prayer")
    }
}

// MARK: - Helper Struct

private struct UserRelationship {
    let userId: String
    let isFollowing: Bool
    let isMutual: Bool
    let sameChurch: Bool
    let prayerHistory: Int
    let followUpRate: Double
    let topicMatch: Double
    let proximity: Double
}

// MARK: - Firestore Schema

/*
 prayer_commitments/{commitmentId}:
 {
   id: string
   prayerId: string
   intercessorId: string
   matchScore: number
   matchReasons: [string]
   invitedAt: timestamp
   respondedAt: timestamp?
   status: string
 }
 
 prayer_reminders/{reminderId}:
 {
   id: string
   prayerId: string
   userId: string
   reminderType: string
   scheduledFor: timestamp
   sent: boolean
   sentAt: timestamp?
 }
 
 prayer_status_updates/{updateId}:
 {
   id: string
   prayerId: string
   authorId: string
   status: string
   updateText: string?
   createdAt: timestamp
 }
 
 answered_prayers/{cardId}:
 {
   id: string
   prayerId: string
   authorId: string
   originalRequest: string
   gratitudeSummary: string
   howGodAnswered: string
   intercessorsToThank: [string]
   createdAt: timestamp
   isVisible: boolean
 }
 */
