//
//  ProofOfCareService.swift
//  AMENAPP
//
//  High-level service for accessing and managing Proof of Care scores.
//  Wraps TrustScoringEngine for score computation and provides caching.
//  Used by other services to check care quality thresholds.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProofOfCareService: ObservableObject {
    
    static let shared = ProofOfCareService()
    
    @Published private(set) var currentScore: ProofOfCareScore?
    
    private let db = Firestore.firestore()
    
    // Cache: userId → (score, fetchedAt)
    private var cache: [String: (score: ProofOfCareScore, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600  // 10 minutes
    
    private init() {}
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.proofOfCareEnabled
    }
    
    // MARK: - Get Score
    
    /// Get the current Proof of Care score for a user.
    func getScore(for userId: String) async -> ProofOfCareScore? {
        guard isEnabled else { return nil }
        
        if let cached = cache[userId],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.score
        }
        
        do {
            let doc = try await db.collection("users").document(userId)
                .collection("trust").document("careScore")
                .getDocument()
            
            if let score = try? doc.data(as: ProofOfCareScore.self) {
                cache[userId] = (score, Date())
                if userId == Auth.auth().currentUser?.uid {
                    currentScore = score
                }
                return score
            }
        } catch {
            dlog("[ProofOfCareService] Failed to fetch score: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Check if a user meets a care score threshold.
    func meetsThreshold(_ threshold: Double, userId: String) async -> Bool {
        guard isEnabled else { return true }
        guard let score = await getScore(for: userId) else { return true }
        return score.score >= threshold
    }
    
    /// Trigger a score recomputation for the current user.
    func recompute() async {
        guard isEnabled else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let _ = await TrustScoringEngine.shared.computeScores(userId: userId)
        let _ = await getScore(for: userId)
    }
    
    /// Invalidate cached score.
    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
        if userId == Auth.auth().currentUser?.uid {
            currentScore = nil
        }
    }
    
    /// Clear all cached scores.
    func clearAll() {
        cache.removeAll()
        currentScore = nil
    }
}
