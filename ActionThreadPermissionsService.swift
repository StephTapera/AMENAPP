//
//  ActionThreadPermissionsService.swift
//  AMENAPP
//
//  Handles permission checks and trust eligibility for Action Thread operations.
//  Integrates with existing trust infrastructure (NewAccountRestrictionService,
//  EnforcementLadderService, ModerationService).
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActionThreadPermissionsService {
    
    static let shared = ActionThreadPermissionsService()
    private let db = Firestore.firestore()
    private init() {}
    
    // MARK: - Eligibility Check
    
    /// Check if a user meets the trust requirements for a specific action.
    func checkEligibility(
        userId: String,
        constraint: TrustActionConstraint
    ) async -> TrustEligibility {
        let now = Date()
        
        // Check account age
        let accountAgeDays = await getAccountAgeDays(userId: userId)
        if accountAgeDays < constraint.minimumAccountAgeDays {
            return TrustEligibility(
                userId: userId,
                feature: constraint.action,
                isEligible: false,
                reason: "Account must be at least \(constraint.minimumAccountAgeDays) days old",
                humanScoreRequired: constraint.minimumHumanScore,
                careScoreRequired: constraint.minimumCareScore,
                actualHumanScore: 0,
                actualCareScore: 0,
                evaluatedAt: now
            )
        }
        
        // Check enforcement status
        let canPost = await canUserAct(userId: userId)
        if !canPost {
            return TrustEligibility(
                userId: userId,
                feature: constraint.action,
                isEligible: false,
                reason: "Account is currently restricted",
                humanScoreRequired: constraint.minimumHumanScore,
                careScoreRequired: constraint.minimumCareScore,
                actualHumanScore: 0,
                actualCareScore: 0,
                evaluatedAt: now
            )
        }
        
        // If trust signals are enabled, check computed scores
        var actualHuman = 0.5  // Default when trust signals are off
        var actualCare = 0.5
        
        if AMENFeatureFlags.shared.trustSignalsEnabled {
            let scores = await fetchLatestTrustScores(userId: userId)
            actualHuman = scores.human
            actualCare = scores.care
        }
        
        let meetsHuman = actualHuman >= constraint.minimumHumanScore
        let meetsCare = actualCare >= constraint.minimumCareScore
        
        return TrustEligibility(
            userId: userId,
            feature: constraint.action,
            isEligible: meetsHuman && meetsCare,
            reason: meetsHuman && meetsCare ? "Eligible" :
                    !meetsHuman ? "Human authenticity score below threshold" :
                    "Care quality score below threshold",
            humanScoreRequired: constraint.minimumHumanScore,
            careScoreRequired: constraint.minimumCareScore,
            actualHumanScore: actualHuman,
            actualCareScore: actualCare,
            evaluatedAt: now
        )
    }
    
    // MARK: - Thread Permissions
    
    /// Get the effective permissions for a user in a specific thread.
    func getPermissions(
        userId: String,
        threadId: String,
        postId: String
    ) async -> ActionThreadPermissionSet {
        do {
            let participantDoc = try await db.collection("posts").document(postId)
                .collection("actionThreads").document(threadId)
                .collection("participants").document(userId)
                .getDocument()
            
            guard let data = participantDoc.data(),
                  let roleRaw = data["role"] as? String,
                  let role = ActionThreadParticipant.ParticipantRole(rawValue: roleRaw),
                  let statusRaw = data["status"] as? String,
                  statusRaw == "active" || statusRaw == "invited" else {
                return .observerDefaults
            }
            
            switch role {
            case .owner, .coordinator:
                return .ownerDefaults
            case .supporter:
                return .supporterDefaults
            case .observer:
                return .observerDefaults
            }
        } catch {
            return .observerDefaults
        }
    }
    
    // MARK: - Private Helpers
    
    private func getAccountAgeDays(userId: String) async -> Int {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let createdAt = (doc.data()?["createdAt"] as? Timestamp)?.dateValue() else {
                return 0
            }
            return Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        } catch {
            return 0
        }
    }
    
    private func canUserAct(userId: String) async -> Bool {
        do {
            let doc = try await db.collection("user_trust").document(userId).getDocument()
            guard let data = doc.data() else { return true }  // No enforcement record = allowed
            let status = data["accountStatus"] as? String ?? "active"
            return status == "active" || status == "warned"
        } catch {
            return true  // Fail open for non-safety operations
        }
    }
    
    private func fetchLatestTrustScores(userId: String) async -> (human: Double, care: Double) {
        do {
            let humanDoc = try await db.collection("users").document(userId)
                .collection("trust").document("humanScore").getDocument()
            let careDoc = try await db.collection("users").document(userId)
                .collection("trust").document("careScore").getDocument()
            
            let human = humanDoc.data()?["score"] as? Double ?? 0.5
            let care = careDoc.data()?["score"] as? Double ?? 0.5
            return (human, care)
        } catch {
            return (0.5, 0.5)  // Default when unavailable
        }
    }
}
