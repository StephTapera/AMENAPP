import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SpiritualJourneyService {
    static let shared = SpiritualJourneyService()

    private let db = Firestore.firestore()

    func fetchOrGenerateStory(period: JourneyPeriod) async throws -> SpiritualJourneyStory {
        guard let uid = Auth.auth().currentUser?.uid else {
            return Self.demoStory(period: period)
        }

        if let cached = try await loadCachedStory(uid: uid, period: period) {
            return cached
        }

        if let generated = try await generateStoryFromFirestore(uid: uid, period: period) {
            try? await cacheStory(uid: uid, story: generated)
            return generated
        }

        let story = Self.demoStory(period: period)
        try? await cacheStory(uid: uid, story: story)
        return story
    }

    private func loadCachedStory(uid: String, period: JourneyPeriod) async throws -> SpiritualJourneyStory? {
        let docId = "latest_\(period.rawValue)"
        let snap = try await db.collection("users/\(uid)/spiritualJourneyStories")
            .document(docId)
            .getDocument()
        guard let data = snap.data() else { return nil }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(SpiritualJourneyStory.self, from: json)
    }

    private func cacheStory(uid: String, story: SpiritualJourneyStory) async throws {
        let docId = "latest_\(story.period.rawValue)"
        let data = try Firestore.Encoder().encode(story)
        try await db.collection("users/\(uid)/spiritualJourneyStories")
            .document(docId)
            .setData(data, merge: true)
    }

    private func generateStoryFromFirestore(uid: String, period: JourneyPeriod) async throws -> SpiritualJourneyStory? {
        let postsSnap = try await db.collection("posts")
            .whereField("authorId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        let texts = postsSnap.documents.compactMap { $0.data()["content"] as? String }
        guard !texts.isEmpty else { return nil }

        let combined = texts.joined(separator: " ")
        let emotion = detectEmotionProfile(in: combined)
        let topThemes = detectThemes(in: combined)

        let summary = SpiritualJourneySummary(
            activeDays: min(30, max(8, Int(Double(texts.count) * 0.6))),
            postsCount: texts.count,
            commentsCount: 0,
            prayersCount: 0,
            encouragementCount: estimateEncouragementCount(in: combined),
            comebackMoments: estimateComebacks(from: postsSnap.documents.count),
            topThemes: topThemes,
            emotionProfile: emotion,
            spiritualTone: deriveTone(from: emotion)
        )

        let slides = buildSlides(from: summary)

        return SpiritualJourneyStory(
            id: UUID().uuidString,
            userId: uid,
            period: period,
            generatedAt: Date(),
            summary: summary,
            slides: slides,
            safeShareCard: SpiritualJourneyShareCard(
                title: "My Spiritual Journey",
                subtitle: "A season of perseverance and trust",
                highlights: ["\(summary.activeDays) active days", "\(summary.encouragementCount) people encouraged"],
                blessing: "Keep going. Grace is with you."
            ),
            version: 1
        )
    }

    private func detectEmotionProfile(in text: String) -> EmotionProfile {
        let lowered = text.lowercased()
        let joy = score(words: ["joy", "grateful", "thankful", "praise", "rejoice"], in: lowered)
        let peace = score(words: ["peace", "calm", "rest", "still"], in: lowered)
        let gratitude = score(words: ["grateful", "thank", "thankful"], in: lowered)
        let grief = score(words: ["sad", "grief", "cry", "broken", "loss"], in: lowered)
        let stress = score(words: ["anxious", "anxiety", "worried", "overwhelmed"], in: lowered)
        let doubt = score(words: ["doubt", "confused", "question"], in: lowered)
        let perseverance = score(words: ["keep going", "persist", "endure", "still here"], in: lowered)

        return EmotionProfile(
            joy: joy,
            peace: peace,
            gratitude: gratitude,
            grief: grief,
            stress: stress,
            doubt: doubt,
            perseverance: perseverance
        )
    }

    private func detectThemes(in text: String) -> [String] {
        let lowered = text.lowercased()
        let themes: [(String, [String])] = [
            ("Healing", ["heal", "healing", "restore"]),
            ("Prayer", ["prayer", "pray", "praying"]),
            ("Trust", ["trust", "faith", "believe"]),
            ("Hope", ["hope", "hopeful"]),
            ("Forgiveness", ["forgive", "forgiveness"]),
            ("Peace", ["peace", "rest"]) 
        ]

        var scored: [(String, Int)] = []
        for (theme, words) in themes {
            let count = words.reduce(0) { $0 + occurrences(of: $1, in: lowered) }
            scored.append((theme, count))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 }
    }

    private func estimateEncouragementCount(in text: String) -> Int {
        let count = occurrences(of: "praying", in: text.lowercased())
            + occurrences(of: "encourag", in: text.lowercased())
            + occurrences(of: "with you", in: text.lowercased())
        return max(3, min(30, count))
    }

    private func estimateComebacks(from totalPosts: Int) -> Int {
        return max(1, min(3, totalPosts / 20))
    }

    private func deriveTone(from profile: EmotionProfile) -> SpiritualTone {
        if profile.grief > 0.25 || profile.stress > 0.25 { return .persevering }
        if profile.joy > 0.5 || profile.gratitude > 0.5 { return .growing }
        return .steady
    }

    private func buildSlides(from summary: SpiritualJourneySummary) -> [SpiritualJourneySlide] {
        return Self.demoStory(period: .monthly).slides
    }

    private func score(words: [String], in text: String) -> Double {
        let total = words.reduce(0) { $0 + occurrences(of: $1, in: text) }
        return min(1.0, Double(total) / 8.0)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func demoStory(period: JourneyPeriod) -> SpiritualJourneyStory {
        let summary = SpiritualJourneySummary(
            activeDays: 18,
            postsCount: 11,
            commentsCount: 24,
            prayersCount: 5,
            encouragementCount: 12,
            comebackMoments: 2,
            topThemes: ["Healing", "Prayer", "Trust"],
            emotionProfile: EmotionProfile(
                joy: 0.54,
                peace: 0.31,
                gratitude: 0.61,
                grief: 0.24,
                stress: 0.28,
                doubt: 0.11,
                perseverance: 0.67
            ),
            spiritualTone: .persevering
        )

        let slides: [SpiritualJourneySlide] = [
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .intro,
                title: "Your Spiritual Journey",
                subtitle: "A look back at this season",
                body: nil,
                accentText: nil,
                metrics: [],
                chips: [],
                mood: .warm,
                scripture: nil,
                shareSafe: true,
                animationStyle: .riseFade,
                duration: 4.5
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .consistency,
                title: "You showed up",
                subtitle: "18 days this month",
                body: "Even in quiet moments, you kept coming back.",
                accentText: "18",
                metrics: [JourneyMetric(label: "Active days", value: "18", rawValue: 18)],
                chips: [],
                mood: .bright,
                scripture: nil,
                shareSafe: true,
                animationStyle: .countUp,
                duration: 5.0
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .emotionRhythm,
                title: "Your emotional rhythm",
                subtitle: "Gratitude and perseverance led the way",
                body: nil,
                accentText: nil,
                metrics: [],
                chips: ["Gratitude", "Persevering", "Honest"],
                mood: .calm,
                scripture: nil,
                shareSafe: false,
                animationStyle: .radialPulse,
                duration: 5.5
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .topThemes,
                title: "Themes you returned to",
                subtitle: "Healing, Prayer, Trust",
                body: "Your reflections kept circling back to hope.",
                accentText: nil,
                metrics: [],
                chips: ["Healing", "Prayer", "Trust"],
                mood: .reflective,
                scripture: nil,
                shareSafe: true,
                animationStyle: .staggerWords,
                duration: 5.0
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .communityImpact,
                title: "You encouraged others",
                subtitle: "12 people felt your support",
                body: "Your words carried comfort more often than you realized.",
                accentText: "12",
                metrics: [JourneyMetric(label: "Encouraged", value: "12", rawValue: 12)],
                chips: [],
                mood: .warm,
                scripture: nil,
                shareSafe: true,
                animationStyle: .countUp,
                duration: 5.0
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .comeback,
                title: "You returned",
                subtitle: "After a quieter stretch",
                body: "That return mattered.",
                accentText: nil,
                metrics: [],
                chips: [],
                mood: .hopeful,
                scripture: nil,
                shareSafe: true,
                animationStyle: .timelineDraw,
                duration: 5.5
            ),
            SpiritualJourneySlide(
                id: UUID().uuidString,
                type: .blessing,
                title: "Keep going",
                subtitle: "What felt small still mattered",
                body: "Grace was present in more places than you knew.",
                accentText: nil,
                metrics: [],
                chips: [],
                mood: .calm,
                scripture: JourneyScripture(reference: "Galatians 6:9", text: "Let us not become weary in doing good..."),
                shareSafe: true,
                animationStyle: .softBloom,
                duration: 6.0
            )
        ]

        return SpiritualJourneyStory(
            id: UUID().uuidString,
            userId: Auth.auth().currentUser?.uid ?? "demo",
            period: period,
            generatedAt: Date(),
            summary: summary,
            slides: slides,
            safeShareCard: SpiritualJourneyShareCard(
                title: "My Spiritual Journey",
                subtitle: "A season of perseverance and trust",
                highlights: ["18 active days", "12 people encouraged"],
                blessing: "Keep going. Grace is with you."
            ),
            version: 1
        )
    }
}

@MainActor
final class SpiritualJourneyViewModel: ObservableObject {
    enum PlaybackState: Equatable {
        case loading
        case ready
        case playing
        case paused
        case completed
        case failed(String)
    }

    @Published var state: PlaybackState = .loading
    @Published var story: SpiritualJourneyStory?
    @Published var currentSlideIndex: Int = 0
    @Published var progress: Double = 0

    private var autoAdvanceTask: Task<Void, Never>?

    func loadStory(period: JourneyPeriod) async {
        state = .loading
        do {
            let loaded = try await SpiritualJourneyService.shared.fetchOrGenerateStory(period: period)
            story = loaded
            currentSlideIndex = 0
            progress = 0
            state = .ready
            play()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func play() {
        guard let story else { return }
        state = .playing
        autoAdvanceTask?.cancel()

        autoAdvanceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard case .playing = self.state else { return }
                let currentDuration = story.slides[self.currentSlideIndex].duration
                let steps = 60
                for step in 0..<steps {
                    try? await Task.sleep(nanoseconds: UInt64((currentDuration / Double(steps)) * 1_000_000_000))
                    if case .paused = self.state { return }
                    self.progress = Double(step + 1) / Double(steps)
                }
                self.advance()
            }
        }
    }

    func pause() {
        state = .paused
        autoAdvanceTask?.cancel()
    }

    func resume() {
        guard story != nil else { return }
        play()
    }

    func advance() {
        guard let story else { return }
        if currentSlideIndex < story.slides.count - 1 {
            currentSlideIndex += 1
            progress = 0
            play()
        } else {
            state = .completed
            autoAdvanceTask?.cancel()
        }
    }

    func goBack() {
        guard currentSlideIndex > 0 else { return }
        currentSlideIndex -= 1
        progress = 0
        play()
    }
}
