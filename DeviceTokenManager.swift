//
//  DeviceTokenManager.swift
//  AMENAPP
//
//  Production-grade FCM device token lifecycle management
//  Handles multi-device support, token refresh, and invalid token cleanup
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import Combine

/// Manages FCM device tokens with multi-device support and lifecycle handling
@MainActor
final class DeviceTokenManager: ObservableObject {
    
    static let shared = DeviceTokenManager()
    
    private let db = Firestore.firestore()
    
    // MARK: - Token State
    
    @Published private(set) var currentToken: String?
    @Published private(set) var isTokenRegistered = false
    @Published private(set) var lastTokenRefresh: Date?
    
    // Constants
    private let tokenRefreshInterval: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    private let maxDevicesPerUser = 5  // P0 requirement: max 5 concurrent devices
    
    // MARK: - Initialization
    
    private init() {
        setupTokenRefreshObserver()
    }
    
    // MARK: - Token Registration
    
    /// Register current device token for push notifications
    func registerDeviceToken() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw DeviceTokenError.notAuthenticated
        }
        
        // Get current FCM token
        guard let token = try? await Messaging.messaging().token() else {
            throw DeviceTokenError.tokenRetrievalFailed
        }
        
        currentToken = token
        
        // Get device info
        let deviceId = await getDeviceIdentifier()
        let deviceInfo = await getDeviceInfo()
        
        print("📱 Registering device token: \(token.prefix(20))... for device: \(deviceId)")
        
        // Save to Firestore with device-specific document
        let tokenData: [String: Any] = [
            "token": token,
            "deviceId": deviceId,
            "deviceName": deviceInfo.name,
            "deviceModel": deviceInfo.model,
            "osVersion": deviceInfo.osVersion,
            "appVersion": deviceInfo.appVersion,
            "createdAt": Timestamp(date: Date()),
            "lastRefreshed": Timestamp(date: Date()),
            "isActive": true,
            "userId": userId
        ]
        
        do {
            // Use deviceId as document ID for idempotency
            try await db.collection("users")
                .document(userId)
                .collection("devices")
                .document(deviceId)
                .setData(tokenData, merge: true)
            
            // Also update the legacy fcmToken field on user document (for backward compatibility)
            try await db.collection("users")
                .document(userId)
                .updateData(["fcmToken": token, "fcmTokenUpdatedAt": Timestamp(date: Date())])
            
            isTokenRegistered = true
            lastTokenRefresh = Date()
            
            print("✅ Device token registered successfully")
            
            // Cleanup old/invalid tokens
            await cleanupInvalidTokens(userId: userId)
            
        } catch {
            print("❌ Error registering device token: \(error)")
            throw DeviceTokenError.registrationFailed(error.localizedDescription)
        }
    }
    
    /// Update existing token (called when FCM token refreshes)
    func updateDeviceToken(_ newToken: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        currentToken = newToken
        
        let deviceId = await getDeviceIdentifier()
        
        print("🔄 Updating device token for device: \(deviceId)")
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("devices")
                .document(deviceId)
                .updateData([
                    "token": newToken,
                    "lastRefreshed": Timestamp(date: Date()),
                    "isActive": true
                ])
            
            // Update legacy field
            try await db.collection("users")
                .document(userId)
                .updateData(["fcmToken": newToken, "fcmTokenUpdatedAt": Timestamp(date: Date())])
            
            lastTokenRefresh = Date()
            
            print("✅ Device token updated successfully")
            
        } catch {
            print("❌ Error updating device token: \(error)")
        }
    }
    
    /// Unregister device token (called on logout)
    func unregisterDeviceToken() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let deviceId = await getDeviceIdentifier()
        
        print("📱 Unregistering device token for device: \(deviceId)")
        
        do {
            // Mark device as inactive instead of deleting (for audit trail)
            try await db.collection("users")
                .document(userId)
                .collection("devices")
                .document(deviceId)
                .updateData([
                    "isActive": false,
                    "unregisteredAt": Timestamp(date: Date())
                ])
            
            isTokenRegistered = false
            currentToken = nil
            
            print("✅ Device token unregistered successfully")
            
        } catch {
            print("❌ Error unregistering device token: \(error)")
        }
    }
    
    // MARK: - Token Cleanup
    
    /// Remove invalid/expired tokens
    private func cleanupInvalidTokens(userId: String) async {
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("devices")
                .getDocuments()
            
            print("🧹 Checking \(snapshot.documents.count) device tokens for cleanup")
            
            var inactiveCount = 0
            var oldCount = 0
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                // Check if inactive
                if let isActive = data["isActive"] as? Bool, !isActive {
                    // Check if inactive for more than 30 days
                    if let unregisteredAt = data["unregisteredAt"] as? Timestamp {
                        let daysSinceUnregistered = Date().timeIntervalSince(unregisteredAt.dateValue()) / (24 * 60 * 60)
                        if daysSinceUnregistered > 30 {
                            try await doc.reference.delete()
                            inactiveCount += 1
                            print("   🗑️ Deleted inactive token (inactive for \(Int(daysSinceUnregistered)) days)")
                        }
                    }
                } else {
                    // Check if token hasn't been refreshed in a long time
                    if let lastRefreshed = data["lastRefreshed"] as? Timestamp {
                        let daysSinceRefresh = Date().timeIntervalSince(lastRefreshed.dateValue()) / (24 * 60 * 60)
                        if daysSinceRefresh > 90 {  // 90 days = likely abandoned device
                            try await doc.reference.delete()
                            oldCount += 1
                            print("   🗑️ Deleted stale token (not refreshed for \(Int(daysSinceRefresh)) days)")
                        }
                    }
                }
            }
            
            if inactiveCount > 0 || oldCount > 0 {
                print("✅ Cleaned up \(inactiveCount) inactive and \(oldCount) stale tokens")
            }
            
            // Enforce max devices limit
            await enforceDeviceLimit(userId: userId)
            
        } catch {
            print("❌ Error cleaning up tokens: \(error)")
        }
    }
    
    /// Enforce maximum number of active devices per user
    private func enforceDeviceLimit(userId: String) async {
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("devices")
                .whereField("isActive", isEqualTo: true)
                .order(by: "lastRefreshed", descending: false)  // Oldest first
                .getDocuments()
            
            let activeDevices = snapshot.documents
            
            if activeDevices.count > maxDevicesPerUser {
                let excessCount = activeDevices.count - maxDevicesPerUser
                print("⚠️ User has \(activeDevices.count) devices, removing \(excessCount) oldest")
                
                // Remove oldest devices
                for i in 0..<excessCount {
                    try await activeDevices[i].reference.delete()
                    print("   🗑️ Deleted oldest device: \(activeDevices[i].documentID)")
                }
                
                print("✅ Enforced device limit: kept newest \(maxDevicesPerUser) devices")
            }
            
        } catch {
            print("❌ Error enforcing device limit: \(error)")
        }
    }
    
    // MARK: - Token Refresh
    
    /// Check if token needs refresh and refresh if needed
    func checkAndRefreshTokenIfNeeded() async {
        guard let lastRefresh = lastTokenRefresh else {
            // No record of last refresh - refresh now
            try? await registerDeviceToken()
            return
        }
        
        let timeSinceRefresh = Date().timeIntervalSince(lastRefresh)
        
        if timeSinceRefresh > tokenRefreshInterval {
            print("🔄 Token refresh needed (last refresh: \(Int(timeSinceRefresh / 3600)) hours ago)")
            try? await registerDeviceToken()
        }
    }
    
    private func setupTokenRefreshObserver() {
        // Listen for FCM token refresh events
        NotificationCenter.default.addObserver(
            forName: Notification.Name("FCMTokenRefreshed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let token = notification.object as? String {
                Task { @MainActor [weak self] in
                    await self?.updateDeviceToken(token)
                }
            }
        }
        
        // Listen for app becoming active (check for token refresh)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndRefreshTokenIfNeeded()
            }
        }
    }
    
    // MARK: - Device Info
    
    /// Get unique device identifier
    private func getDeviceIdentifier() async -> String {
        // Use IDFV (Identifier for Vendor) which persists across app reinstalls
        // but is different for each app from the same vendor
        if let idfv = await UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        
        // Fallback: generate and store a UUID
        let key = "deviceIdentifier_v1"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
    
    /// Get device information for tracking
    private func getDeviceInfo() async -> DeviceInfo {
        let device = await UIDevice.current
        
        return DeviceInfo(
            name: await device.name,
            model: await device.model,
            osVersion: "\(await device.systemName) \(await device.systemVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
    }
    
    struct DeviceInfo {
        let name: String
        let model: String
        let osVersion: String
        let appVersion: String
    }
}

// MARK: - Errors

enum DeviceTokenError: LocalizedError {
    case notAuthenticated
    case tokenRetrievalFailed
    case registrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User must be authenticated to register device token"
        case .tokenRetrievalFailed:
            return "Failed to retrieve FCM token"
        case .registrationFailed(let reason):
            return "Failed to register device token: \(reason)"
        }
    }
}
