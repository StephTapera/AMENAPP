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
import FirebaseFunctions
import Combine

// MARK: - Daily Verse Genkit Service

@MainActor
class DailyVerseGenkitService: ObservableObject {
    static let shared = DailyVerseGenkitService()
    
    @Published var isGenerating = false
    @Published var lastError: (any Error)?
    @Published var todayVerse: PersonalizedDailyVerse?

    // In-flight continuation set — prevents duplicate Cloud Function calls when two callers
    // (DailyVerseBanner + AIDailyVerseView) both invoke generatePersonalizedDailyVerse()
    // before the first call completes. We store continuations rather than holding a Task so
    // that each caller's own task cancellation is handled independently without tearing down
    // the shared generation work (which caused asyncLet_finish_after_task_completion crashes).
    private var pendingContinuations: [CheckedContinuation<PersonalizedDailyVerse, Never>] = []
    private var isGeneratingInternally = false
    
    nonisolated private let db = Firestore.firestore()
    nonisolated private let functions = Functions.functions(region: "us-central1")
    nonisolated private let cacheKey = "cachedDailyVerse"
    nonisolated private let cacheDate = "cachedVerseDate"
    
    init() {
        print("✅ DailyVerseGenkitService initialized with Firebase Cloud Functions")
    }
    
    // MARK: - Generate Personalized Daily Verse
    
    /// Generate AI-personalized daily verse based on user context.
    ///
    /// Safe to call from multiple concurrent callers: the first call fires the Cloud Function
    /// and all subsequent callers wait on a continuation queue. When the result is ready every
    /// caller is resumed. This avoids the detached-Task pattern that caused the
    /// `asyncLet_finish_after_task_completion` SIGABRT on TestFlight.
    func generatePersonalizedDailyVerse(
        userContext: UserVerseContext? = nil,
        forceRefresh: Bool = false
    ) async -> PersonalizedDailyVerse {
        
        // Check cache first (only fetch once per day)
        if !forceRefresh, let cached = todayVerse, isSameDay(cached.date, Date()) {
            print("📖 Using cached daily verse")
            return cached
        }

        // All callers (including the first) park on the continuation queue.
        // A single Task.detached runs the actual Firebase call, isolating it from
        // any caller's task cancellation (which caused asyncLet_finish_after_task_completion).
        if !isGeneratingInternally {
            isGeneratingInternally = true
            // Detached: does NOT inherit the calling task's cancellation token.
            Task.detached { [weak self] in
                guard let self else { return }
                let verse = await self._generateVerseImpl(userContext: userContext)
                // Must hop back to MainActor to mutate shared state.
                await MainActor.run {
                    self.isGeneratingInternally = false
                    let waiting = self.pendingContinuations
                    self.pendingContinuations.removeAll()
                    for continuation in waiting {
                        continuation.resume(returning: verse)
                    }
                }
            }
        }

        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
    }

    @MainActor
    private func _generateVerseImpl(userContext: UserVerseContext?) async -> PersonalizedDailyVerse {
        isGenerating = true
        defer { isGenerating = false }
        
        print("🤖 Generating personalized daily verse via Genkit...")

        // Fetch user context for personalization
        var context = userContext
        if context == nil {
            context = try? await fetchUserContext()
        }

        do {
            // Call Cloud Function with user context
            let callable = functions.httpsCallable("generateDailyVerse")
            let input: [String: Any] = [
                "goals": context?.interests ?? [],
                "recentTopics": context?.currentChallenges ?? [],
                "prayerThemes": context?.recentPrayerTopics ?? []
            ]
            let result = try await callable.call(input)
            let data = result.data as? [String: Any] ?? [:]
            let verseData = data["verse"] as? [String: Any] ?? [:]

            let verse = PersonalizedDailyVerse(
                reference: verseData["reference"] as? String ?? "Romans 8:28",
                text: verseData["text"] as? String ?? "And we know that in all things God works for the good of those who love him.",
                theme: verseData["theme"] as? String ?? "Trust",
                reflection: verseData["reflection"] as? String ?? "God is working all things for your good.",
                actionPrompt: verseData["prayer"] as? String ?? "Trust God with one area of your life today.",
                relatedVerses: [],
                prayerPrompt: verseData["prayer"] as? String ?? "Lord, I trust your plans for my life.",
                personalizedFor: context,
                date: Date()
            )

            self.todayVerse = verse
            cacheVerse(verse)
            print("✅ Cloud Function verse: \(verse.reference) — \(verse.theme)")
            return verse

        } catch {
            // Cloud Function unavailable — use curated fallback rotation
            print("⚠️ Cloud Function unavailable (\(error.localizedDescription)) — using fallback verse")
            let fallbackData = createFallbackVerse()
            let verse = PersonalizedDailyVerse(
                reference: fallbackData["reference"] as? String ?? "Romans 8:28",
                text: fallbackData["text"] as? String ?? "And we know that in all things God works for the good of those who love him.",
                theme: fallbackData["theme"] as? String ?? "Trust",
                reflection: fallbackData["reflection"] as? String ?? "God is working all things for your good.",
                actionPrompt: fallbackData["actionPrompt"] as? String ?? "Trust God with one area of your life today.",
                relatedVerses: fallbackData["relatedVerses"] as? [String] ?? [],
                prayerPrompt: fallbackData["prayerPrompt"] as? String ?? "Lord, I trust your plans for my life.",
                personalizedFor: nil,
                date: Date()
            )
            self.todayVerse = verse
            cacheVerse(verse)
            return verse
        }
    }
    
