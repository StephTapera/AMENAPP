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
        // Configure endpoint: Info.plist > Cloud Run (default)
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "GENKIT_ENDPOINT") as? String, !endpoint.isEmpty {
            self.genkitEndpoint = endpoint
            print("✅ DailyVerseGenkitService initialized with endpoint: \(endpoint)")
        } else {
            // Production & TestFlight: Use Cloud Run
            self.genkitEndpoint = "https://genkit-amen-78278013543.us-central1.run.app"
            print("✅ DailyVerseGenkitService initialized with Cloud Run endpoint")
            
            // 💡 For local development, you can override this in Info.plist:
            // <key>GENKIT_ENDPOINT</key>
            // <string>http://localhost:3400</string>
        }
        
        // ✅ FIXED: Don't call async methods in init()
        // The view's .task modifier will handle loading
    }
    
    // MARK: - Generate Personalized Daily Verse
    
    /// Generate AI-personalized daily verse based on user context
    func generatePersonalizedDailyVerse(
        userContext: UserVerseContext? = nil,
        forceRefresh: Bool = false
    ) async -> PersonalizedDailyVerse {
        
        // Check cache first (only fetch once per day)
        if !forceRefresh, let cached = todayVerse, isSameDay(cached.date, Date()) {
            print("📖 Using cached daily verse")
            return cached
        }
        
        await MainActor.run {
            isGenerating = true
        }
        
        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }
        
        print("🤖 Generating personalized daily verse...")
        
        // ⚠️ TEMPORARY: Use fallback verse instead of calling Genkit
        // TODO: Set up Genkit server or configure proper endpoint
        print("⚠️ Using fallback verse (Genkit server not available)")
        let fallbackData = createFallbackVerse()
        
        let verse = PersonalizedDailyVerse(
            reference: fallbackData["reference"] as? String ?? "Philippians 4:13",
            text: fallbackData["text"] as? String ?? "I can do all things through Christ who strengthens me.",
            theme: fallbackData["theme"] as? String ?? "Strength",
            reflection: fallbackData["reflection"] as? String ?? "God's strength is always available.",
            actionPrompt: fallbackData["actionPrompt"] as? String ?? "Trust God today.",
            relatedVerses: fallbackData["relatedVerses"] as? [String] ?? [],
            prayerPrompt: fallbackData["prayerPrompt"] as? String ?? "Lord, strengthen me.",
            personalizedFor: nil,
            date: Date()
        )
        
        // Cache it
        await MainActor.run {
            self.todayVerse = verse
        }
        cacheVerse(verse)
        
        print("✅ Fallback verse generated: \(verse.reference)")
        
        return verse
        
        /* ORIGINAL GENKIT CODE - Uncomment when Genkit server is ready
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
        
        return verse
        */
    }
    
    // MARK: - Generate Themed Verse
    
    /// Generate verse for a specific theme or need
    func generateThemedVerse(theme: VerseTheme) async -> PersonalizedDailyVerse {
        
        await MainActor.run {
            isGenerating = true
        }
        
        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }
        
        print("🤖 Generating verse for theme: \(theme.rawValue)")
        
        // Use fallback themed verses
        let fallbackData = createThemedFallbackVerse(theme: theme)
        
        let verse = PersonalizedDailyVerse(
            reference: fallbackData["reference"] as? String ?? "Psalm 23:1",
            text: fallbackData["text"] as? String ?? "The Lord is my shepherd; I shall not want.",
            theme: theme.rawValue,
            reflection: fallbackData["reflection"] as? String ?? "God provides for us.",
            actionPrompt: fallbackData["actionPrompt"] as? String ?? "Trust in God's provision.",
            relatedVerses: fallbackData["relatedVerses"] as? [String] ?? [],
            prayerPrompt: fallbackData["prayerPrompt"] as? String ?? "Lord, I trust you.",
            personalizedFor: nil,
            date: Date()
        )
        
        print("✅ Themed verse generated: \(verse.reference)")
        
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
        
        // If no endpoint, return a fallback reflection
        guard !genkitEndpoint.isEmpty else {
            print("⚠️ No Genkit endpoint - returning fallback reflection")
            return VerseReflection(
                verse: verse,
                reference: reference,
                reflection: "This verse reminds us of God's faithfulness and His promises to us. Take time to meditate on these words and let them speak to your heart.",
                keyInsight: "God's Word is living and active, offering guidance and comfort for every season of life.",
                practicalApplication: "Reflect on how this verse applies to your current situation. Write down one way you can live out this truth today.",
                prayerPrompt: "Lord, help me understand and apply Your Word to my life. Open my heart to receive what You want to teach me through this verse.",
                relatedVerses: []
            )
        }
        
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
        
        // If no endpoint configured, immediately return fallback
        guard !genkitEndpoint.isEmpty else {
            print("⚠️ No Genkit endpoint - using fallback")
            throw VerseError.invalidEndpoint
        }
        
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
    
    nonisolated private func createThemedFallbackVerse(theme: VerseTheme) -> [String: Any] {
        switch theme {
        case .strength:
            return [
                "reference": "Philippians 4:13",
                "text": "I can do all things through Christ who strengthens me.",
                "theme": "Strength",
                "reflection": "God's strength is made perfect in our weakness. When we feel inadequate, that's when His power shines through us most clearly.",
                "actionPrompt": "Identify one challenge today and ask God for His strength to face it.",
                "relatedVerses": ["2 Corinthians 12:9", "Isaiah 40:31", "Psalm 18:32"],
                "prayerPrompt": "Lord, strengthen me today. I rely on Your power, not my own."
            ]
        case .peace:
            return [
                "reference": "Philippians 4:6-7",
                "text": "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
                "theme": "Peace",
                "reflection": "God's peace isn't about the absence of problems, but the presence of God in the midst of them.",
                "actionPrompt": "Write down your worries and pray about each one, then release them to God.",
                "relatedVerses": ["John 14:27", "Psalm 29:11", "Isaiah 26:3"],
                "prayerPrompt": "Prince of Peace, calm my anxious heart. Give me Your perfect peace."
            ]
        case .hope:
            return [
                "reference": "Romans 15:13",
                "text": "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.",
                "theme": "Hope",
                "reflection": "Hope in God is not wishful thinking—it's confident expectation based on His promises.",
                "actionPrompt": "Find one promise in Scripture today and claim it as your own.",
                "relatedVerses": ["Jeremiah 29:11", "Psalm 42:5", "Hebrews 6:19"],
                "prayerPrompt": "God of hope, fill me with joy and peace as I trust in You."
            ]
        case .love:
            return [
                "reference": "1 John 4:19",
                "text": "We love because he first loved us.",
                "theme": "Love",
                "reflection": "God's love for us enables us to love others. His love is the source and power for all our relationships.",
                "actionPrompt": "Show God's love to someone today through a specific act of kindness.",
                "relatedVerses": ["John 3:16", "Romans 8:38-39", "1 Corinthians 13:4-7"],
                "prayerPrompt": "Father, help me love others as You have loved me."
            ]
        case .faith:
            return [
                "reference": "Hebrews 11:1",
                "text": "Now faith is confidence in what we hope for and assurance about what we do not see.",
                "theme": "Faith",
                "reflection": "Faith isn't blind—it's choosing to trust God's character even when we can't see His hand.",
                "actionPrompt": "Take one step of faith today in an area where you've been hesitating.",
                "relatedVerses": ["Romans 10:17", "James 2:17", "Mark 11:22-24"],
                "prayerPrompt": "Lord, increase my faith. Help me trust You more deeply."
            ]
        case .courage:
            return [
                "reference": "Joshua 1:9",
                "text": "Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",
                "theme": "Courage",
                "reflection": "Courage isn't the absence of fear, but moving forward despite fear because God is with us.",
                "actionPrompt": "Face one fear today, knowing God goes before you.",
                "relatedVerses": ["Psalm 27:1", "2 Timothy 1:7", "Deuteronomy 31:6"],
                "prayerPrompt": "God, give me courage to face today's challenges knowing You are with me."
            ]
        case .forgiveness:
            return [
                "reference": "Colossians 3:13",
                "text": "Bear with each other and forgive one another if any of you has a grievance against someone. Forgive as the Lord forgave you.",
                "theme": "Forgiveness",
                "reflection": "Forgiveness is releasing our right to hurt someone who has hurt us, just as God forgave us.",
                "actionPrompt": "Ask God to help you forgive someone who has wronged you.",
                "relatedVerses": ["Matthew 6:14-15", "Ephesians 4:32", "Luke 6:37"],
                "prayerPrompt": "Father, help me forgive as You have forgiven me."
            ]
        case .gratitude:
            return [
                "reference": "1 Thessalonians 5:18",
                "text": "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.",
                "theme": "Gratitude",
                "reflection": "Gratitude shifts our focus from what's missing to what's present, from problems to blessings.",
                "actionPrompt": "List three things you're grateful for today and thank God for each one.",
                "relatedVerses": ["Psalm 100:4", "Colossians 3:17", "Philippians 4:6"],
                "prayerPrompt": "Thank You, Lord, for Your countless blessings in my life."
            ]
        case .guidance:
            return [
                "reference": "Proverbs 3:5-6",
                "text": "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
                "theme": "Guidance",
                "reflection": "God's guidance comes as we trust Him, not as we figure everything out on our own.",
                "actionPrompt": "Ask God for direction in one specific decision you need to make.",
                "relatedVerses": ["Psalm 32:8", "James 1:5", "Isaiah 30:21"],
                "prayerPrompt": "Lord, guide my steps today. Show me Your path."
            ]
        case .healing:
            return [
                "reference": "Psalm 147:3",
                "text": "He heals the brokenhearted and binds up their wounds.",
                "theme": "Healing",
                "reflection": "God is near to the brokenhearted and brings healing to our deepest wounds, both physical and emotional.",
                "actionPrompt": "Bring your pain to God in prayer and ask for His healing touch.",
                "relatedVerses": ["Jeremiah 17:14", "1 Peter 2:24", "Psalm 30:2"],
                "prayerPrompt": "Great Physician, heal my heart and restore my soul."
            ]
        case .patience:
            return [
                "reference": "Romans 12:12",
                "text": "Be joyful in hope, patient in affliction, faithful in prayer.",
                "theme": "Patience",
                "reflection": "Patience is not passive waiting, but active trust in God's perfect timing.",
                "actionPrompt": "Practice patience in one frustrating situation today.",
                "relatedVerses": ["James 1:2-4", "Galatians 6:9", "Psalm 37:7"],
                "prayerPrompt": "Lord, teach me to wait on Your timing with patience and trust."
            ]
        case .wisdom:
            return [
                "reference": "James 1:5",
                "text": "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.",
                "theme": "Wisdom",
                "reflection": "True wisdom comes from God and leads us to make choices that honor Him and benefit others.",
                "actionPrompt": "Ask God for wisdom in one decision you're facing today.",
                "relatedVerses": ["Proverbs 2:6", "Colossians 3:16", "Proverbs 9:10"],
                "prayerPrompt": "Lord, grant me wisdom to navigate life's challenges according to Your will."
            ]
        }
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

