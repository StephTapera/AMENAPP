//
//  ChurchNotesFeatureViewModels.swift
//  AMENAPP
//
//  All ViewModels for the Church Notes smart feature suite.
//

import SwiftUI
import Combine
import AVFoundation

// MARK: - AIInsightsViewModel

@MainActor
final class AIInsightsViewModel: ObservableObject {
    @Published var insights: AIInsights?
    @Published var isLoading: Bool = false
    @Published var isExpanded: Bool = true
    @Published var hasEnoughText: Bool = false

    private var debounceTask: Task<Void, Never>?
    private let minimumTextLength = 60

    func analyzeText(_ text: String) async {
        hasEnoughText = text.count >= minimumTextLength
        guard hasEnoughText else {
            insights = nil
            return
        }

        // Cancel any pending analysis
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
                guard !Task.isCancelled else { return }
                isLoading = true
                // Simulate async work (replace with real API call)
                try await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }
                insights = generateMockInsights(for: text)
                isLoading = false
            } catch {
                isLoading = false
            }
        }
        await debounceTask?.value
    }

    func generateMockInsights(for text: String) -> AIInsights {
        let words = text.split(separator: " ").map(String.init)
        let significantWords = words.filter { $0.count > 4 }
        let themeWord = significantWords.first ?? "Faith"
        let theme = detectTheme(from: text, seed: themeWord)
        let score = Double.random(in: 0.65...0.95)

        let allActions = [
            "Meditate on this passage daily",
            "Share with your accountability partner",
            "Apply this truth to your current challenge",
            "Journal a personal response to this message",
            "Memorize the key scripture referenced",
            "Pray over the action steps mentioned",
            "Discuss with your small group this week"
        ]
        let actionItems = Array(allActions.shuffled().prefix(3))

        let sentences = text.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 20 }
        let keyQuote = sentences.max(by: { $0.count < $1.count }) ?? "God is faithful in every season."

        let keywords = extractKeywords(from: text)

        return AIInsights(
            detectedTheme: theme,
            emotionalDepthScore: score,
            actionItems: actionItems,
            keyQuote: keyQuote,
            topKeywords: keywords,
            generatedAt: Date()
        )
    }

    private func detectTheme(from text: String, seed: String) -> String {
        let lower = text.lowercased()
        let themes: [(keywords: [String], theme: String)] = [
            (["grace", "mercy", "forgiv"], "Grace & Forgiveness"),
            (["faith", "trust", "believ"], "Living by Faith"),
            (["prayer", "pray", "intercession"], "Prayer & Intercession"),
            (["identity", "purpose", "calling", "chosen"], "Identity in Christ"),
            (["hope", "future", "promise"], "Hope & Promise"),
            (["love", "compassion", "heart"], "Love of God"),
            (["spirit", "holy", "anointing"], "Holy Spirit"),
            (["obedience", "follow", "disciple"], "Discipleship"),
            (["worship", "praise", "glory"], "Worship & Praise"),
            (["heal", "restore", "renew"], "Healing & Restoration")
        ]
        for entry in themes {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return entry.theme
            }
        }
        return seed.prefix(1).uppercased() + seed.dropFirst() + " & Truth"
    }

    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "and", "that", "this", "with", "from", "have", "they", "will", "been", "were", "when", "your", "their"])
        let words = text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 4 && !stopWords.contains($0) }
        var freq: [String: Int] = [:]
        for word in words { freq[word, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }.prefix(5).map { $0.key.capitalized }
    }
}

// MARK: - ScriptureDNAViewModel

@MainActor
final class ScriptureDNAViewModel: ObservableObject {
    @Published var result: ScriptureDNAResult?
    @Published var isLoading: Bool = false
    @Published var isExpanded: Bool = false
    @Published var showWordMap: Bool = false

    private var debounceTask: Task<Void, Never>?

    // Known verse database
    private let knownVerses: [String: ScriptureDNAResult] = {
        var db: [String: ScriptureDNAResult] = [:]

        db["John 3:16"] = ScriptureDNAResult(
            id: UUID(),
            reference: "John 3:16",
            verseText: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "Romans 5:8", snippet: "But God demonstrates his own love for us in this: While we were still sinners, Christ died for us."),
                CrossRef(id: UUID(), reference: "1 John 4:9", snippet: "This is how God showed his love among us: He sent his one and only Son into the world."),
                CrossRef(id: UUID(), reference: "John 10:28", snippet: "I give them eternal life, and they shall never perish.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "loved", original: "ἀγαπάω", language: "Greek", definition: "agapaō — unconditional, self-sacrificing love; divine love that wills the good of another"),
                OriginalWord(id: UUID(), english: "only Son", original: "μονογενής", language: "Greek", definition: "monogenēs — unique, one of a kind; the only-begotten"),
                OriginalWord(id: UUID(), english: "eternal", original: "αἰώνιος", language: "Greek", definition: "aiōnios — pertaining to an age; everlasting, without beginning or end")
            ],
            keyThemes: ["God's Love", "Salvation", "Eternal Life", "The Son", "Belief"]
        )

