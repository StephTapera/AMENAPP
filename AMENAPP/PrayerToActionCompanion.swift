//
//  PrayerToActionCompanion.swift
//  AMENAPP
//
//  AI-powered prayer companion that:
//  - Extracts key information from prayer requests
//  - Generates "how to pray" prompts
//  - Suggests practical actions
//  - Protects privacy (optional sensitive details hiding)
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Prayer Analysis Result

struct PrayerAnalysis: Codable, Identifiable {
    let id: String
    let prayerId: String  // Original prayer post ID
    let authorId: String
    
    // Extracted information
    let summary: String              // One-line compassionate summary
    let keyThemes: [PrayerTheme]     // Health, grief, job, anxiety, etc.
    let urgency: PrayerUrgency       // Immediate, Soon, Ongoing, Answered
    let whoNeedsIt: String?          // Person/people mentioned
    
    // Generated guidance
    let prayerFocus: String          // 1-2 lines on how to pray
    let suggestedAction: PrayerAction?  // Optional practical action
    
    // Privacy
    let hasSensitiveDetails: Bool
    let hiddenDetails: [String]      // Names, locations to optionally hide
    
    // Metadata
    let createdAt: Date
    let lastUpdated: Date
    var authorApproved: Bool         // Author must approve before showing
    var isVisible: Bool              // Final visibility toggle
}

// MARK: - Prayer Themes

enum PrayerTheme: String, Codable, CaseIterable {
    case health = "Health & Healing"
    case grief = "Grief & Loss"
    case job = "Job & Finances"
    case anxiety = "Anxiety & Peace"
    case relationship = "Relationships"
    case family = "Family"
    case salvation = "Salvation"
    case guidance = "Guidance & Direction"
    case protection = "Protection & Safety"
    case thankfulness = "Thankfulness"
    case breakthrough = "Breakthrough"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .health: return "heart.text.square.fill"
        case .grief: return "cloud.rain.fill"
        case .job: return "briefcase.fill"
        case .anxiety: return "leaf.fill"
        case .relationship: return "person.2.fill"
        case .family: return "house.fill"
        case .salvation: return "cross.fill"
        case .guidance: return "map.fill"
        case .protection: return "shield.fill"
        case .thankfulness: return "hands.sparkles.fill"
        case .breakthrough: return "bolt.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .health: return "red"
        case .grief: return "blue"
        case .job: return "orange"
        case .anxiety: return "green"
        case .relationship: return "pink"
        case .family: return "purple"
        case .salvation: return "gold"
        case .guidance: return "teal"
        case .protection: return "indigo"
        case .thankfulness: return "yellow"
        case .breakthrough: return "cyan"
        case .other: return "gray"
        }
    }
}

// MARK: - Prayer Urgency

enum PrayerUrgency: String, Codable {
    case immediate = "Immediate"     // Emergency, crisis
    case soon = "Soon"               // Upcoming event, deadline
    case ongoing = "Ongoing"         // Long-term situation
    case answered = "Answered"       // Praise report
    
    var displayText: String {
        switch self {
        case .immediate: return "Pray now"
        case .soon: return "Pray soon"
        case .ongoing: return "Ongoing prayer"
        case .answered: return "Answered!"
        }
    }
    
    var color: String {
        switch self {
        case .immediate: return "red"
        case .soon: return "orange"
        case .ongoing: return "blue"
        case .answered: return "green"
        }
    }
}

// MARK: - Suggested Action

struct PrayerAction: Codable {
    let actionType: ActionType
    let description: String
    let optional: Bool  // User can toggle on/off
    
    enum ActionType: String, Codable {
        case message = "Send a message"
        case visit = "Offer to visit"
        case meal = "Bring a meal"
        case verse = "Share a verse"
        case call = "Make a call"
        case financial = "Offer financial help"
        case childcare = "Offer childcare"
        case prayer = "Pray together"
        case other = "Other support"
    }
    
    var icon: String {
        switch actionType {
        case .message: return "message.fill"
        case .visit: return "figure.walk"
        case .meal: return "fork.knife"
        case .verse: return "book.fill"
        case .call: return "phone.fill"
        case .financial: return "dollarsign.circle.fill"
        case .childcare: return "figure.and.child.holdinghands"
        case .prayer: return "hands.sparkles.fill"
        case .other: return "hand.raised.fill"
        }
    }
}

