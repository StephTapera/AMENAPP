//
//  DailyVerseGenkitService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  AI-powered daily verse generation using Genkit
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Daily Verse Genkit Service

@MainActor
class DailyVerseGenkitService: ObservableObject {
    static let shared = DailyVerseGenkitService()
    
    @Published var isGenerating = false
    @Published var lastError: (any Error)?
    @Published var todayVerse: PersonalizedDailyVerse?
    
    nonisolated private let genkitEndpoint: String
    nonisolated private let db = Firestore.firestore()
    nonisolated private let cacheKey = "cachedDailyVerse"
    nonisolated private let cacheDate = "cachedVerseDate"
    
    init() {
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "GENKIT_ENDPOINT") as? String {
            self.genkitEndpoint = endpoint
        } else {
            self.genkitEndpoint = "http://localhost:3400"
            print("⚠️ Using default Genkit endpoint for daily verse: \(self.genkitEndpoint)")
        }
        
        print("✅ DailyVerseGenkitService initialized")
        
        // Load cached verse asynchronously on the main actor
        Task {
            await self.loadCachedVerse()
        }
    }
    
    // MARK: - Generate Personalized Daily Verse
    
    /// Generate AI-personalized daily verse based on user context
    func generatePersonalizedDailyVerse(
        userContext: UserVerseContext? = nil,
        forceRefresh: Bool = false
    ) async throws -> PersonalizedDailyVerse {
        
        // Check cache first (only fetch once per day)
        if !forceRefresh, let cached = todayVerse, isSameDay(cached.date, Date()) {
            print("📖 Using cached daily verse")
            return cached
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("🤖 Generating personalized daily verse...")
        
        // Get user context if not provided
        var context = userContext
        if context == nil {
            context = try? await fetchUserContext()
        }
        
        // Call Genkit to generate personalized verse
        let response = try await callGenkitFlow(
            flowName: "generateDailyVerse",
            input: [
                "userInterests": context?.interests ?? [],
                "userChallenges": context?.currentChallenges ?? [],
                "userPrayerRequests": context?.recentPrayerTopics ?? [],
                "userMood": context?.mood ?? "hopeful",
                "date": ISO8601DateFormatter().string(from: Date()),
                "previousVerses": context?.recentVerses ?? []
            ]
        )
        
        guard let reference = response["reference"] as? String,
              let text = response["text"] as? String,
              let theme = response["theme"] as? String,
              let reflection = response["reflection"] as? String,
              let actionPrompt = response["actionPrompt"] as? String else {
            throw VerseError.invalidResponse
        }
        
        let relatedVerses = response["relatedVerses"] as? [String] ?? []
        let prayerPrompt = response["prayerPrompt"] as? String ?? ""
        
        let verse = PersonalizedDailyVerse(
            reference: reference,
            text: text,
            theme: theme,
            reflection: reflection,
            actionPrompt: actionPrompt,
            relatedVerses: relatedVerses,
            prayerPrompt: prayerPrompt,
            personalizedFor: context,
            date: Date()
        )
        
        // Cache it
        self.todayVerse = verse
        cacheVerse(verse)
        
        print("✅ Personalized daily verse generated:")
        print("   Reference: \(reference)")
        print("   Theme: \(theme)")
        
        return verse
    }
    
    // MARK: - Generate Themed Verse
    
    /// Generate verse for a specific theme or need
    func generateThemedVerse(theme: VerseTheme) async throws -> PersonalizedDailyVerse {
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("🤖 Generating verse for theme: \(theme.rawValue)")
        
        let response = try await callGenkitFlow(
            flowName: "generateThemedVerse",
            input: [
                "theme": theme.rawValue,
                "description": theme.description
            ]
        )
        
        guard let reference = response["reference"] as? String,
              let text = response["text"] as? String,
              let reflection = response["reflection"] as? String,
              let actionPrompt = response["actionPrompt"] as? String else {
            throw VerseError.invalidResponse
        }
        
        let verse = PersonalizedDailyVerse(
            reference: reference,
            text: text,
            theme: theme.rawValue,
            reflection: reflection,
            actionPrompt: actionPrompt,
            relatedVerses: response["relatedVerses"] as? [String] ?? [],
            prayerPrompt: response["prayerPrompt"] as? String ?? "",
            personalizedFor: nil,
            date: Date()
        )
        
        print("✅ Themed verse generated: \(reference)")
        
        return verse
    }
    
    // MARK: - Generate Verse Reflection
    
    /// AI-generated reflection on a specific verse
    func generateReflection(
        for verse: String,
        reference: String,
        userContext: String? = nil
    ) async throws -> VerseReflection {
        
        isGenerating = true
        defer { isGenerating = false }
        
        print("🤖 Generating reflection for: \(reference)")
        
        let response = try await callGenkitFlow(
            flowName: "generateVerseReflection",
            input: [
                "verse": verse,
                "reference": reference,
                "userContext": userContext ?? ""
            ]
        )
        
        guard let reflection = response["reflection"] as? String,
              let keyInsight = response["keyInsight"] as? String,
              let application = response["application"] as? String,
              let prayerPrompt = response["prayerPrompt"] as? String else {
            throw VerseError.invalidResponse
        }
        
        return VerseReflection(
            verse: verse,
            reference: reference,
            reflection: reflection,
            keyInsight: keyInsight,
            practicalApplication: application,
            prayerPrompt: prayerPrompt,
            relatedVerses: response["relatedVerses"] as? [String] ?? []
        )
    }
    
    // MARK: - Helper Methods
    
    private func callGenkitFlow(
        flowName: String,
        input: [String: Any]
    ) async throws -> [String: Any] {
        
        guard let url = URL(string: "\(genkitEndpoint)/\(flowName)") else {
            throw VerseError.invalidEndpoint
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": input])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerseError.requestFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ Genkit request failed with status: \(httpResponse.statusCode)")
            // Return fallback verse
            return createFallbackVerse()
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VerseError.invalidResponse
        }
        
        if let result = json["result"] as? [String: Any] {
            return result
        }
        
        return json
    }
    
    private func fetchUserContext() async throws -> UserVerseContext {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw VerseError.noUser
        }
        
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw VerseError.noUserData
        }
        
        // Fetch recent prayer requests
        let prayerSnapshot = try await db.collection("prayerRequests")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .getDocuments()
        
        let prayerTopics = prayerSnapshot.documents.compactMap { doc in
            doc.data()["topic"] as? String
        }
        
        return UserVerseContext(
            interests: data["interests"] as? [String] ?? [],
            currentChallenges: data["currentChallenges"] as? [String] ?? [],
            recentPrayerTopics: prayerTopics,
            mood: data["currentMood"] as? String ?? "hopeful",
            recentVerses: data["recentVerses"] as? [String] ?? []
        )
    }
    
    nonisolated private func createFallbackVerse() -> [String: Any] {
        let fallbackVerses: [[String: Any]] = [
            [
                "reference": "Philippians 4:13",
                "text": "I can do all things through Christ who strengthens me.",
                "theme": "Strength",
                "reflection": "God's strength is always available to us, empowering us to face any challenge.",
                "actionPrompt": "Today, ask God for strength in one specific area where you feel weak.",
                "relatedVerses": ["2 Corinthians 12:9", "Isaiah 40:31"],
                "prayerPrompt": "Lord, I need your strength today. Help me rely on you."
            ],
            [
                "reference": "Jeremiah 29:11",
                "text": "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
                "theme": "Hope",
                "reflection": "God has good plans for your life. Even in uncertainty, trust His perfect timing.",
                "actionPrompt": "Write down one area where you need to trust God's plan today.",
                "relatedVerses": ["Proverbs 3:5-6", "Romans 8:28"],
                "prayerPrompt": "Father, I trust your plans for my life. Guide me today."
            ],
            [
                "reference": "Psalm 46:10",
                "text": "Be still, and know that I am God.",
                "theme": "Peace",
                "reflection": "In the busyness of life, God invites us to rest in His presence and remember He is in control.",
                "actionPrompt": "Take 5 minutes today to be still and quiet before God.",
                "relatedVerses": ["Psalm 23:1-3", "Matthew 11:28"],
                "prayerPrompt": "God, help me find stillness in your presence today."
            ]
        ]
        
        return fallbackVerses.randomElement() ?? fallbackVerses[0]
    }
    
    nonisolated private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    // MARK: - Caching
    
    nonisolated private func cacheVerse(_ verse: PersonalizedDailyVerse) {
        if let encoded = try? JSONEncoder().encode(verse) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheDate)
        }
    }
    
    private func loadCachedVerse() async {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let date = UserDefaults.standard.object(forKey: cacheDate) as? Date,
              isSameDay(date, Date()),
              let verse = try? JSONDecoder().decode(PersonalizedDailyVerse.self, from: data) else {
            return
        }
        
        await MainActor.run {
            self.todayVerse = verse
            print("📖 Loaded cached verse: \(verse.reference)")
        }
    }
}