        db["Romans 8:28"] = ScriptureDNAResult(
            id: UUID(),
            reference: "Romans 8:28",
            verseText: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "Genesis 50:20", snippet: "You intended to harm me, but God intended it for good."),
                CrossRef(id: UUID(), reference: "Jeremiah 29:11", snippet: "For I know the plans I have for you, declares the Lord, plans to prosper you.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "works together", original: "συνεργέω", language: "Greek", definition: "synergeo — to work together with; to cooperate toward an end"),
                OriginalWord(id: UUID(), english: "called", original: "κλητός", language: "Greek", definition: "klētos — divinely selected and appointed; called by God")
            ],
            keyThemes: ["Providence", "God's Purpose", "Calling", "Sovereignty", "Hope"]
        )

        db["Psalm 23:1"] = ScriptureDNAResult(
            id: UUID(),
            reference: "Psalm 23:1",
            verseText: "The Lord is my shepherd; I shall not want.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "John 10:11", snippet: "I am the good shepherd. The good shepherd lays down his life for the sheep."),
                CrossRef(id: UUID(), reference: "Ezekiel 34:15", snippet: "I myself will tend my sheep and have them lie down, declares the Sovereign Lord.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "shepherd", original: "רָעָה", language: "Hebrew", definition: "rā'āh — to tend, pasture, feed; to rule, govern with care"),
                OriginalWord(id: UUID(), english: "want", original: "חָסֵר", language: "Hebrew", definition: "ḥāsēr — to lack, be without, be in need of")
            ],
            keyThemes: ["Guidance", "Provision", "God as Shepherd", "Trust", "Rest"]
        )

        db["Philippians 4:13"] = ScriptureDNAResult(
            id: UUID(),
            reference: "Philippians 4:13",
            verseText: "I can do all this through him who gives me strength.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "2 Corinthians 12:9", snippet: "My grace is sufficient for you, for my power is made perfect in weakness."),
                CrossRef(id: UUID(), reference: "Isaiah 40:31", snippet: "Those who hope in the Lord will renew their strength.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "strength", original: "ἐνδυναμόω", language: "Greek", definition: "endynamoō — to make strong, empower; to increase in inner strength"),
                OriginalWord(id: UUID(), english: "all things", original: "πάντα", language: "Greek", definition: "panta — all, every, the totality; all circumstances without exception")
            ],
            keyThemes: ["Strength", "Contentment", "Christ-Dependence", "Endurance", "Peace"]
        )

        db["Jeremiah 29:11"] = ScriptureDNAResult(
            id: UUID(),
            reference: "Jeremiah 29:11",
            verseText: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "Romans 8:28", snippet: "And we know that in all things God works for the good of those who love him."),
                CrossRef(id: UUID(), reference: "Proverbs 19:21", snippet: "Many are the plans in a person's heart, but it is the Lord's purpose that prevails.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "plans", original: "מַחֲשָׁבָה", language: "Hebrew", definition: "maḥăšāḇāh — thoughts, purposes, plans; the deliberate intention of a mind"),
                OriginalWord(id: UUID(), english: "hope", original: "תִּקְוָה", language: "Hebrew", definition: "tiqwāh — hope, expectation; lit. a cord of hope binding one to the future")
            ],
            keyThemes: ["God's Plans", "Hope", "Future", "Providence", "Prosperity"]
        )

        return db
    }()

    func lookupScripture(_ ref: String) {
        guard ref.count > 4 else {
            result = nil
            return
        }

        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s debounce
                guard !Task.isCancelled else { return }

                isLoading = true
                try await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }

                // Check known verses first (case-insensitive partial match)
                let normalised = ref.trimmingCharacters(in: .whitespaces)
                if let known = knownVerses.first(where: { normalised.lowercased().contains($0.key.lowercased()) || $0.key.lowercased().contains(normalised.lowercased()) })?.value {
                    result = known
                } else {
                    result = generateMockResult(for: normalised)
                }
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    private func generateMockResult(for ref: String) -> ScriptureDNAResult {
        ScriptureDNAResult(
            id: UUID(),
            reference: ref,
            verseText: "Trust in the Lord with all your heart and lean not on your own understanding.",
            crossReferences: [
                CrossRef(id: UUID(), reference: "Psalm 37:5", snippet: "Commit your way to the Lord; trust in him and he will do this."),
                CrossRef(id: UUID(), reference: "Isaiah 26:4", snippet: "Trust in the Lord forever, for the Lord is the Rock eternal.")
            ],
            originalLanguageWords: [
                OriginalWord(id: UUID(), english: "trust", original: "בָּטַח", language: "Hebrew", definition: "bāṭaḥ — to trust, be confident; to feel safe, be careless of danger"),
                OriginalWord(id: UUID(), english: "understanding", original: "בִּינָה", language: "Hebrew", definition: "bînāh — understanding, discernment; the faculty of insight")
            ],
            keyThemes: ["Trust", "Wisdom", "Surrender", "God's Guidance"]
        )
    }
}