// MARK: - Prayer-to-Action Companion Service

@MainActor
class PrayerToActionCompanion: ObservableObject {
    static let shared = PrayerToActionCompanion()
    
    @Published var analyses: [String: PrayerAnalysis] = [:]  // prayerId -> analysis
    @Published var isProcessing = false
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Analyze Prayer
    
    /// Analyze a prayer request and generate companion card
    /// Note: This is a client-side analysis. In production, you'd call a Cloud Function with Vertex AI
    func analyzePrayer(postId: String, content: String, authorId: String) async -> PrayerAnalysis? {
        print("🙏 Analyzing prayer request...")
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Extract themes
        let themes = detectThemes(in: content)
        
        // Detect urgency
        let urgency = detectUrgency(in: content)
        
        // Extract who needs prayer
        let who = extractWhoNeedsIt(in: content)
        
        // Generate summary
        let summary = generateSummary(content: content, themes: themes, urgency: urgency)
        
        // Generate prayer focus
        let prayerFocus = generatePrayerFocus(themes: themes, urgency: urgency)
        
        // Suggest action
        let action = suggestAction(themes: themes, urgency: urgency)
        
        // Detect sensitive details
        let (hasSensitive, hiddenDetails) = detectSensitiveDetails(in: content)
        
        // Create analysis
        let analysis = PrayerAnalysis(
            id: UUID().uuidString,
            prayerId: postId,
            authorId: authorId,
            summary: summary,
            keyThemes: themes,
            urgency: urgency,
            whoNeedsIt: who,
            prayerFocus: prayerFocus,
            suggestedAction: action,
            hasSensitiveDetails: hasSensitive,
            hiddenDetails: hiddenDetails,
            createdAt: Date(),
            lastUpdated: Date(),
            authorApproved: false,  // Author must approve
            isVisible: false
        )
        
        // Cache locally
        analyses[postId] = analysis
        
        print("✅ Prayer analysis complete: \(themes.count) themes, urgency: \(urgency.rawValue)")
        
        return analysis
    }
    
    // MARK: - Theme Detection
    
    private func detectThemes(in content: String) -> [PrayerTheme] {
        let lowercased = content.lowercased()
        var themes: [PrayerTheme] = []
        
        // Health keywords
        if lowercased.contains("health") || lowercased.contains("sick") ||
           lowercased.contains("heal") || lowercased.contains("surgery") ||
           lowercased.contains("hospital") || lowercased.contains("doctor") ||
           lowercased.contains("cancer") || lowercased.contains("pain") {
            themes.append(.health)
        }
        
        // Grief keywords
        if lowercased.contains("grief") || lowercased.contains("loss") ||
           lowercased.contains("passed") || lowercased.contains("died") ||
           lowercased.contains("funeral") || lowercased.contains("mourning") {
            themes.append(.grief)
        }
        
        // Job/finances
        if lowercased.contains("job") || lowercased.contains("work") ||
           lowercased.contains("employment") || lowercased.contains("unemployed") ||
           lowercased.contains("finance") || lowercased.contains("money") ||
           lowercased.contains("bills") || lowercased.contains("debt") {
            themes.append(.job)
        }
        
        // Anxiety/peace
        if lowercased.contains("anxiety") || lowercased.contains("anxious") ||
           lowercased.contains("worry") || lowercased.contains("stress") ||
           lowercased.contains("peace") || lowercased.contains("calm") ||
           lowercased.contains("overwhelmed") {
            themes.append(.anxiety)
        }
        
        // Relationships
        if lowercased.contains("relationship") || lowercased.contains("marriage") ||
           lowercased.contains("spouse") || lowercased.contains("dating") ||
           lowercased.contains("divorce") || lowercased.contains("conflict") {
            themes.append(.relationship)
        }
        
        // Family
        if lowercased.contains("family") || lowercased.contains("children") ||
           lowercased.contains("parent") || lowercased.contains("child") ||
           lowercased.contains("kids") {
            themes.append(.family)
        }
        
        // Salvation
        if lowercased.contains("salvation") || lowercased.contains("saved") ||
           lowercased.contains("accept christ") || lowercased.contains("lost") {
            themes.append(.salvation)
        }
        
        // Guidance
        if lowercased.contains("guidance") || lowercased.contains("direction") ||
           lowercased.contains("decision") || lowercased.contains("wisdom") ||
           lowercased.contains("calling") {
            themes.append(.guidance)
        }
        
        // Protection
        if lowercased.contains("protection") || lowercased.contains("safety") ||
           lowercased.contains("danger") || lowercased.contains("secure") {
            themes.append(.protection)
        }
        
        // Thankfulness (praise reports)
        if lowercased.contains("thank") || lowercased.contains("grateful") ||
           lowercased.contains("blessed") || lowercased.contains("praise") {
            themes.append(.thankfulness)
        }
        
        // Breakthrough
        if lowercased.contains("breakthrough") || lowercased.contains("miracle") ||
           lowercased.contains("impossible") {
            themes.append(.breakthrough)
        }
        
        // Default to "other" if no themes detected
        if themes.isEmpty {
            themes.append(.other)
        }
        
        return Array(Set(themes))  // Remove duplicates
    }
    
