//
//  FirebaseOfflineHelper.swift
//  AMENAPP
//
//  Created by Assistant on 2/4/26.
//

import Foundation
import FirebaseDatabase
import Combine

/// Helper utilities for handling Firebase offline scenarios
@MainActor
class FirebaseOfflineHelper {
    static let shared = FirebaseOfflineHelper()
    
    private init() {}
    
    // MARK: - Safe Query Wrapper
    
    /// Safely query Firebase with automatic offline handling
    /// - Parameters:
    ///   - path: The database path to query
    ///   - cacheKey: Optional key for caching the result
    ///   - defaultValue: Default value to return when offline and no cache exists
    /// - Returns: The database snapshot or nil if offline
    func safeQuery<T>(
        path: String,
        cacheKey: String? = nil,
        defaultValue: T? = nil
    ) async throws -> T? where T: Codable {
        // Check network first
        guard AMENNetworkMonitor.shared.isConnected else {
            print("⚠️ Offline - attempting to use cached value for: \(path)")
            
            if let cacheKey = cacheKey,
               let cached = getCachedValue(key: cacheKey, type: T.self) {
                return cached
            }
            
            return defaultValue
        }
        
        // Attempt Firebase query
        do {
            let ref = Database.database().reference(withPath: path)
            let snapshot = try await ref.getData()
            
            guard let value = snapshot.value else {
                return defaultValue
            }
            
            // Try to decode the value
            let data = try JSONSerialization.data(withJSONObject: value)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            
            // Cache the result
            if let cacheKey = cacheKey {
                cacheValue(decoded, key: cacheKey)
            }
            
            return decoded
        } catch {
            print("❌ Firebase query failed: \(error.localizedDescription)")
            
            // Try cache as fallback
            if let cacheKey = cacheKey,
               let cached = getCachedValue(key: cacheKey, type: T.self) {
                print("✅ Using cached fallback for: \(path)")
                return cached
            }
            
            // Return default value
            return defaultValue
        }
    }
    
    // MARK: - Check Boolean Status (like isSaved)
    
    /// Check if a boolean flag exists in Firebase (e.g., is post saved?)
    /// - Parameters:
    ///   - path: The database path
    ///   - cacheKey: Key for caching
    /// - Returns: Boolean value or cached/default
    func checkBooleanStatus(
        path: String,
        cacheKey: String? = nil
    ) async -> Bool {
        // Check network
        guard AMENNetworkMonitor.shared.isConnected else {
            // Return cached value
            if let cacheKey = cacheKey {
                return UserDefaults.standard.bool(forKey: cacheKey)
            }
            return false
        }
        
        do {
            let ref = Database.database().reference(withPath: path)
            let snapshot = try await ref.getData()
            let exists = snapshot.exists()
            
            // Cache result
            if let cacheKey = cacheKey {
                UserDefaults.standard.set(exists, forKey: cacheKey)
            }
            
            return exists
        } catch {
            print("⚠️ Failed to check status for \(path): \(error.localizedDescription)")
            
            // Fallback to cache
            if let cacheKey = cacheKey {
                return UserDefaults.standard.bool(forKey: cacheKey)
            }
            
            return false
        }
    }
    
    // MARK: - Safe Write with Queuing
    
    /// Safely write to Firebase, queuing if offline
    /// - Parameters:
    ///   - path: Database path
    ///   - value: Value to write
    ///   - queueIfOffline: Whether to queue the write if offline
    func safeWrite(
        path: String,
        value: Any,
        queueIfOffline: Bool = true
    ) async throws {
        // Check network
        guard AMENNetworkMonitor.shared.isConnected else {
            if queueIfOffline {
                print("📥 Queuing write for when online: \(path)")
                OfflineWriteQueue.shared.queue(path: path, value: value)
            } else {
                throw NSError(
                    domain: "FirebaseOfflineHelper",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot write - device is offline"]
                )
            }
            return
        }
        
        // Write to Firebase
        let ref = Database.database().reference(withPath: path)
        try await ref.setValue(value)
        
        print("✅ Successfully wrote to \(path)")
    }
    