    // MARK: - Generate Themed Verse
    
    /// Generate verse for a specific theme or need
    func generateThemedVerse(theme: VerseTheme) async -> PersonalizedDailyVerse {
        
        isGenerating = true
        defer { isGenerating = false }
        
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
        
        let callable = functions.httpsCallable("generateVerseReflection")
        let result = try await callable.call(["reference": reference, "verseText": verse])
        let data = result.data as? [String: Any] ?? [:]
        let reflData = data["reflection"] as? [String: Any] ?? [:]

        let reflectionText = reflData["reflection"] as? String
            ?? "This verse reminds us of God's faithfulness. Take time to meditate on these words."
        let journalPrompt = reflData["journalPrompt"] as? String
            ?? "How does this verse speak to what you're experiencing right now?"
        let prayerStarter = reflData["prayerStarter"] as? String
            ?? "Lord, help me understand and apply Your Word to my life..."

        return VerseReflection(
            verse: verse,
            reference: reference,
            reflection: reflectionText,
            keyInsight: journalPrompt,
            practicalApplication: "Reflect on how this verse applies to your current situation. Write down one way you can live out this truth today.",
            prayerPrompt: prayerStarter,
            relatedVerses: []
        )
    }
    
    // MARK: - Helper Methods
    
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
            ],
            [
                "reference": "Romans 8:28",
                "text": "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
                "theme": "Trust",
                "reflection": "Even when we can't see it, God is working everything together for our good.",
                "actionPrompt": "Reflect on a difficult situation and trust God is working in it.",
                "relatedVerses": ["Jeremiah 29:11", "Proverbs 3:5-6"],
                "prayerPrompt": "Lord, help me trust that you're working all things for my good."
            ],
            [
                "reference": "Matthew 11:28",
                "text": "Come to me, all you who are weary and burdened, and I will give you rest.",
                "theme": "Rest",
                "reflection": "Jesus invites us to bring our burdens to Him and find rest for our souls.",
                "actionPrompt": "Identify what's weighing you down and give it to Jesus in prayer.",
                "relatedVerses": ["Psalm 55:22", "1 Peter 5:7"],
                "prayerPrompt": "Jesus, I bring my burdens to you. Give me your rest."
            ]
        ]
        
        let selectedVerse = fallbackVerses.randomElement() ?? fallbackVerses[0]
        print("📖 Selected fallback verse: \(selectedVerse["reference"] ?? "Unknown")")
        return selectedVerse
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
    
    private func cacheVerse(_ verse: PersonalizedDailyVerse) {
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

    /// Used as a non-throwing fallback when the weak self capture is nil (extremely rare).
    static let placeholder = PersonalizedDailyVerse(
        reference: "Romans 8:28",
        text: "And we know that in all things God works for the good of those who love him.",
        theme: "Trust",
        reflection: "God is working all things for your good.",
        actionPrompt: "Trust God with one area of your life today.",
        relatedVerses: [],
        prayerPrompt: "Lord, I trust your plans for my life.",
        personalizedFor: nil,
        date: Date()
    )
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
    case noUser
    case noUserData
    
    var errorDescription: String? {
        switch self {
        case .noUser:
            return "No authenticated user"
        case .noUserData:
            return "User data not found"
        }
    }
}