// MARK: - Data Models

struct PersonalizedDailyVerse: Codable, Identifiable {
    let id: UUID
    let reference: String
    let text: String
    let theme: String
    let reflection: String
    let actionPrompt: String
    let relatedVerses: [String]
    let prayerPrompt: String
    let personalizedFor: UserVerseContext?
    let date: Date
    
    init(reference: String, text: String, theme: String, reflection: String, actionPrompt: String, relatedVerses: [String], prayerPrompt: String, personalizedFor: UserVerseContext?, date: Date) {
        self.id = UUID()
        self.reference = reference
        self.text = text
        self.theme = theme
        self.reflection = reflection
        self.actionPrompt = actionPrompt
        self.relatedVerses = relatedVerses
        self.prayerPrompt = prayerPrompt
        self.personalizedFor = personalizedFor
        self.date = date
    }
    
    enum CodingKeys: String, CodingKey {
        case id, reference, text, theme, reflection, actionPrompt, relatedVerses, prayerPrompt, personalizedFor, date
    }
}

struct UserVerseContext: Codable {
    let interests: [String]
    let currentChallenges: [String]
    let recentPrayerTopics: [String]
    let mood: String
    let recentVerses: [String]
}

struct VerseReflection {
    let verse: String
    let reference: String
    let reflection: String
    let keyInsight: String
    let practicalApplication: String
    let prayerPrompt: String
    let relatedVerses: [String]
}

