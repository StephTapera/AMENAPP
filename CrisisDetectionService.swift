//
//  CrisisDetectionService.swift
//  AMENAPP
//
//  AI-powered crisis detection for prayer requests
//  Detects suicide ideation, abuse, self-harm, and routes to resources
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

// MARK: - Crisis Detection Models

/// Crisis detection result from AI analysis
struct CrisisDetectionResult: Codable {
    let isCrisis: Bool
    let crisisTypes: [CrisisType]
    let urgencyLevel: UrgencyLevel
    let recommendedResources: [ResourceType]
    let confidence: Double
    let suggestedIntervention: InterventionType
    
    enum CrisisType: String, Codable, CaseIterable {
        case suicideIdeation = "suicide_ideation"
        case selfHarm = "self_harm"
        case abuse = "abuse"
        case domesticViolence = "domestic_violence"
        case sexualAssault = "sexual_assault"
        case substanceAbuse = "substance_abuse"
        case mentalHealthCrisis = "mental_health_crisis"
        case severeDepression = "severe_depression"
        case panicAttack = "panic_attack"
        
        var displayName: String {
            switch self {
            case .suicideIdeation: return "Suicide Ideation"
            case .selfHarm: return "Self-Harm"
            case .abuse: return "Abuse"
            case .domesticViolence: return "Domestic Violence"
            case .sexualAssault: return "Sexual Assault"
            case .substanceAbuse: return "Substance Abuse"
            case .mentalHealthCrisis: return "Mental Health Crisis"
            case .severeDepression: return "Severe Depression"
            case .panicAttack: return "Panic Attack"
            }
        }
    }
    
    enum UrgencyLevel: String, Codable {
        case none = "none"
        case low = "low"
        case moderate = "moderate"
        case high = "high"
        case critical = "critical"
    }
    
    enum InterventionType: String, Codable {
        case none = "none"
        case showResources = "show_resources"
        case alertModerators = "alert_moderators"
        case emergencyContact = "emergency_contact"
    }
}

/// Resource type for crisis support
enum ResourceType: String, Codable, CaseIterable {
    case suicidePrevention = "suicide_prevention"
    case mentalHealth = "mental_health"
    case crisisTextLine = "crisis_text_line"
    case domesticViolence = "domestic_violence"
    case sexualAssault = "sexual_assault"
    case substanceAbuse = "substance_abuse"
    case christianCounseling = "christian_counseling"
    
    var displayName: String {
        switch self {
        case .suicidePrevention: return "Suicide Prevention Hotline"
        case .mentalHealth: return "Mental Health Resources"
        case .crisisTextLine: return "Crisis Text Line"
        case .domesticViolence: return "Domestic Violence Support"
        case .sexualAssault: return "Sexual Assault Support"
        case .substanceAbuse: return "Substance Abuse Support"
        case .christianCounseling: return "Christian Counseling"
        }
    }
    
    var phoneNumber: String {
        switch self {
        case .suicidePrevention: return "988" // 988 Suicide & Crisis Lifeline
        case .crisisTextLine: return "741741" // Text HOME to 741741
        case .domesticViolence: return "1-800-799-7233" // National Domestic Violence Hotline
        case .sexualAssault: return "1-800-656-4673" // RAINN
        case .substanceAbuse: return "1-800-662-4357" // SAMHSA
        default: return ""
        }
    }
    
    var website: String {
        switch self {
        case .suicidePrevention: return "https://988lifeline.org"
        case .crisisTextLine: return "https://www.crisistextline.org"
        case .domesticViolence: return "https://www.thehotline.org"
        case .sexualAssault: return "https://www.rainn.org"
        case .substanceAbuse: return "https://www.samhsa.gov"
        case .christianCounseling: return "https://www.aacc.net"
        case .mentalHealth: return "https://www.nami.org"
        }
    }
}

// MARK: - Crisis Detection Service

/// Service for detecting crisis situations in prayer requests
class CrisisDetectionService {
    static let shared = CrisisDetectionService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Crisis Detection
    
