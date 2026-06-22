//
//  LoginHistoryService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/26/26.
//
//  Service for tracking user login history and device sessions
//

import Foundation
import FirebaseAuth
import FirebaseDatabase
import UIKit
import Combine

// MARK: - Models

struct LoginSession: Identifiable, Codable {
    let id: String
    let deviceName: String
    let deviceType: String
    let osVersion: String
    let appVersion: String
    let ipAddress: String?
    let location: String?
    let timestamp: Date
    let isCurrent: Bool
    
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

private struct LoginHistorySessionID: RawRepresentable, Equatable {
    let rawValue: String
}

@MainActor
class LoginHistoryService: ObservableObject {
    static let shared = LoginHistoryService()

    /// Single source of truth for the RTDB field names of a login session.
    ///
    /// The write path (`trackLogin`) and the read path (`parseSession`) must
    /// agree on every key — a typo in one but not the other silently drops a
    /// field at runtime. Centralizing the names here makes that a compile-time
    /// concern instead.
    private enum Field {
        static let sessionId  = "sessionId"
        static let deviceName = "deviceName"
        static let deviceType = "deviceType"
        static let osVersion  = "osVersion"
        static let appVersion = "appVersion"
        static let ipAddress  = "ipAddress"
        static let location   = "location"
        static let timestamp  = "timestamp"
        static let lastActive = "lastActive"
        static let isCurrent  = "isCurrent"
    }

    private let database = Database.database()
    @Published var loginSessions: [LoginSession] = []
    @Published var isLoading = false
    
    // Typed so a session id can't be silently confused with any other String id.
    private var currentSessionId: LoginHistorySessionID?
    
    private init() {}
    
    // MARK: - Track Login
    
    /// Record current login session
    func trackLogin() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sessionId = UUID().uuidString
        currentSessionId = LoginHistorySessionID(rawValue: sessionId)
        
        let deviceInfo = getDeviceInfo()
        let timestamp = Date().timeIntervalSince1970
        
        let sessionData: [String: Any] = [
            Field.sessionId: sessionId,
            Field.deviceName: deviceInfo.deviceName,
            Field.deviceType: deviceInfo.deviceType,
            Field.osVersion: deviceInfo.osVersion,
            Field.appVersion: deviceInfo.appVersion,
            Field.ipAddress: "", // Will be filled by backend/cloud function if needed
            Field.location: "", // Will be filled by backend/cloud function if needed
            Field.timestamp: timestamp,
            Field.lastActive: timestamp,
            Field.isCurrent: true
        ]
        
        // Add to user's login history
        let sessionRef = database.reference()
            .child("user-login-history")
            .child(userId)
            .child(sessionId)
        
        try await sessionRef.setValue(sessionData)
        
        // Mark all other sessions as not current
        let allSessionsRef = database.reference()
            .child("user-login-history")
            .child(userId)
        
        let snapshot = try await allSessionsRef.getData()
        
        if snapshot.exists(), let sessions = snapshot.value as? [String: Any] {
            for (sid, _) in sessions where sid != sessionId {
                try await allSessionsRef.child(sid).child("isCurrent").setValue(false)
            }
        }
        
        dlog("✅ Login session tracked: \(sessionId)")
        
        // Store session ID locally
        UserDefaults.standard.set(sessionId, forKey: UserDefaultsKeys.currentLoginSessionId)
    }
    
    /// Update last active timestamp
    func updateLastActive() async {
        guard let userId = Auth.auth().currentUser?.uid,
              let sessionId = currentSessionId?.rawValue ?? UserDefaults.standard.string(forKey: UserDefaultsKeys.currentLoginSessionId) else {
            return
        }
        
        let sessionRef = database.reference()
            .child("user-login-history")
            .child(userId)
            .child(sessionId)
            .child("lastActive")
        
        do {
            try await sessionRef.setValue(Date().timeIntervalSince1970)
        } catch {
            dlog("⚠️ Failed to update last active: \(error)")
        }
    }
    
    // MARK: - Fetch Login History
    