enum VerseTheme: String, CaseIterable {
    case strength = "Strength"
    case peace = "Peace"
    case hope = "Hope"
    case love = "Love"
    case faith = "Faith"
    case courage = "Courage"
    case forgiveness = "Forgiveness"
    case gratitude = "Gratitude"
    case guidance = "Guidance"
    case healing = "Healing"
    case patience = "Patience"
    case wisdom = "Wisdom"
    
    var description: String {
        switch self {
        case .strength: return "Finding strength in difficult times"
        case .peace: return "Inner peace and calm in chaos"
        case .hope: return "Hope for the future"
        case .love: return "God's love and loving others"
        case .faith: return "Growing and strengthening faith"
        case .courage: return "Courage to face challenges"
        case .forgiveness: return "Forgiving and being forgiven"
        case .gratitude: return "Thankfulness and appreciation"
        case .guidance: return "Seeking God's direction"
        case .healing: return "Emotional and spiritual healing"
        case .patience: return "Patience in waiting"
        case .wisdom: return "Wisdom and discernment"
        }
    }
    
    var icon: String {
        switch self {
        case .strength: return "bolt.fill"
        case .peace: return "leaf.fill"
        case .hope: return "sunrise.fill"
        case .love: return "heart.fill"
        case .faith: return "hands.sparkles.fill"
        case .courage: return "shield.fill"
        case .forgiveness: return "arrow.uturn.left.circle.fill"
        case .gratitude: return "gift.fill"
        case .guidance: return "map.fill"
        case .healing: return "heart.text.square.fill"
        case .patience: return "hourglass"
        case .wisdom: return "brain.head.profile"
        }
    }
}

enum VerseError: LocalizedError {
    case invalidEndpoint
    case requestFailed
    case invalidResponse
    case noUser
    case noUserData
    
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid Genkit endpoint"
        case .requestFailed:
            return "Request to Genkit failed"
        case .invalidResponse:
            return "Invalid response from Genkit"
        case .noUser:
            return "No authenticated user"
        case .noUserData:
            return "User data not found"
        }
    }
}