    // MARK: - Caching Helpers
    
    private func cacheValue<T: Codable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: "firebase_cache_\(key)")
        } catch {
            print("⚠️ Failed to cache value for key \(key): \(error)")
        }
    }
    
    private func getCachedValue<T: Codable>(key: String, type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: "firebase_cache_\(key)") else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("⚠️ Failed to decode cached value for key \(key): \(error)")
            return nil
        }
    }
    
    func clearCache(key: String) {
        UserDefaults.standard.removeObject(forKey: "firebase_cache_\(key)")
    }
    
    func clearAllCache() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("firebase_cache_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        print("🗑️ Cleared all Firebase cache")
    }
}

// MARK: - Offline Write Queue

@MainActor
class OfflineWriteQueue: ObservableObject {
    static let shared = OfflineWriteQueue()
    
    @Published var pendingWrites: [(path: String, value: Any)] = []
    
    private init() {
        // Observe network changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkStatusChanged),
            name: NSNotification.Name("NetworkStatusChanged"),
            object: nil
        )
    }
    
    func queue(path: String, value: Any) {
        pendingWrites.append((path, value))
        savePendingWrites()
        print("📥 Queued write: \(path) (\(pendingWrites.count) pending)")
    }
    
    @objc private func networkStatusChanged() {
        guard AMENNetworkMonitor.shared.isConnected else { return }
        
        Task {
            await processQueue()
        }
    }
    
    func processQueue() async {
        guard AMENNetworkMonitor.shared.isConnected else {
            print("⚠️ Still offline - cannot process queue")
            return
        }
        
        guard !pendingWrites.isEmpty else { return }
        
        print("📤 Processing \(pendingWrites.count) queued writes...")
        
        let writes = pendingWrites
        pendingWrites.removeAll()
        
        for (path, value) in writes {
            do {
                let ref = Database.database().reference(withPath: path)
                try await ref.setValue(value)
                print("✅ Processed queued write: \(path)")
            } catch {
                print("❌ Failed to process write for \(path): \(error)")
                // Re-queue on failure
                pendingWrites.append((path, value))
            }
        }
        
        savePendingWrites()
    }
    
    private func savePendingWrites() {
        // Save to UserDefaults for persistence across app launches
        let writeData = pendingWrites.map { ["path": $0.path, "value": $0.value] }
        UserDefaults.standard.set(writeData, forKey: "pending_firebase_writes")
    }
    
    private func loadPendingWrites() {
        // Load from UserDefaults
        if let writeData = UserDefaults.standard.array(forKey: "pending_firebase_writes") as? [[String: Any]] {
            pendingWrites = writeData.compactMap { dict in
                guard let path = dict["path"] as? String,
                      let value = dict["value"] else { return nil }
                return (path, value)
            }
        }
    }
}

// MARK: - Usage Examples

/*
 
 // Example 1: Check if post is saved (with automatic caching)
 let isSaved = await FirebaseOfflineHelper.shared.checkBooleanStatus(
     path: "user_saved_posts/\(userId)/\(postId)",
     cacheKey: "saved_\(postId)"
 )
 
 // Example 2: Safe query with type
 struct UserProfile: Codable {
     let name: String
     let email: String
 }
 
 let profile = try? await FirebaseOfflineHelper.shared.safeQuery(
     path: "users/\(userId)/profile",
     cacheKey: "user_profile_\(userId)",
     defaultValue: UserProfile(name: "Guest", email: "")
 )
 
 // Example 3: Safe write (auto-queues if offline)
 try? await FirebaseOfflineHelper.shared.safeWrite(
     path: "posts/\(postId)/likes/\(userId)",
     value: true
 )
 
 // Example 4: Clear cache when needed
 FirebaseOfflineHelper.shared.clearCache(key: "saved_\(postId)")
 
 */
