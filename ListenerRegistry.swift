//
//  ListenerRegistry.swift
//  AMENAPP
//
//  P1-5: Global listener deduplication
//  Prevents duplicate Firestore listeners when the same profile is viewed multiple times
//

import Foundation
import FirebaseFirestore

/// P1-5: Global registry to prevent duplicate Firestore listeners
///
/// **Problem Solved:**
/// - Opening same profile twice creates duplicate listeners
/// - Back button → Same profile creates 2 listeners
/// - Wastes bandwidth and can cause inconsistent state
///
/// **How It Works:**
/// - Maintains a global dictionary of active listeners by key
/// - When requesting a listener, returns existing one if available
/// - Automatically cleans up when listener is removed
///
@MainActor
class ListenerRegistry {
    static let shared = ListenerRegistry()
    
    /// Active listeners keyed by identifier (e.g., "profile:{userId}", "followers:{userId}")
    private var activeListeners: [String: ListenerRegistration] = [:]
    
    private init() {}
    
    /// Get existing listener or create new one
    /// - Parameters:
    ///   - key: Unique identifier for this listener (e.g., "profile:userId123")
    ///   - create: Closure to create the listener if it doesn't exist
    /// - Returns: The listener (existing or newly created)
    func getOrCreateListener(
        key: String,
        create: () -> ListenerRegistration
    ) -> ListenerRegistration {
        // Return existing listener if available
        if let existing = activeListeners[key] {
            print("📡 Using existing listener for key: \(key)")
            return existing
        }
        
        // Create new listener
        print("📡 Creating new listener for key: \(key)")
        let listener = create()
        activeListeners[key] = listener
        
        return listener
    }
    
    /// Remove a listener from the registry
    /// - Parameter key: The listener key to remove
    func removeListener(key: String) {
        if let listener = activeListeners[key] {
            listener.remove()
            activeListeners.removeValue(forKey: key)
            print("📡 Removed listener for key: \(key)")
        }
    }
    
    /// Check if a listener exists for a key
    /// - Parameter key: The listener key
    /// - Returns: True if listener exists
    func hasListener(key: String) -> Bool {
        return activeListeners[key] != nil
    }
    
    /// Remove all listeners (useful for cleanup on logout)
    func removeAllListeners() {
        print("📡 Removing all \(activeListeners.count) active listeners")
        
        for (key, listener) in activeListeners {
            listener.remove()
            print("📡 Removed listener: \(key)")
        }
        
        activeListeners.removeAll()
    }
    
    /// Get count of active listeners (for debugging)
    var activeListenerCount: Int {
        return activeListeners.count
    }
    
    /// Get all active listener keys (for debugging)
    var activeListenerKeys: [String] {
        return Array(activeListeners.keys)
    }
}

// MARK: - Convenience Extensions

extension ListenerRegistry {
    /// Convenience method for profile listeners
    func profileListenerKey(userId: String) -> String {
        return "profile:\(userId)"
    }
    
    /// Convenience method for posts listeners
    func postsListenerKey(userId: String) -> String {
        return "posts:\(userId)"
    }
    
    /// Convenience method for follower count listeners
    func followerCountListenerKey(userId: String) -> String {
        return "followerCount:\(userId)"
    }
}
