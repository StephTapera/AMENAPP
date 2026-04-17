//
//  MessageSettingsService.swift
//  AMENAPP
//
//  Service for managing message settings with Firestore persistence
//  Handles CRUD, validation, defaults, and integration with messaging logic
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class MessageSettingsService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MessageSettingsService()
    
    // MARK: - Published Properties
    
    @Published private(set) var settings: MessageSettings
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - Private Properties
    
    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var settingsCache: [String: MessageSettings] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Start with defaults
        self.settings = MessageSettings.defaultSettings()
    }
    
    // MARK: - Firestore Path
    
    private func settingsPath(for userId: String) -> DocumentReference {
        return db.collection("users").document(userId).collection("settings").document("messaging")
    }
    
    // MARK: - Load Settings
    
    func loadSettings(for userId: String? = nil) async throws {
        guard let uid = userId ?? Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageSettings", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        isLoading = true
        error = nil
        
        do {
            let document = try await settingsPath(for: uid).getDocument()
            
            if document.exists, let data = document.data() {
                // Decode from Firestore
                let decoder = Firestore.Decoder()
                var loadedSettings = try decoder.decode(MessageSettings.self, from: data)
                loadedSettings = loadedSettings.validated()
                
                self.settings = loadedSettings
                settingsCache[uid] = loadedSettings
                
                dlog("📱 [MessageSettings] Loaded settings for user \(uid)")
            } else {
                // No settings exist, use defaults
                let isMinor = try await checkIfMinor(userId: uid)
                let defaultSettings = MessageSettings.defaultSettings(isMinor: isMinor)
                
                // Save defaults to Firestore
                try await saveSettings(defaultSettings, for: uid)
                
                self.settings = defaultSettings
                settingsCache[uid] = defaultSettings
                
                dlog("📱 [MessageSettings] Created default settings for user \(uid)")
            }
            
            isLoading = false
        } catch {
            isLoading = false
            // Firestore permission errors (code 7) are transient on startup — the auth
            // token propagates asynchronously. Fall back to cached or default settings
            // instead of surfacing an error to the UI.
            let nsError = error as NSError
            let isPermissionError = nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
            if isPermissionError {
                dlog("⚠️ [MessageSettings] Permission denied — using defaults (auth token may not have propagated yet)")
                if settings == MessageSettings.defaultSettings() {
                    // Keep existing defaults; don't overwrite a previously loaded value
                }
                // Don't store the error or rethrow — let the app continue with defaults
            } else {
                self.error = error
                dlog("❌ [MessageSettings] Failed to load: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Save Settings
    
    func saveSettings(_ newSettings: MessageSettings, for userId: String? = nil) async throws {
        guard let uid = userId ?? Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessageSettings", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        var validated = newSettings.validated()
        validated.lastUpdated = Date()
        
        do {
            let encoder = Firestore.Encoder()
            let data = try encoder.encode(validated)
            
            try await settingsPath(for: uid).setData(data, merge: true)
            
            self.settings = validated
            settingsCache[uid] = validated
            
            dlog("📱 [MessageSettings] Saved settings for user \(uid)")
        } catch {
            dlog("❌ [MessageSettings] Failed to save: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Update Individual Settings
    
    func updateSetting<T: Codable>(_ keyPath: WritableKeyPath<MessageSettings, T>, value: T) async throws {
        var updated = settings
        updated[keyPath: keyPath] = value
        try await saveSettings(updated)
    }
    
    // MARK: - Real-time Listener
    
    func startListening(for userId: String? = nil) {
        // ✅ CRASH FIX: Guard against nil auth to prevent "Missing or insufficient permissions" error
        guard let uid = userId ?? Auth.auth().currentUser?.uid else { 
            dlog("⚠️ [MessageSettings] Cannot start listener: No authenticated user")
            return 
        }
        
        stopListening()
        
        listener = settingsPath(for: uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let error = error {
                    let nsError = error as NSError
                    let isPermissionError = nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
                    if isPermissionError {
                        dlog("⚠️ [MessageSettings] Listener: permission denied — using defaults until auth token propagates")
                    } else {
                        self.error = error
                        dlog("❌ [MessageSettings] Listener error: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let document = snapshot, document.exists, let data = document.data() else {
                    return
                }
                
                do {
                    let decoder = Firestore.Decoder()
                    var loadedSettings = try decoder.decode(MessageSettings.self, from: data)
                    loadedSettings = loadedSettings.validated()
                    
                    self.settings = loadedSettings
                    self.settingsCache[uid] = loadedSettings
                } catch {
                    dlog("❌ [MessageSettings] Failed to decode listener update: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Permission Checks
    
    func canUserSendMessageRequest(from senderId: String, to recipientId: String) async throws -> Bool {
        // Get recipient's settings
        let recipientSettings = try await getSettings(for: recipientId)
        
        // Check permission level
        switch recipientSettings.whoCanSendMessageRequests {
        case .noOne:
            return false
            
        case .everyone:
            return true
            
        case .peopleIFollow:
            // Check if recipient follows sender
            return try await isFollowing(userId: recipientId, targetId: senderId)
            
        case .mutualFollowsOnly:
            // Check mutual follow
            let recipientFollowsSender = try await isFollowing(userId: recipientId, targetId: senderId)
            let senderFollowsRecipient = try await isFollowing(userId: senderId, targetId: recipientId)
            return recipientFollowsSender && senderFollowsRecipient
            
        case .trustedConnectionsOnly:
            // Check if sender is in trusted connections
            return try await isTrustedConnection(userId: recipientId, connectionId: senderId)
        }
    }
    
    /// Check if a user can initiate a call to another user based on recipient's settings.
    /// - Note: This method is ready for integration when call functionality is implemented.
    ///         Usage: Before initiating a call, check if allowed:
    ///         ```
    ///         let canCall = try await MessageSettingsService.shared.canUserCall(from: currentUserId, to: recipientId)
    ///         guard canCall else {
    ///             throw CallError.notAllowed
    ///         }
    ///         // Proceed with call initiation
    ///         ```
    func canUserCall(from callerId: String, to recipientId: String) async throws -> Bool {
        let recipientSettings = try await getSettings(for: recipientId)

        switch recipientSettings.whoCanCallYou {
        case .noOne:
            return false
        case .everyone:
            return true
        case .peopleIFollow:
            return try await isFollowing(userId: recipientId, targetId: callerId)
        case .mutualFollowsOnly:
            let recipientFollowsCaller = try await isFollowing(userId: recipientId, targetId: callerId)
            let callerFollowsRecipient = try await isFollowing(userId: callerId, targetId: recipientId)
            return recipientFollowsCaller && callerFollowsRecipient
        case .trustedConnectionsOnly:
            return try await isTrustedConnection(userId: recipientId, connectionId: callerId)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getSettings(for userId: String) async throws -> MessageSettings {
        // Check cache first
        if let cached = settingsCache[userId] {
            return cached
        }
        
        // Load from Firestore
        let document = try await settingsPath(for: userId).getDocument()
        
        if document.exists, let data = document.data() {
            let decoder = Firestore.Decoder()
            let settings = try decoder.decode(MessageSettings.self, from: data)
            settingsCache[userId] = settings
            return settings
        } else {
            // Return defaults if no settings exist
            let isMinor = try await checkIfMinor(userId: userId)
            return MessageSettings.defaultSettings(isMinor: isMinor)
        }
    }
    
    private func isFollowing(userId: String, targetId: String) async throws -> Bool {
        // Integration with existing follow system
        let followDoc = try await db.collection("follows")
            .document(userId)
            .collection("following")
            .document(targetId)
            .getDocument()
        
        return followDoc.exists
    }
    
    private func isTrustedConnection(userId: String, connectionId: String) async throws -> Bool {
        // Check if connection is verified, from same church, or explicitly trusted
        // This integrates with TrustByDesignService if available
        
        // For now, check if they follow each other (mutual follow)
        let userFollowsConnection = try await isFollowing(userId: userId, targetId: connectionId)
        let connectionFollowsUser = try await isFollowing(userId: connectionId, targetId: userId)
        let mutualFollow = userFollowsConnection && connectionFollowsUser
        
        if mutualFollow {
            return true
        }
        
        // Could also check church membership, verification status, etc.
        // TODO: Integrate with TrustByDesignService when available
        
        return false
    }
    
    private func checkIfMinor(userId: String) async throws -> Bool {
        // Check user's age tier if available
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        if let ageTier = userDoc.data()?["ageTier"] as? String {
            return ageTier == "13-17" || ageTier == "under13"
        }
        
        return false
    }
    
    // MARK: - Analytics
    
    func trackSettingChange(_ settingName: String, newValue: Any) {
        // Analytics tracking (non-content, privacy-safe)
        // TODO: Integrate with AnalyticsService when available
        dlog("📊 [Analytics] message_setting_changed: \(settingName)")
    }
    
    // MARK: - Cleanup
    
    func clearCache() {
        settingsCache.removeAll()
    }
    
    deinit {
        Task { @MainActor in
            stopListening()
        }
    }
}
