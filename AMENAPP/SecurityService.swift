//
//  SecurityService.swift
//  AMENAPP
//
//  Handles login history, sessions, security events, and account lifecycle
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

@MainActor
class SecurityService: ObservableObject {
    static let shared = SecurityService()
    
    private lazy var db = Firestore.firestore()
    
    @Published var loginHistory: [LoginRecord] = []
    @Published var activeSessions: [ActiveSession] = []
    @Published var securityEvents: [SecurityEvent] = []
    @Published var contactMethods: [ContactMethod] = []
    @Published var mfaMethods: [MFAMethod] = []
    @Published var trustedDevices: [TrustedDevice] = []
    
    private init() {}
    
    // MARK: - Device Info
    
    private func getCurrentDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        let deviceId = getDeviceIdentifier()
        
        return DeviceInfo(
            deviceId: deviceId,
            deviceName: device.name,
            platform: "iOS",
            osVersion: device.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            trusted: false
        )
    }
    
    private func getDeviceIdentifier() -> String {
        // Use identifierForVendor as device ID
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    // MARK: - Login Tracking
    
    func recordLogin(success: Bool, failureReason: String? = nil, mfaUsed: Bool = false) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let deviceInfo = getCurrentDeviceInfo()
        let location = await fetchLocationInfo()
        let ipAddress = await fetchIPAddress()
        let riskScore = calculateRiskScore(deviceInfo: deviceInfo, location: location, ipAddress: ipAddress)
        
        let record = LoginRecord(
            id: UUID().uuidString,
            userId: userId,
            timestamp: Date(),
            success: success,
            deviceInfo: deviceInfo,
            location: location,
            ipAddress: ipAddress,
            riskScore: riskScore,
            failureReason: failureReason,
            mfaUsed: mfaUsed
        )
        
        // Save to Firestore
        do {
            try db.collection("users").document(userId)
                .collection("loginHistory").document(record.id)
                .setData(from: record)
            
            // Record security event
            await recordSecurityEvent(
                type: success ? .loginSuccess : .loginFailure,
                deviceInfo: deviceInfo,
                ipAddress: ipAddress,
                location: location,
                metadata: failureReason != nil ? ["reason": failureReason!] : nil,
                riskScore: riskScore
            )
            
            // Send security alert if high risk
            if success && riskScore > 0.7 {
                await sendSecurityAlert(type: .suspiciousLogin, details: "Login from new location: \(location?.city ?? "Unknown")")
            }
        } catch {
            print("Error recording login: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Session Management
    
    func createSession() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let deviceInfo = getCurrentDeviceInfo()
        let location = await fetchLocationInfo()
        let ipAddress = await fetchIPAddress()
        
        let session = ActiveSession(
            id: UUID().uuidString,
            userId: userId,
            deviceInfo: deviceInfo,
            createdAt: Date(),
            lastActiveAt: Date(),
            ipAddress: ipAddress,
            location: location,
            refreshToken: UUID().uuidString, // In production, use actual refresh token
            riskScore: 0.0,
            current: true
        )
        
        do {
            try db.collection("users").document(userId)
                .collection("sessions").document(session.id)
                .setData(from: session)
            
            await recordSecurityEvent(
                type: .sessionCreated,
                deviceInfo: deviceInfo,
                ipAddress: ipAddress,
                location: location
            )
        } catch {
            print("Error creating session: \(error.localizedDescription)")
        }
    }
    
    func fetchActiveSessions() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("sessions")
                .order(by: "lastActiveAt", descending: true)
                .getDocuments()
            
            self.activeSessions = snapshot.documents.compactMap { doc in
                try? doc.data(as: ActiveSession.self)
            }.filter { !$0.isExpired }
        } catch {
            print("Error fetching sessions: \(error.localizedDescription)")
        }
    }
    
    func revokeSession(_ sessionId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId)
                .collection("sessions").document(sessionId)
                .delete()
            
            await recordSecurityEvent(type: .sessionRevoked, metadata: ["sessionId": sessionId])
            await fetchActiveSessions()
        } catch {
            print("Error revoking session: \(error.localizedDescription)")
        }
    }
    
    func revokeAllSessions() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("sessions")
                .getDocuments()
            
            // Delete all sessions except current
            for document in snapshot.documents {
                if let session = try? document.data(as: ActiveSession.self), !session.current {
                    try await document.reference.delete()
                }
            }
            
            await recordSecurityEvent(type: .allSessionsRevoked)
            await fetchActiveSessions()
        } catch {
            print("Error revoking all sessions: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Security Events
    
    func recordSecurityEvent(
        type: SecurityEventType,
        deviceInfo: DeviceInfo? = nil,
        ipAddress: String? = nil,
        location: LocationInfo? = nil,
        metadata: [String: String]? = nil,
        riskScore: Double? = nil
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let event = SecurityEvent(
            id: UUID().uuidString,
            userId: userId,
            eventType: type,
            timestamp: Date(),
            deviceInfo: deviceInfo,
            ipAddress: ipAddress,
            location: location,
            metadata: metadata,
            riskScore: riskScore
        )
        
        do {
            try db.collection("users").document(userId)
                .collection("securityEvents").document(event.id)
                .setData(from: event)
        } catch {
            print("Error recording security event: \(error.localizedDescription)")
        }
    }
    
    func fetchSecurityEvents(limit: Int = 50) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("securityEvents")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            self.securityEvents = snapshot.documents.compactMap { doc in
                try? doc.data(as: SecurityEvent.self)
            }
        } catch {
            print("Error fetching security events: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Login History
    
    func fetchLoginHistory(limit: Int = 20) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("loginHistory")
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            self.loginHistory = snapshot.documents.compactMap { doc in
                try? doc.data(as: LoginRecord.self)
            }
        } catch {
            print("Error fetching login history: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Contact Methods
    
    func fetchContactMethods() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("contactMethods")
                .getDocuments()
            
            self.contactMethods = snapshot.documents.compactMap { doc in
                try? doc.data(as: ContactMethod.self)
            }
        } catch {
            print("Error fetching contact methods: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Risk Calculation
    
    private func calculateRiskScore(deviceInfo: DeviceInfo, location: LocationInfo?, ipAddress: String) -> Double {
        var score = 0.0
        
        // New device = higher risk
        if !deviceInfo.trusted {
            score += 0.3
        }
        
        // No location data = moderate risk
        if location == nil {
            score += 0.2
        }
        
        // TODO: Add more sophisticated risk checks:
        // - Geovelocity (impossible travel)
        // - VPN/Proxy detection
        // - IP reputation
        // - Device fingerprint mismatch
        
        return min(score, 1.0)
    }
    
    // MARK: - Location & IP
    
    private func fetchLocationInfo() async -> LocationInfo? {
        // In production, use IP geolocation service
        // For now, return nil (will be populated by backend)
        return nil
    }
    
    private func fetchIPAddress() async -> String {
        // In production, get from backend
        return "0.0.0.0"
    }
    
    // MARK: - Security Alerts
    
    enum SecurityAlertType {
        case suspiciousLogin
        case newDevice
        case passwordChanged
        case emailChanged
        case mfaDisabled
    }
    
    private func sendSecurityAlert(type: SecurityAlertType, details: String) async {
        // Send email/push notification to user
        print("🔔 Security Alert: \(type) - \(details)")
        
        // TODO: Implement actual email/push notification
        // - Use Firebase Cloud Messaging for push
        // - Use SendGrid/AWS SES for email
    }
}