    // MARK: - Urgency Detection
    
    private func detectUrgency(in content: String) -> PrayerUrgency {
        let lowercased = content.lowercased()
        
        // Answered prayer
        if lowercased.contains("answered") || lowercased.contains("praise") ||
           lowercased.contains("god did it") || lowercased.contains("testimony") {
            return .answered
        }
        
        // Immediate/emergency
        if lowercased.contains("urgent") || lowercased.contains("emergency") ||
           lowercased.contains("critical") || lowercased.contains("right now") ||
           lowercased.contains("immediately") || lowercased.contains("tonight") ||
           lowercased.contains("today") {
            return .immediate
        }
        
        // Soon (upcoming events)
        if lowercased.contains("tomorrow") || lowercased.contains("next week") ||
           lowercased.contains("upcoming") || lowercased.contains("this week") {
            return .soon
        }
        
        // Default: ongoing
        return .ongoing
    }
    
    // MARK: - Extract Who Needs It
    
    private func extractWhoNeedsIt(in content: String) -> String? {
        let lowercased = content.lowercased()
        
        if lowercased.contains("my mom") || lowercased.contains("my mother") {
            return "Mother"
        } else if lowercased.contains("my dad") || lowercased.contains("my father") {
            return "Father"
        } else if lowercased.contains("my wife") {
            return "Wife"
        } else if lowercased.contains("my husband") {
            return "Husband"
        } else if lowercased.contains("my friend") {
            return "Friend"
        } else if lowercased.contains("my family") {
            return "Family"
        } else if lowercased.contains("myself") || lowercased.contains("for me") {
            return "Self"
        }
        
        return nil
    }
    
    // MARK: - Generate Summary
    
    private func generateSummary(content: String, themes: [PrayerTheme], urgency: PrayerUrgency) -> String {
        // Take first 100 chars as base
        let preview = String(content.prefix(100))
        
        // Add context
        let themeText = themes.first?.rawValue ?? "Prayer"
        let urgencyText = urgency == .immediate ? " (Urgent)" : ""
        
        return "\(themeText) prayer\(urgencyText): \(preview)..."
    }
    
    // MARK: - Generate Prayer Focus
    
    private func generatePrayerFocus(themes: [PrayerTheme], urgency: PrayerUrgency) -> String {
        guard let mainTheme = themes.first else {
            return "Lift this situation to God in prayer"
        }
        
        switch mainTheme {
        case .health:
            return urgency == .immediate ? 
                "Pray for immediate healing and comfort. Ask God to guide doctors and bring peace." :
                "Pray for strength, healing, and God's presence through this health journey."
            
        case .grief:
            return "Pray for comfort and peace. Ask God to hold them close and remind them they're not alone."
            
        case .job:
            return "Pray for God's provision and open doors. Ask for wisdom in decisions and peace in waiting."
            
        case .anxiety:
            return "Pray for God's perfect peace. Ask Him to calm fears and replace worry with trust."
            
        case .relationship:
            return "Pray for reconciliation and healing. Ask God to soften hearts and bring understanding."
            
        case .family:
            return "Pray for God's protection over their family and unity in His love."
            
        case .salvation:
            return "Pray for the Holy Spirit to draw them to Christ. Ask God to open their heart."
            
        case .guidance:
            return "Pray for wisdom and clarity. Ask God to illuminate the path forward."
            
        case .protection:
            return "Pray for God's hedge of protection. Ask for safety and security."
            
        case .thankfulness:
            return "Give thanks with them! Celebrate God's faithfulness and goodness."
            
        case .breakthrough:
            return "Pray in faith for God's miracle. Nothing is impossible with Him."
            
        case .other:
            return "Lift this need to God. Ask Him to move powerfully on their behalf."
        }
    }
    
