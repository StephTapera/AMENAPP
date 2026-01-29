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

class LoginHistoryService: ObservableObject {
    static let shared = LoginHistoryService()
    
    private let database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com")
    @Published var loginSessions: [LoginSession] = []
    @Published var isLoading = false
    
    private var currentSessionId: String?
    
    private init() {
        print("🔐 LoginHistoryService initialized")
    }
    
    // MARK: - Track Login
    
    /// Record current login session
    func trackLogin() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        
        let deviceInfo = getDeviceInfo()
        let timestamp = Date().timeIntervalSince1970
        
        let sessionData: [String: Any] = [
            "sessionId": sessionId,
            "deviceName": deviceInfo.deviceName,
            "deviceType": deviceInfo.deviceType,
            "osVersion": deviceInfo.osVersion,
            "appVersion": deviceInfo.appVersion,
            "ipAddress": "", // Will be filled by backend/cloud function if needed
            "location": "", // Will be filled by backend/cloud function if needed
            "timestamp": timestamp,
            "lastActive": timestamp,
            "isCurrent": true
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
        
        print("✅ Login session tracked: \(sessionId)")
        
        // Store session ID locally
        UserDefaults.standard.set(sessionId, forKey: "currentLoginSessionId")
    }
    
    /// Update last active timestamp
    func updateLastActive() async {
        guard let userId = Auth.auth().currentUser?.uid,
              let sessionId = currentSessionId ?? UserDefaults.standard.string(forKey: "currentLoginSessionId") else {
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
            print("⚠️ Failed to update last active: \(error)")
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
            print("📭 No login history found")
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
        
        print("✅ Fetched \(sessions.count) login sessions")
        
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
        
        print("✅ Signed out from session: \(sessionId)")
        
        // Refresh login history
        _ = try await fetchLoginHistory()
    }
    
    /// Sign out from all devices except current
    func signOutAllOtherDevices() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "LoginHistoryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let currentSession = currentSessionId ?? UserDefaults.standard.string(forKey: "currentLoginSessionId")
        
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
        
        print("✅ Signed out from all other devices")
        
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
        
        print("✅ Signed out from all devices")
        
        // Sign out from Firebase Auth
        try Auth.auth().signOut()
        
        // Clear local session
        UserDefaults.standard.removeObject(forKey: "currentLoginSessionId")
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
        guard let deviceName = data["deviceName"] as? String,
              let deviceType = data["deviceType"] as? String,
              let osVersion = data["osVersion"] as? String,
              let appVersion = data["appVersion"] as? String,
              let timestamp = data["timestamp"] as? Double else {
            return nil
        }
        
        let ipAddress = data["ipAddress"] as? String
        let location = data["location"] as? String
        let isCurrent = data["isCurrent"] as? Bool ?? false
        
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
