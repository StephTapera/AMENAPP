//
//  ProofOfHumanService.swift
//  AMENAPP
//
//  High-level service for accessing and managing Proof of Human scores.
//  Wraps TrustScoringEngine for score computation and provides caching.
//  Used by other services to check human authenticity thresholds.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ProofOfHumanService: ObservableObject {
    
    static let shared = ProofOfHumanService()
    
    @Published private(set) var currentScore: ProofOfHumanScore?
    
    private let db = Firestore.firestore()
    
    // Cache: userId → (score, fetchedAt)
    private var cache: [String: (score: ProofOfHumanScore, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600  // 10 minutes
    
    private init() {}
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.proofOfHumanEnabled
    }
    
    // MARK: - Get Score
    
    /// Get the current Proof of Human score for a user.
    /// Returns a cached value if available, otherwise fetches from Firestore.
    func getScore(for userId: String) async -> ProofOfHumanScore? {
        guard isEnabled else { return nil }
        
        // Check cache
        if let cached = cache[userId],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.score
        }
        
        // Fetch from Firestore
        do {
            let doc = try await db.collection("users").document(userId)
                .collection("trust").document("humanScore")
                .getDocument()
            
            if let score = try? doc.data(as: ProofOfHumanScore.self) {
                cache[userId] = (score, Date())
                if userId == Auth.auth().currentUser?.uid {
                    currentScore = score
                }
                return score
            }
        } catch {
            dlog("[ProofOfHumanService] Failed to fetch score: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Check if a user meets a human score threshold.
    func meetsThreshold(_ threshold: Double, userId: String) async -> Bool {
        guard isEnabled else { return true }  // Default to true when disabled
        guard let score = await getScore(for: userId) else { return true }
        return score.score >= threshold
    }
    
    /// Trigger a score recomputation for the current user.
    func recompute() async {
        guard isEnabled else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let _ = await TrustScoringEngine.shared.computeScores(userId: userId)
        // Refresh cached score
        let _ = await getScore(for: userId)
    }
    
    /// Invalidate cached score for a user.
    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
        if userId == Auth.auth().currentUser?.uid {
            currentScore = nil
        }
    }
    
    /// Clear all cached scores (e.g., on sign-out).
    func clearAll() {
        cache.removeAll()
        currentScore = nil
    }
}