// MARK: - ChurchRadarViewModel

@MainActor
final class ChurchRadarViewModel: ObservableObject {
    @Published var nearbyChurches: [LiveChurch] = []
    @Published var isScanning: Bool = false
    @Published var sweepAngle: Double = 0

    private var sweepTimer: Timer?

    func startRadar() {
        guard !isScanning else { return }
        isScanning = true
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sweepAngle = (self.sweepAngle + 2).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    func stopRadar() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        isScanning = false
    }

    func loadNearbyChurches() {
        nearbyChurches = [
            LiveChurch(id: UUID(), name: "Hillsong Atlanta", pastorName: "Marcus Reid", distanceMiles: 0.8, isLive: true, sermonTitle: "Walk in the Light", latitude: 33.749, longitude: -84.388),
            LiveChurch(id: UUID(), name: "New Birth Missionary", pastorName: "Jamal Bryant", distanceMiles: 1.4, isLive: true, sermonTitle: "Season of Overflow", latitude: 33.731, longitude: -84.362),
            LiveChurch(id: UUID(), name: "Transformation Church", pastorName: "Michael Todd", distanceMiles: 2.1, isLive: false, sermonTitle: "Relationship Goals", latitude: 33.762, longitude: -84.401),
            LiveChurch(id: UUID(), name: "The Church at Brook Hills", pastorName: "David Platt", distanceMiles: 3.3, isLive: true, sermonTitle: "Radical Generosity", latitude: 33.721, longitude: -84.375),
            LiveChurch(id: UUID(), name: "Elevation Worship Center", pastorName: "Steven Furtick", distanceMiles: 4.7, isLive: false, sermonTitle: "Do It Again", latitude: 33.778, longitude: -84.410),
            LiveChurch(id: UUID(), name: "Grace Fellowship Atlanta", pastorName: "Dharius Daniels", distanceMiles: 5.2, isLive: true, sermonTitle: "Re-Present Jesus", latitude: 33.742, longitude: -84.342),
            LiveChurch(id: UUID(), name: "Word of Faith Family", pastorName: "Keith Battle", distanceMiles: 6.8, isLive: false, sermonTitle: "Faith for the Fire", latitude: 33.755, longitude: -84.418),
            LiveChurch(id: UUID(), name: "Greater Travelers Rest", pastorName: "Grainger Browning", distanceMiles: 8.0, isLive: true, sermonTitle: "God Is Not Done", latitude: 33.714, longitude: -84.355)
        ]
    }
}

// MARK: - VoiceToWisdomViewModel

@MainActor
final class VoiceToWisdomViewModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var waveformHeights: [CGFloat] = Array(repeating: 12, count: 10)
    @Published var transcribedText: String = ""

    private var elapsedTimer: Timer?
    private var waveformTimer: Timer?
    private var audioRecorder: AVAudioRecorder?

    func startRecording() {
        Task {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
            }
            guard granted else { return }
            beginRecordingSession()
        }
    }

    private func beginRecordingSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cn_voice_\(Date().timeIntervalSince1970).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
        } catch {
            print("[VoiceToWisdom] Recording session error: \(error)")
        }

        isRecording = true
        elapsedSeconds = 0
        transcribedText = ""

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.waveformHeights = (0..<10).map { _ in CGFloat.random(in: 4...32) }
            }
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
        waveformTimer?.invalidate(); waveformTimer = nil
        isRecording = false
        isProcessing = true
        waveformHeights = Array(repeating: 8, count: 10)

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            transcribedText = mockTranscription()
            isProcessing = false
        }
    }

    func formattedElapsed() -> String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    func cleanup() {
        audioRecorder?.stop()
        audioRecorder = nil
        elapsedTimer?.invalidate()
        waveformTimer?.invalidate()
        isRecording = false
        isProcessing = false
    }

    private func mockTranscription() -> String {
        "Today Pastor spoke on Philippians 4:13 — the idea that our strength doesn't come from our own willpower, but from Christ who continually empowers us. The Greek word 'endynamoō' means to be made strong from within. He challenged us: stop trying to carry your burdens alone. Surrender them at the altar and let the Holy Spirit renew your capacity daily. Three action steps: First, start each morning with a surrendered prayer. Second, identify one area where you're striving and release it. Third, memorize Philippians 4:13 and speak it when doubt rises."
    }
}