    /// Analyze prayer request for crisis indicators
    /// - Parameters:
    ///   - prayerText: The prayer request text to analyze
    ///   - userId: ID of user posting prayer request
    /// - Returns: CrisisDetectionResult with crisis status and recommended actions
    func detectCrisis(
        in prayerText: String,
        userId: String
    ) async throws -> CrisisDetectionResult {
        
        print("🚨 [CRISIS] Analyzing prayer request for crisis indicators...")
        
        // Step 1: Quick local pattern matching (instant)
        if let quickResult = performQuickCrisisCheck(prayerText) {
            print("🚨 [CRISIS] Quick check detected: \(quickResult.crisisTypes.map { $0.displayName })")
            
            // Log crisis detection
            await logCrisisDetection(
                userId: userId,
                prayerText: prayerText,
                result: quickResult
            )
            
            return quickResult
        }
        
        // Step 2: Call Firebase AI Logic for deep analysis
        let aiResult = try await callFirebaseAICrisisDetectionAPI(
            prayerText: prayerText,
            userId: userId
        )
        
        // Step 3: Log if crisis detected
        if aiResult.isCrisis {
            await logCrisisDetection(
                userId: userId,
                prayerText: prayerText,
                result: aiResult
            )
            
            print("🚨 [CRISIS] AI detected: \(aiResult.crisisTypes.map { $0.displayName }) (urgency: \(aiResult.urgencyLevel.rawValue))")
        }
        
        return aiResult
    }
    
    // MARK: - Quick Local Crisis Detection
    
    /// Perform instant local pattern matching for crisis keywords
    private func performQuickCrisisCheck(_ text: String) -> CrisisDetectionResult? {
        let lowercased = text.lowercased()
        var detectedCrises: [CrisisDetectionResult.CrisisType] = []
        var maxUrgency: CrisisDetectionResult.UrgencyLevel = .none
        
        // Suicide ideation patterns (CRITICAL)
        let suicidePatterns = [
            "want to die", "kill myself", "end my life", "suicide",
            "better off dead", "no reason to live", "can't go on",
            "end it all", "take my life", "not worth living"
        ]
        
        for pattern in suicidePatterns {
            if lowercased.contains(pattern) {
                detectedCrises.append(.suicideIdeation)
                maxUrgency = .critical
                break
            }
        }
        
        // Self-harm patterns (HIGH)
        let selfHarmPatterns = [
            "hurt myself", "cut myself", "harm myself",
            "self harm", "cutting", "burning myself"
        ]
        
        for pattern in selfHarmPatterns {
            if lowercased.contains(pattern) && maxUrgency != .critical {
                detectedCrises.append(.selfHarm)
                maxUrgency = .high
                break
            }
        }
        
        // Abuse patterns (HIGH)
        let abusePatterns = [
            "abused", "abusing me", "hitting me", "hurting me",
            "beating me", "violence", "scared for my life"
        ]
        
        for pattern in abusePatterns {
            if lowercased.contains(pattern) {
                detectedCrises.append(.abuse)
                if maxUrgency.rawValue < CrisisDetectionResult.UrgencyLevel.high.rawValue {
                    maxUrgency = .high
                }
                break
            }
        }
        
        // Domestic violence patterns (HIGH)
        let domesticViolencePatterns = [
            "domestic violence", "spouse hitting", "partner hurting",
            "afraid of my husband", "afraid of my wife"
        ]
        
        for pattern in domesticViolencePatterns {
            if lowercased.contains(pattern) {
                detectedCrises.append(.domesticViolence)
                if maxUrgency.rawValue < CrisisDetectionResult.UrgencyLevel.high.rawValue {
                    maxUrgency = .high
                }
                break
            }
        }
        
        // Severe depression patterns (MODERATE)
        let depressionPatterns = [
            "hopeless", "no hope", "can't take it anymore",
            "giving up", "nothing matters", "lost all hope"
        ]
        
        for pattern in depressionPatterns {
            if lowercased.contains(pattern) && detectedCrises.isEmpty {
                detectedCrises.append(.severeDepression)
                maxUrgency = .moderate
                break
            }
        }
        
        // If crisis detected, return result immediately
        if !detectedCrises.isEmpty {
            let resources = getRecommendedResources(for: detectedCrises)
            
            return CrisisDetectionResult(
                isCrisis: true,
                crisisTypes: detectedCrises,
                urgencyLevel: maxUrgency,
                recommendedResources: resources,
                confidence: 0.85,
                suggestedIntervention: maxUrgency == .critical ? .emergencyContact : .showResources
            )
        }
        
        return nil
    }
    
    // MARK: - Firebase AI Crisis Detection
    
    /// Call Firebase AI Logic for deep crisis analysis
    private func callFirebaseAICrisisDetectionAPI(
        prayerText: String,
        userId: String
    ) async throws -> CrisisDetectionResult {
        
        let requestData: [String: Any] = [
            "prayerText": prayerText,
            "userId": userId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            // Call Firebase AI Logic Cloud Function
            let result = try await db.collection("crisisDetectionRequests")
                .addDocument(data: requestData)
            
            // Wait for AI response
            let response = try await waitForCrisisDetectionResponse(requestId: result.documentID)
            
            return response
            
        } catch {
            print("❌ [CRISIS] AI API error: \(error)")
            
            // Fallback: No crisis detected if AI fails
            return CrisisDetectionResult(
                isCrisis: false,
                crisisTypes: [],
                urgencyLevel: .none,
                recommendedResources: [],
                confidence: 0.0,
                suggestedIntervention: .none
            )
        }
    }
    