    // MARK: - Suggest Action
    
    private func suggestAction(themes: [PrayerTheme], urgency: PrayerUrgency) -> PrayerAction? {
        guard let mainTheme = themes.first else { return nil }
        
        switch mainTheme {
        case .health:
            if urgency == .immediate {
                return PrayerAction(
                    actionType: .message,
                    description: "Send them encouragement today",
                    optional: true
                )
            } else {
                return PrayerAction(
                    actionType: .meal,
                    description: "Offer to bring a meal this week",
                    optional: true
                )
            }
            
        case .grief:
            return PrayerAction(
                actionType: .visit,
                description: "Ask if they'd like company or just need someone to listen",
                optional: true
            )
            
        case .job:
            return PrayerAction(
                actionType: .message,
                description: "Offer to review their resume or connect them with contacts",
                optional: true
            )
            
        case .anxiety:
            return PrayerAction(
                actionType: .verse,
                description: "Share Philippians 4:6-7 or Psalm 23 if welcome",
                optional: true
            )
            
        case .relationship:
            return PrayerAction(
                actionType: .prayer,
                description: "Offer to pray with them (in person or call)",
                optional: true
            )
            
        case .family:
            return PrayerAction(
                actionType: .childcare,
                description: "Offer to help with kids so they can have a break",
                optional: true
            )
            
        default:
            return PrayerAction(
                actionType: .message,
                description: "Text them today to let them know you're praying",
                optional: true
            )
        }
    }
    
    // MARK: - Detect Sensitive Details
    
    private func detectSensitiveDetails(in content: String) -> (Bool, [String]) {
        var hiddenDetails: [String] = []
        
        // Simple name detection (capitalized words that aren't common words)
        let words = content.split(separator: " ")
        for word in words {
            if word.first?.isUppercase == true && word.count > 2 {
                let wordStr = String(word).trimmingCharacters(in: .punctuationCharacters)
                // Skip common capitalized words
                if !["God", "Lord", "Jesus", "Christ", "Holy", "Spirit", "Bible", "Church"].contains(wordStr) {
                    hiddenDetails.append(wordStr)
                }
            }
        }
        
        let hasSensitive = !hiddenDetails.isEmpty
        return (hasSensitive, Array(Set(hiddenDetails)))  // Remove duplicates
    }
    
    // MARK: - Save Analysis
    
    /// Save prayer analysis to Firestore
    func saveAnalysis(_ analysis: PrayerAnalysis) async throws {
        let docRef = db.collection("prayer_analyses").document(analysis.id)
        try await docRef.setData(try Firestore.Encoder().encode(analysis))
        print("✅ Prayer analysis saved: \(analysis.id)")
    }
    
    // MARK: - Approve Analysis
    
    /// Author approves the analysis for public display
    func approveAnalysis(analysisId: String) async throws {
        guard let analysis = analyses.values.first(where: { $0.id == analysisId }) else {
            throw NSError(domain: "PrayerCompanion", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Analysis not found"])
        }
        
        var updatedAnalysis = analysis
        updatedAnalysis.authorApproved = true
        updatedAnalysis.isVisible = true
        
        try await saveAnalysis(updatedAnalysis)
        analyses[analysis.prayerId] = updatedAnalysis
        
        print("✅ Prayer analysis approved and visible")
    }
}

// MARK: - Firestore Schema

/*
 prayer_analyses/{analysisId}:
 {
   id: string
   prayerId: string
   authorId: string
   summary: string
   keyThemes: [string]
   urgency: string
   whoNeedsIt: string?
   prayerFocus: string
   suggestedAction: {
     actionType: string
     description: string
     optional: boolean
   }?
   hasSensitiveDetails: boolean
   hiddenDetails: [string]
   createdAt: timestamp
   lastUpdated: timestamp
   authorApproved: boolean
   isVisible: boolean
 }
 */