// MARK: - CommunityDuetViewModel

@MainActor
final class CommunityDuetViewModel: ObservableObject {
    @Published var communityNotes: [CommunityNote] = []
    @Published var searchText: String = ""
    @Published var filteredNotes: [CommunityNote] = []

    func loadCommunityNotes() {
        let raw: [(name: String, initials: String, color: String, snippet: String, ref: String, church: String, likes: Int)] = [
            ("Aisha Okonkwo", "AO", "A855F7", "God's love is not conditional on our performance — it's the foundation we build from, not the reward we earn.", "Romans 5:8", "New Birth Missionary", 42),
            ("Marcus Webb", "MW", "4A9EFF", "Pastor challenged us: your faith isn't measured in church attendance, but in how you love people on Monday morning.", "James 2:17", "Hillsong Atlanta", 38),
            ("Destiny Flowers", "DF", "34D399", "The Holy Spirit doesn't just comfort — He equips. Today I felt equipped to face what I've been avoiding.", "John 14:26", "Transformation Church", 61),
            ("Jordan Price", "JP", "D4A843", "Surrender isn't weakness. It's the bravest thing a believer can do — to trust God with the outcome.", "Proverbs 3:5", "The Church at Brook Hills", 29),
            ("Imani Torres", "IT", "FB7185", "We are not defined by our past seasons. God's mercies are new every morning — that's not a cliché, it's a covenant.", "Lamentations 3:23", "Grace Fellowship", 55),
            ("Caleb Mensah", "CM", "22D3EE", "The enemy wants you distracted by what you lack. God wants you grateful for what He's already placed in your hands.", "Philippians 4:11", "Word of Faith Family", 33),
            ("Naomi Grant", "NG", "FB923C", "Worship isn't a moment — it's a posture. You can live a life of worship in the grocery store, at work, everywhere.", "Romans 12:1", "Greater Travelers Rest", 48),
            ("Elijah Cross", "EC", "A855F7", "God doesn't call the equipped. He equips the called. Stop waiting until you feel ready.", "Exodus 4:12", "New Birth Missionary", 71),
            ("Priya Sundar", "PS", "4A9EFF", "Today's message hit different — healing is a process. Don't rush God's timeline in your restoration season.", "Psalm 147:3", "Hillsong Atlanta", 26),
            ("Andre Williams", "AW", "34D399", "Community is the context for discipleship. You cannot grow in isolation. Iron sharpens iron — find your people.", "Proverbs 27:17", "Transformation Church", 44),
            ("Faith Osei", "FO", "D4A843", "The sermon this morning: God is not waiting for you to clean yourself up before He receives you. Come as you are.", "Luke 15:20", "Elevation Worship Center", 67),
            ("Samuel Oduya", "SO", "FB7185", "The deeper you go in prayer, the clearer everything else becomes. Stillness is a spiritual discipline.", "Psalm 46:10", "Grace Fellowship", 39)
        ]

        let calendar = Calendar.current
        communityNotes = raw.enumerated().map { idx, r in
            CommunityNote(
                id: UUID(),
                authorName: r.name,
                authorInitials: r.initials,
                avatarColorHex: r.color,
                noteSnippet: r.snippet,
                scriptureRef: r.ref,
                churchName: r.church,
                likeCount: r.likes,
                postedAt: calendar.date(byAdding: .hour, value: -(idx * 3 + Int.random(in: 0...5)), to: Date()) ?? Date()
            )
        }
        filteredNotes = communityNotes
    }

    func filterNotes() {
        guard !searchText.isEmpty else {
            filteredNotes = communityNotes
            return
        }
        let q = searchText.lowercased()
        filteredNotes = communityNotes.filter {
            $0.noteSnippet.lowercased().contains(q) ||
            $0.scriptureRef.lowercased().contains(q) ||
            $0.authorName.lowercased().contains(q) ||
            $0.churchName.lowercased().contains(q)
        }
    }

