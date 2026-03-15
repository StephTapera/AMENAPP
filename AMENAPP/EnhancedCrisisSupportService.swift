//
//  EnhancedCrisisSupportService.swift
//  AMENAPP
//
//  Support-first crisis intervention system
//  Gentle, non-punitive, with risk scoring
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

@MainActor
class EnhancedCrisisSupportService {
    static let shared = EnhancedCrisisSupportService()
    
    private let db = Firestore.firestore()
    private init() {}
    
    // MARK: - Risk Assessment
    
    /// Assess crisis risk with detailed scoring (0-1)
    func assessRisk(
        in text: String,
        context: CrisisRiskAssessment.CrisisContext
    ) async -> CrisisRiskAssessment {
        
        let text = text.lowercased()
        var score: Double = 0.0
        var reasonCodes: [CrisisRiskAssessment.ReasonCode] = []
        var falsePositiveFilters: [String] = []
        
        // ============================================================================
        // FALSE POSITIVE FILTERS (reduce score for casual language)
        // ============================================================================
        
        let casualPhrases = [
            "i'd die for", "dying for", "kill for", "killing me", "dead tired",
            "i'm dead", "literally dying", "so dead", "die laughing", "to die for"
        ]
        
        for phrase in casualPhrases {
            if text.contains(phrase) {
                falsePositiveFilters.append(phrase)
                score -= 0.15  // Reduce score for casual usage
            }
        }
        
        // ============================================================================
        // IDEATION (thoughts of suicide)
        // ============================================================================
        
        let ideationPatterns = [
            "want to die", "wish i was dead", "better off dead", "don't want to be here",
            "can't go on", "end it all", "end my life", "take my life", "hurt myself"
        ]
        
        for pattern in ideationPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.ideation)
                score += CrisisRiskAssessment.ReasonCode.ideation.weight
                break
            }
        }
        
        // ============================================================================
        // PLAN (specific method mentioned)
        // ============================================================================
        
        let planPatterns = [
            "going to jump", "take pills", "overdose", "hanging", "cut myself",
            "slit my wrists", "step in front", "walk into traffic"
        ]
        
        for pattern in planPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.plan)
                score += CrisisRiskAssessment.ReasonCode.plan.weight
                break
            }
        }
        
        // ============================================================================
        // MEANS (access to lethal means)
        // ============================================================================
        
        let meansPatterns = [
            "have pills", "got a gun", "bought pills", "have rope", "sharp knife"
        ]
        
        for pattern in meansPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.means)
                score += CrisisRiskAssessment.ReasonCode.means.weight
                break
            }
        }
        
        // ============================================================================
        // TIMEFRAME (immediate intent)
        // ============================================================================
        
        let timeframePatterns = [
            "tonight", "today", "right now", "this morning", "can't wait",
            "soon as", "after i", "before i go"
        ]
        
        for pattern in timeframePatterns {
            if text.contains(pattern) && (reasonCodes.contains(.ideation) || reasonCodes.contains(.plan)) {
                reasonCodes.append(.timeframe)
                score += CrisisRiskAssessment.ReasonCode.timeframe.weight
                break
            }
        }
        
        // ============================================================================
        // GOODBYE LANGUAGE (farewell messages)
        // ============================================================================
        
        let goodbyePatterns = [
            "goodbye", "final post", "last time", "won't be around", "sorry for everything",
            "forgive me", "thank you for", "i love you all", "take care of"
        ]
        
        for pattern in goodbyePatterns {
            if text.contains(pattern) && (reasonCodes.contains(.ideation) || reasonCodes.contains(.plan)) {
                reasonCodes.append(.goodbyeLanguage)
                score += CrisisRiskAssessment.ReasonCode.goodbyeLanguage.weight
                break
            }
        }
        
        // ============================================================================
        // HOPELESSNESS (extreme negative thinking)
        // ============================================================================
        
        let hopelessnessPatterns = [
            "no point", "no reason to live", "nothing left", "no hope", "pointless",
            "never going to", "always be like this", "can't see a way"
        ]
        
        for pattern in hopelessnessPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.hopelessness)
                score += CrisisRiskAssessment.ReasonCode.hopelessness.weight
                break
            }
        }
        
        // ============================================================================
        // ISOLATION (feeling alone/burden)
        // ============================================================================
        
        let isolationPatterns = [
            "no one cares", "better off without me", "burden to everyone", "all alone",
            "nobody would miss me", "people hate me", "everyone would be better"
        ]
        
        for pattern in isolationPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.isolation)
                score += CrisisRiskAssessment.ReasonCode.isolation.weight
                break
            }
        }
        
        // ============================================================================
        // SELF-HARM (cutting, burning, etc.)
        // ============================================================================
        
        let selfHarmPatterns = [
            "cut myself", "burn myself", "hurt myself", "punish myself", "harm myself"
        ]
        
        for pattern in selfHarmPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.selfHarm)
                score += CrisisRiskAssessment.ReasonCode.selfHarm.weight
                break
            }
        }
        
        // ============================================================================
        // RECENT LOSS (major life event)
        // ============================================================================
        
        let lossPatterns = [
            "just lost", "died yesterday", "funeral was", "passed away", "since they died"
        ]
        
        for pattern in lossPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.recentLoss)
                score += CrisisRiskAssessment.ReasonCode.recentLoss.weight
                break
            }
        }
        
        // ============================================================================
        // PANIC SYMPTOMS (physical crisis)
        // ============================================================================
        
        let panicPatterns = [
            "can't breathe", "heart racing", "going to die", "losing control", "panic attack"
        ]
        
        for pattern in panicPatterns {
            if text.contains(pattern) {
                reasonCodes.append(.panicSymptoms)
                score += CrisisRiskAssessment.ReasonCode.panicSymptoms.weight
                break
            }
        }
        
        // ============================================================================
        // CALCULATE FINAL SCORE AND LEVEL
        // ============================================================================
        
        // Clamp score to 0.0 - 1.0
        score = max(0.0, min(1.0, score))
        
        // Determine risk level based on score
        let riskLevel: CrisisRiskAssessment.RiskLevel
        switch score {
        case 0.0..<0.2:
            riskLevel = .none
        case 0.2..<0.4:
            riskLevel = .low
        case 0.4..<0.6:
            riskLevel = .moderate
        case 0.6..<0.8:
            riskLevel = .high
        default:
            riskLevel = .critical
        }
        
        #if DEBUG
        if riskLevel != .none {
            print("🚨 [CRISIS] Risk detected: \(riskLevel.rawValue) (score: \(String(format: "%.2f", score)))")
            print("   Reasons: \(reasonCodes.map { $0.displayName }.joined(separator: ", "))")
            if !falsePositiveFilters.isEmpty {
                print("   False positives filtered: \(falsePositiveFilters.joined(separator: ", "))")
            }
        }
        #endif
        
        return CrisisRiskAssessment(
            riskScore: score,
            riskLevel: riskLevel,
            reasonCodes: Array(Set(reasonCodes)),  // Remove duplicates
            context: context,
            falsePositiveFilters: falsePositiveFilters,
            timestamp: Date()
        )
    }
    
    // MARK: - User Preferences
    
    /// Load user's crisis support preferences
    func loadPreferences(userId: String) async throws -> CrisisSupportPreferences {
        let doc = try await db.collection("crisisSupportPreferences")
            .document(userId)
            .getDocument()
        
        if let data = doc.data(),
           let prefs = try? Firestore.Decoder().decode(CrisisSupportPreferences.self, from: data) {
            return prefs
        }
        
        // Return defaults if not found
        return CrisisSupportPreferences.defaultPreferences(userId: userId)
    }
    
    /// Save user preferences
    func savePreferences(_ prefs: CrisisSupportPreferences) async throws {
        let data = try Firestore.Encoder().encode(prefs)
        try await db.collection("crisisSupportPreferences")
            .document(prefs.userId)
            .setData(data, merge: true)
    }
    
    /// Check if user has dismissed support card recently
    func shouldShowSupport(for userId: String, riskLevel: CrisisRiskAssessment.RiskLevel) async -> Bool {
        guard let prefs = try? await loadPreferences(userId: userId) else {
            return true  // Show by default
        }
        
        // Always show for high/critical risk
        if riskLevel == .high || riskLevel == .critical {
            return true
        }
        
        // Check if user dismissed recently
        if let dontShowUntil = prefs.dontShowAgainUntil, Date() < dontShowUntil {
            return false
        }
        
        return prefs.showSubtleSupport
    }
    
    /// User dismissed support card - don't show again for X hours
    func dismissSupport(userId: String, durationHours: Int = 24) async throws {
        var prefs = try await loadPreferences(userId: userId)
        prefs.dontShowAgainUntil = Date().addingTimeInterval(TimeInterval(durationHours * 3600))
        prefs.updatedAt = Date()
        try await savePreferences(prefs)
    }
    
    // MARK: - Trusted Circle
    
    /// Load user's trusted circle
    func loadTrustedCircle(userId: String) async throws -> TrustedCircle? {
        let doc = try await db.collection("trustedCircles")
            .document(userId)
            .getDocument()
        
        guard let data = doc.data() else { return nil }
        return try? Firestore.Decoder().decode(TrustedCircle.self, from: data)
    }
    
    /// Save trusted circle
    func saveTrustedCircle(_ circle: TrustedCircle) async throws {
        let data = try Firestore.Encoder().encode(circle)
        try await db.collection("trustedCircles")
            .document(circle.userId)
            .setData(data)
    }
    
    /// Ask user if they want to notify trusted circle
    func shouldAskToNotify(
        userId: String,
        riskLevel: CrisisRiskAssessment.RiskLevel
    ) async -> Bool {
        guard let circle = try? await loadTrustedCircle(userId: userId),
              circle.isEnabled,
              !circle.contacts.isEmpty else {
            return false
        }
        
        // Only ask for moderate/high/critical
        return riskLevel.rawValue >= CrisisRiskAssessment.RiskLevel.moderate.rawValue
    }
    
    /// Send alert to trusted circle
    func notifyTrustedCircle(
        userId: String,
        riskLevel: CrisisRiskAssessment.RiskLevel,
        userConsented: Bool
    ) async throws {
        guard let circle = try? await loadTrustedCircle(userId: userId),
              circle.isEnabled else {
            return
        }
        
        let userName = try? await fetchUserName(userId: userId)
        
        // Log the alert
        let alertLog = CrisisAlertLog(
            id: UUID().uuidString,
            userId: userId,
            triggeredAt: Date(),
            riskLevel: riskLevel,
            contentContext: .post,  // Will be updated based on actual context
            notifiedContacts: circle.contacts.map { $0.id },
            userConsented: userConsented,
            autoTriggered: !userConsented,
            responseTime: nil,
            outcome: nil
        )
        
        // crisisAlertLogs is a server-only collection (Firestore rules deny all client writes).
        // The Cloud Function triggered on the trusted circle notification write handles server logging.
        #if DEBUG
        print("🧠 [CRISIS ALERT] Would log alert \(alertLog.id) for user \(userId), risk=\(riskLevel.rawValue)")
        #endif
        
        // Send notifications to trusted contacts
        for contact in circle.contacts {
            try await sendTrustedCircleNotification(
                contact: contact,
                userName: userName ?? "Someone",
                riskLevel: riskLevel
            )
        }
    }
    
    private func sendTrustedCircleNotification(
        contact: TrustedCircle.TrustedContact,
        userName: String,
        riskLevel: CrisisRiskAssessment.RiskLevel
    ) async throws {
        // Minimal, respectful message
        let message = "AMEN is concerned about \(userName). Please check in when you can."
        
        #if DEBUG
        print("🚨 [TRUSTED CIRCLE] Would notify: \(contact.name)")
        print("   Message: \(message)")
        #endif
        
        // If contact is an AMEN user, send in-app notification
        if let contactUserId = contact.userId {
            // Write a raw Firestore record for the trusted circle alert log
            try await db.collection("trustedCircleNotifications")
                .addDocument(data: [
                    "recipientUserId": contactUserId,
                    "senderName": userName,
                    "message": message,
                    "riskLevel": riskLevel.rawValue,
                    "sentAt": Timestamp(date: Date()),
                    "isRead": false
                ])
            
            // Also deliver as a standard in-app notification so the recipient sees
            // a badge and gets a push via the existing FCM notification fan-out.
            let notificationId = UUID().uuidString
            try await db.collection("users").document(contactUserId)
                .collection("notifications").document(notificationId)
                .setData([
                    "userId": contactUserId,
                    "type": "crisis_alert",
                    "actorName": userName,
                    "commentText": message,
                    "read": false,
                    "priority": 90,  // High priority
                    "createdAt": FieldValue.serverTimestamp(),
                    "idempotencyKey": "crisis_\(userName)_\(contactUserId)_\(Int(Date().timeIntervalSince1970 / 3600))"
                ])
        }
        
        // If phone number, could integrate SMS (optional, requires Twilio/similar)
        // For now, just in-app notifications
    }
    
    // MARK: - Helpers
    
    private func fetchUserName(userId: String) async throws -> String {
        let doc = try await db.collection("users").document(userId).getDocument()
        return doc.data()?["displayName"] as? String ?? "User"
    }
}