    /// Fetch all login sessions for current user
    @MainActor
    func fetchLoginHistory() async throws -> [LoginSession] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let historyRef = database.reference()
            .child("user-login-history")
            .child(userId)
        
        let snapshot = try await historyRef.getData()
        
        guard snapshot.exists(), let sessionsData = snapshot.value as? [String: Any] else {
            dlog("📭 No login history found")
            return []
        }
        
        var sessions: [LoginSession] = []
        
        for (sessionId, sessionValue) in sessionsData {
            guard let sessionData = sessionValue as? [String: Any] else { continue }
            
            if let session = parseSession(id: sessionId, data: sessionData) {
                sessions.append(session)
            }
        }
        
        // Sort by timestamp (most recent first)
        sessions.sort { $0.timestamp > $1.timestamp }
        
        dlog("✅ Fetched \(sessions.count) login sessions")
        
        self.loginSessions = sessions
        
        return sessions
    }
    
    // MARK: - Sign Out Actions
    
    /// Sign out from a specific device/session
    func signOutFromSession(sessionId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sessionRef = database.reference()
            .child("user-login-history")
            .child(userId)
            .child(sessionId)
        
        try await sessionRef.removeValue()
        
        dlog("✅ Signed out from session: \(sessionId)")
        
        // Refresh login history
        _ = try await fetchLoginHistory()
    }
    
    /// Sign out from all devices except current
    func signOutAllOtherDevices() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentSession = currentSessionId?.rawValue ?? UserDefaults.standard.string(forKey: UserDefaultsKeys.currentLoginSessionId)
        
        let historyRef = database.reference()
            .child("user-login-history")
            .child(userId)
        
        let snapshot = try await historyRef.getData()
        
        guard snapshot.exists(), let sessionsData = snapshot.value as? [String: Any] else {
            return
        }
        
        // Remove all sessions except current
        for (sessionId, _) in sessionsData where sessionId != currentSession {
            try await historyRef.child(sessionId).removeValue()
        }
        
        dlog("✅ Signed out from all other devices")
        
        // Refresh login history
        _ = try await fetchLoginHistory()
    }
    
    /// Sign out from all devices (including current)
    func signOutAllDevices() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let historyRef = database.reference()
            .child("user-login-history")
            .child(userId)
        
        try await historyRef.removeValue()
        
        dlog("✅ Signed out from all devices")
        
        // Sign out from Firebase Auth
        try Auth.auth().signOut()
        
        // Clear local session
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.currentLoginSessionId)
        currentSessionId = nil
    }
    
    // MARK: - Helper Methods
    
    private func getDeviceInfo() -> (deviceName: String, deviceType: String, osVersion: String, appVersion: String) {
        let device = UIDevice.current
        
        // Device name (e.g., "iPhone 14 Pro")
        let deviceName = device.model
        
        // Device type (e.g., "iPhone", "iPad")
        let deviceType: String
        if UIDevice.current.userInterfaceIdiom == .phone {
            deviceType = "iPhone"
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            deviceType = "iPad"
        } else {
            deviceType = "Unknown"
        }
        
        // OS version (e.g., "iOS 17.2")
        let osVersion = "\(device.systemName) \(device.systemVersion)"
        
        // App version (e.g., "1.0.0")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        return (deviceName, deviceType, osVersion, appVersion)
    }
    
    private func parseSession(id: String, data: [String: Any]) -> LoginSession? {
        guard let deviceName = data[Field.deviceName] as? String,
              let deviceType = data[Field.deviceType] as? String,
              let osVersion = data[Field.osVersion] as? String,
              let appVersion = data[Field.appVersion] as? String,
              let timestamp = data[Field.timestamp] as? Double else {
            return nil
        }

        let ipAddress = data[Field.ipAddress] as? String
        let location = data[Field.location] as? String
        let isCurrent = data[Field.isCurrent] as? Bool ?? false
        
        return LoginSession(
            id: id,
            deviceName: deviceName,
            deviceType: deviceType,
            osVersion: osVersion,
            appVersion: appVersion,
            ipAddress: ipAddress,
            location: location,
            timestamp: Date(timeIntervalSince1970: timestamp),
            isCurrent: isCurrent
        )
    }
}