    /// Wait for Firebase AI Logic to process crisis detection
    private func waitForCrisisDetectionResponse(requestId: String) async throws -> CrisisDetectionResult {
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let snapshot = try await db.collection("crisisDetectionResults")
                .document(requestId)
                .getDocument()
            
            if snapshot.exists,
               let data = snapshot.data(),
               let isCrisis = data["isCrisis"] as? Bool {
                
                let crisisTypesRaw = data["crisisTypes"] as? [String] ?? []
                let crisisTypes = crisisTypesRaw.compactMap { CrisisDetectionResult.CrisisType(rawValue: $0) }
                
                let urgencyRaw = data["urgencyLevel"] as? String ?? "none"
                let urgency = CrisisDetectionResult.UrgencyLevel(rawValue: urgencyRaw) ?? .none
                
                let resourcesRaw = data["recommendedResources"] as? [String] ?? []
                let resources = resourcesRaw.compactMap { ResourceType(rawValue: $0) }
                
                let confidence = data["confidence"] as? Double ?? 0.0
                
                let interventionRaw = data["suggestedIntervention"] as? String ?? "none"
                let intervention = CrisisDetectionResult.InterventionType(rawValue: interventionRaw) ?? .none
                
                return CrisisDetectionResult(
                    isCrisis: isCrisis,
                    crisisTypes: crisisTypes,
                    urgencyLevel: urgency,
                    recommendedResources: resources,
                    confidence: confidence,
                    suggestedIntervention: intervention
                )
            }
        }
        
        throw NSError(domain: "CrisisDetection", code: 408, userInfo: nil)
    }
    
    // MARK: - Helper Methods
    
    /// Get recommended resources based on detected crisis types
    private func getRecommendedResources(
        for crisisTypes: [CrisisDetectionResult.CrisisType]
    ) -> [ResourceType] {
        var resources: [ResourceType] = []
        
        for crisis in crisisTypes {
            switch crisis {
            case .suicideIdeation:
                resources.append(contentsOf: [.suicidePrevention, .crisisTextLine, .mentalHealth])
            case .selfHarm:
                resources.append(contentsOf: [.mentalHealth, .crisisTextLine])
            case .abuse, .domesticViolence:
                resources.append(.domesticViolence)
            case .sexualAssault:
                resources.append(.sexualAssault)
            case .substanceAbuse:
                resources.append(.substanceAbuse)
            case .mentalHealthCrisis, .severeDepression, .panicAttack:
                resources.append(contentsOf: [.mentalHealth, .christianCounseling])
            }
        }
        
        // Always include Christian counseling for faith-based support
        if !resources.contains(.christianCounseling) {
            resources.append(.christianCounseling)
        }
        
        return Array(Set(resources)) // Remove duplicates
    }
    
    // MARK: - Logging
    
    /// Log crisis detection for analytics and follow-up
    private func logCrisisDetection(
        userId: String,
        prayerText: String,
        result: CrisisDetectionResult
    ) async {
        
        let logData: [String: Any] = [
            "userId": userId,
            "prayerTextLength": prayerText.count,
            "isCrisis": result.isCrisis,
            "crisisTypes": result.crisisTypes.map { $0.rawValue },
            "urgencyLevel": result.urgencyLevel.rawValue,
            "recommendedResources": result.recommendedResources.map { $0.rawValue },
            "confidence": result.confidence,
            "suggestedIntervention": result.suggestedIntervention.rawValue,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        do {
            try await db.collection("crisisDetectionLogs")
                .addDocument(data: logData)
            
            // Alert moderators for high/critical urgency
            if result.urgencyLevel == .high || result.urgencyLevel == .critical {
                try await alertModerators(userId: userId, result: result)
            }
            
        } catch {
            print("⚠️ [CRISIS] Failed to log detection: \(error)")
        }
    }
    
    /// Alert moderators about detected crisis
    private func alertModerators(userId: String, result: CrisisDetectionResult) async throws {
        let alertData: [String: Any] = [
            "type": "crisis_alert",
            "userId": userId,
            "crisisTypes": result.crisisTypes.map { $0.rawValue },
            "urgencyLevel": result.urgencyLevel.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "pending"
        ]
        
        try await db.collection("moderatorAlerts")
            .addDocument(data: alertData)
        
        print("🚨 [CRISIS] Moderators alerted for user \(userId)")
    }
}
