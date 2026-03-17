//
//  HeyFeedPreferencesService.swift
//  AMENAPP
//
//  Manages user preferences for Hey Feed
//  Single source of truth for feed personalization
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class HeyFeedPreferencesService: ObservableObject {
    static let shared = HeyFeedPreferencesService()
    
    @Published var preferences: HeyFeedPreferences = HeyFeedPreferences()
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    private init() {
        loadPreferences()
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Load Preferences
    
    func loadPreferences() {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ HeyFeed: No user ID, using defaults")
            return
        }
        
        isLoading = true
        
        // Real-time listener for preferences
        listener?.remove()
        listener = db.collection("userFeedPrefs")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    
                    if let error = error {
                        dlog("❌ HeyFeed: Error loading preferences: \(error)")
                        return
                    }
                    
                    guard let data = snapshot?.data() else {
                        // No preferences yet - create defaults
                        Task {
                            await self.savePreferences()
                        }
                        return
                    }
                    
                    if let prefs = HeyFeedPreferences.fromDictionary(data) {
                        self.preferences = prefs
                        dlog("✅ HeyFeed: Loaded preferences (mode: \(prefs.mode.rawValue))")
                    }
                }
            }
    }
    
    // MARK: - Save Preferences
    
    func savePreferences() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        preferences.lastUpdated = Date()
        
        do {
            try await db.collection("userFeedPrefs")
                .document(userId)
                .setData(preferences.toDictionary(), merge: true)
            
            dlog("✅ HeyFeed: Saved preferences")
        } catch {
            dlog("❌ HeyFeed: Failed to save preferences: \(error)")
        }
    }
    
    // MARK: - Mode Control
    
    func setMode(_ mode: FeedMode) async {
        preferences.mode = mode
        await savePreferences()
    }
    
    // MARK: - Topic Control
    
    func toggleTopicPin(_ topic: FeedTopic) async {
        if preferences.pinnedTopics.contains(topic) {
            preferences.pinnedTopics.remove(topic)
        } else {
            preferences.pinnedTopics.insert(topic)
            // Remove from blocked if it was blocked
            preferences.blockedTopics.remove(topic)
        }
        await savePreferences()
    }
    
    func blockTopic(_ topic: FeedTopic) async {
        preferences.blockedTopics.insert(topic)
        preferences.pinnedTopics.remove(topic)
        await savePreferences()
    }
    
    func unblockTopic(_ topic: FeedTopic) async {
        preferences.blockedTopics.remove(topic)
        await savePreferences()
    }
    
    // MARK: - Debate & Sensitivity
    
    func setDebateLevel(_ level: DebateLevel) async {
        preferences.debateLevel = level
        await savePreferences()
    }
    
    func setSensitivityFilter(_ filter: SensitivityFilter) async {
        preferences.sensitivityFilter = filter
        await savePreferences()
    }
    
    func setRefreshPacing(_ pacing: RefreshPacing) async {
        preferences.refreshPacing = pacing
        await savePreferences()
    }
    
    // MARK: - Per-Post Actions
    
    func recordMoreLikeThis(postId: String, authorId: String) async {
        preferences.boostedPosts.insert(postId)
        preferences.boostedAuthors.insert(authorId)
        await savePreferences()
        await recordSignal(postId: postId, signalType: .moreLikeThis)
    }
    
    func recordLessLikeThis(postId: String, authorId: String) async {
        // Don't boost this author
        preferences.boostedAuthors.remove(authorId)
        await savePreferences()
        await recordSignal(postId: postId, signalType: .lessLikeThis)
    }
    
    func hidePost(_ postId: String) async {
        preferences.hiddenPosts.insert(postId)
        await savePreferences()
    }
    
    func muteAuthor(_ authorId: String) async {
        preferences.mutedAuthors.insert(authorId)
        preferences.boostedAuthors.remove(authorId)
        await savePreferences()
        
        // Record signal
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let signal = UserFeedSignal(
            userId: userId,
            postId: "author_mute",
            signalType: .muteAuthor,
            timestamp: Date()
        )
        
        do {
            try await db.collection("userFeedSignals")
                .document(userId)
                .collection("signals")
                .addDocument(data: [
                    "userId": signal.userId,
                    "postId": signal.postId,
                    "signalType": signal.signalType.rawValue,
                    "timestamp": Timestamp(date: signal.timestamp),
                    "targetAuthorId": authorId
                ])
        } catch {
            dlog("⚠️ HeyFeed: Failed to record mute signal: \(error)")
        }
    }
    
    func unmuteAuthor(_ authorId: String) async {
        preferences.mutedAuthors.remove(authorId)
        await savePreferences()
    }
    
    // MARK: - Feed Signals
    
    private func recordSignal(postId: String, signalType: UserFeedSignal.SignalType) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let signal = UserFeedSignal(
            userId: userId,
            postId: postId,
            signalType: signalType,
            timestamp: Date()
        )
        
        do {
            try await db.collection("userFeedSignals")
                .document(userId)
                .collection("signals")
                .addDocument(data: [
                    "userId": signal.userId,
                    "postId": signal.postId,
                    "signalType": signal.signalType.rawValue,
                    "timestamp": Timestamp(date: signal.timestamp)
                ])
            
            dlog("✅ HeyFeed: Recorded signal: \(signalType.rawValue)")
        } catch {
            dlog("⚠️ HeyFeed: Failed to record signal: \(error)")
        }
    }
    
    // MARK: - Refresh Control
    
    func canRefresh() -> Bool {
        guard let lastRefresh = lastRefreshTime else {
            lastRefreshTime = Date()
            return true
        }
        
        let elapsed = Date().timeIntervalSince(lastRefresh)
        let canRefresh = elapsed >= preferences.refreshPacing.minimumRefreshInterval
        
        if canRefresh {
            lastRefreshTime = Date()
        }
        
        return canRefresh
    }
    
    // MARK: - Helpers
    
    func isAuthorMuted(_ authorId: String) -> Bool {
        return preferences.mutedAuthors.contains(authorId)
    }
    
    func isPostHidden(_ postId: String) -> Bool {
        return preferences.hiddenPosts.contains(postId)
    }
    
    func isTopicBlocked(_ topic: FeedTopic) -> Bool {
        return preferences.blockedTopics.contains(topic)
    }
    
    func getTopicWeight(_ topic: FeedTopic) -> Double {
        if preferences.pinnedTopics.contains(topic) {
            return 2.0  // 2x boost for pinned topics
        } else if preferences.blockedTopics.contains(topic) {
            return 0.0  // Fully suppress blocked topics
        } else {
            return 1.0  // Neutral
        }
    }
    
    func shouldShowPost(_ post: Post, safetyMetadata: PostSafetyMetadata?) -> Bool {
        // Hidden posts
        if isPostHidden(post.firebaseId ?? post.id.uuidString) {
            return false
        }
        
        // Muted authors
        if isAuthorMuted(post.authorId) {
            return false
        }
        
        // Safety filter
        if let safety = safetyMetadata {
            if safety.riskScore > preferences.sensitivityFilter.riskThreshold {
                return false
            }
        }
        
        return true
    }
}