    func stitchNote(_ note: CommunityNote, into bodyText: inout String) {
        let block = """


— Stitched from \(note.authorName) (\(note.churchName))
"\(note.noteSnippet)"
[\(note.scriptureRef)]
"""
        bodyText += block
    }
}

// MARK: - QuoteForgeViewModel

@MainActor
final class QuoteForgeViewModel: ObservableObject {
    @Published var detectedQuote: String = ""
    @Published var selectedStyleIndex: Int = 0
    @Published var isVisible: Bool = false

    let reelStyles: [CNReelStyle] = [
        CNReelStyle(name: "Sacred", gradientColors: [.amenPurple, Color(hex: "050508")], emoji: "✝️", fontName: "Georgia-BoldItalic"),
        CNReelStyle(name: "Glory", gradientColors: [.cnGold, .amenOrange], emoji: "🔥", fontName: "Georgia-BoldItalic"),
        CNReelStyle(name: "Peace", gradientColors: [.amenBlue, .amenCyan], emoji: "🕊️", fontName: "Georgia-BoldItalic")
    ]

    private let powerWords: Set<String> = ["faith", "grace", "love", "hope", "truth", "light", "spirit", "holy", "god", "christ", "prayer", "surrender", "strength", "mercy", "purpose", "calling", "redemption", "covenant", "peace", "joy", "abundant", "eternal", "glory"]

    func detectBestQuote(from text: String) {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 6 }

        guard !sentences.isEmpty else {
            detectedQuote = text.isEmpty ? "Your key insight will appear here as you take notes." : String(text.prefix(120))
            return
        }

        let scored = sentences.map { sentence -> (String, Int) in
            let words = sentence.lowercased().split(separator: " ").map(String.init)
            let powerScore = words.filter { powerWords.contains($0) }.count * 3
            let lengthScore = min(sentence.count, 100) / 10
            return (sentence, powerScore + lengthScore)
        }

        detectedQuote = scored.max(by: { $0.1 < $1.1 })?.0 ?? sentences[0]
    }

    func checkVisibility(textLength: Int) {
        withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
            isVisible = textLength >= 80
        }
    }
}

// MARK: - GrowthArcViewModel

@MainActor
final class GrowthArcViewModel: ObservableObject {
    @Published var weeklyData: [GrowthDataPoint] = []
    @Published var topThemes: [(theme: String, count: Int)] = []
    @Published var vocabularyScore: Int = 0
    @Published var animatedScore: Int = 0

    private var scoreTimer: Timer?

    func loadGrowthData() {
        let calendar = Calendar.current
        let themes = ["Grace", "Faith", "Prayer", "Identity", "Worship", "Hope", "Spirit", "Love", "Truth", "Purpose"]
        var data: [GrowthDataPoint] = []

        for week in 0..<52 {
            let date = calendar.date(byAdding: .weekOfYear, value: -(51 - week), to: Date()) ?? Date()
            // Growth curve: starts low, accelerates around week 20, plateaus near week 45
            let base: Double
            if week < 10 {
                base = Double(week) * 0.3
            } else if week < 30 {
                base = 3.0 + Double(week - 10) * 0.25
            } else if week < 45 {
                base = 8.0 + Double(week - 30) * 0.35
            } else {
                base = 13.0 + Double(week - 45) * 0.1
            }
            let noteCount = max(0, Int(base + Double.random(in: -1...2)))
            data.append(GrowthDataPoint(
                id: UUID(),
                weekNumber: week + 1,
                noteCount: noteCount,
                date: date,
                topTheme: themes[week % themes.count]
            ))
        }
        weeklyData = data

        // Tally themes
        var themeCounts: [String: Int] = [:]
        for point in data { themeCounts[point.topTheme, default: 0] += point.noteCount }
        topThemes = themeCounts.sorted { $0.value > $1.value }.map { (theme: $0.key, count: $0.value) }

        // Vocabulary score: unique words across mock notes (simulated)
        vocabularyScore = Int.random(in: 340...520)
    }

    func animateScoreCount() {
        animatedScore = 0
        scoreTimer?.invalidate()
        let target = vocabularyScore
        let step = max(1, target / 40)
        scoreTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.animatedScore < target {
                    self.animatedScore = min(self.animatedScore + step, target)
                } else {
                    self.scoreTimer?.invalidate()
                }
            }
        }
    }
}
