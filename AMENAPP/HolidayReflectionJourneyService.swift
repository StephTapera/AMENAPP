//
//  HolidayReflectionJourneyService.swift
//  AMENAPP
//
//  Holiday Reflection Journey Service — guided seasonal spiritual journeys.
//
//  Available journey types:
//    - Holy Week (7 days: Palm Sunday → Easter)
//    - Lent (40-day or 7-day condensed)
//    - Advent (28-day or 7-day condensed)
//    - Easter Celebration (7 days)
//    - Pentecost Prayer (7 days)
//    - Custom church-provided journeys
//
//  Each journey is:
//    - A series of daily entries with verse, reflection, prompt, and action
//    - Connected to Church Notes (entries become notes)
//    - Connected to FollowUpEngine (scheduled check-ins)
//    - Connected to PersonalSpiritualGraph (records engagement)
//    - Private by default (user can share entries selectively)
//
//  Storage: UserDefaults (local) + Firestore (sync).
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Journey Type

enum ReflectionJourneyType: String, Codable, CaseIterable {
    case holyWeek           = "holy_week"         // 7 days
    case lentFull           = "lent_full"          // 40 days
    case lentCondensed      = "lent_condensed"     // 7 days
    case adventFull         = "advent_full"        // 28 days
    case adventCondensed    = "advent_condensed"   // 7 days
    case easterCelebration  = "easter_celebration" // 7 days
    case pentecostPrayer    = "pentecost_prayer"   // 7 days
    case custom             = "custom"             // Church-provided

    var displayName: String {
        switch self {
        case .holyWeek:          return "Holy Week Journey"
        case .lentFull:          return "40 Days of Lent"
        case .lentCondensed:     return "Lent Reflection (7 Days)"
        case .adventFull:        return "Advent Journey"
        case .adventCondensed:   return "Advent Reflection (7 Days)"
        case .easterCelebration: return "Easter Celebration"
        case .pentecostPrayer:   return "Pentecost Prayer Week"
        case .custom:            return "Custom Journey"
        }
    }

    var dayCount: Int {
        switch self {
        case .holyWeek:          return 7
        case .lentFull:          return 40
        case .lentCondensed:     return 7
        case .adventFull:        return 28
        case .adventCondensed:   return 7
        case .easterCelebration: return 7
        case .pentecostPrayer:   return 7
        case .custom:            return 0  // Variable
        }
    }

    var relatedSeason: LiturgicalSeasonType {
        switch self {
        case .holyWeek:                        return .holyWeek
        case .lentFull, .lentCondensed:        return .lent
        case .adventFull, .adventCondensed:    return .advent
        case .easterCelebration:               return .easter
        case .pentecostPrayer:                 return .pentecost
        case .custom:                          return .ordinaryTimeLate
        }
    }

    var icon: String {
        switch self {
        case .holyWeek:          return "cross.fill"
        case .lentFull:          return "leaf.fill"
        case .lentCondensed:     return "leaf.fill"
        case .adventFull:        return "star.fill"
        case .adventCondensed:   return "star.fill"
        case .easterCelebration: return "sunrise.fill"
        case .pentecostPrayer:   return "flame.fill"
        case .custom:            return "book.fill"
        }
    }
}

// MARK: - Journey Day Entry

struct JourneyDayEntry: Identifiable, Codable {
    let id: String
    let dayNumber: Int
    let title: String
    let theme: String
    let scriptureReference: String
    let scriptureText: String?         // Optional: full verse text
    let reflectionPrompt: String
    let actionStep: String
    let prayerGuide: String
    let scheduledDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var userReflection: String?        // User's journaling response
    var linkedNoteId: String?          // If saved as a Church Note
}

// MARK: - Reflection Journey

struct ReflectionJourney: Identifiable, Codable {
    let id: String
    let userId: String
    let type: ReflectionJourneyType
    let title: String
    var entries: [JourneyDayEntry]
    let createdAt: Date
    let startDate: Date
    var isActive: Bool
    var completedEntries: Int

    var progress: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(entries.filter(\.isCompleted).count) / Double(entries.count)
    }

    var currentEntry: JourneyDayEntry? {
        entries.first { !$0.isCompleted && $0.scheduledDate <= Date() }
    }

    var isComplete: Bool {
        entries.allSatisfy(\.isCompleted)
    }

    var nextEntry: JourneyDayEntry? {
        entries.first { !$0.isCompleted }
    }
}

// MARK: - Service

@MainActor
final class HolidayReflectionJourneyService: ObservableObject {

    static let shared = HolidayReflectionJourneyService()

    @Published private(set) var activeJourneys: [ReflectionJourney] = []
    @Published private(set) var isGenerating = false

    private let db = Firestore.firestore()
    private let localStorageKey = "holiday_journeys_v1"

    private init() {
        loadLocalJourneys()
    }

    // MARK: - Start Journey

    /// Creates and starts a new reflection journey.
    func startJourney(type: ReflectionJourneyType, startDate: Date = Date()) async -> ReflectionJourney? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        // Don't allow duplicate active journeys of the same type
        if activeJourneys.contains(where: { $0.type == type && $0.isActive }) {
            dlog("[Journey] Already have an active \(type.displayName)")
            return nil
        }

        isGenerating = true
        defer { isGenerating = false }

        let entries = buildEntries(for: type, startDate: startDate)
        let journey = ReflectionJourney(
            id: UUID().uuidString,
            userId: uid,
            type: type,
            title: type.displayName,
            entries: entries,
            createdAt: Date(),
            startDate: startDate,
            isActive: true,
            completedEntries: 0
        )

        activeJourneys.append(journey)
        saveLocalJourneys()
        await persistToFirestore(journey)

        return journey
    }

    // MARK: - Complete Entry

    /// Marks a journey entry as completed with optional user reflection.
    func completeEntry(
        entryId: String,
        in journeyId: String,
        userReflection: String? = nil
    ) async {
        guard let journeyIndex = activeJourneys.firstIndex(where: { $0.id == journeyId }),
              let entryIndex = activeJourneys[journeyIndex].entries.firstIndex(where: { $0.id == entryId }) else {
            return
        }

        activeJourneys[journeyIndex].entries[entryIndex].isCompleted = true
        activeJourneys[journeyIndex].entries[entryIndex].completedAt = Date()
        activeJourneys[journeyIndex].entries[entryIndex].userReflection = userReflection
        activeJourneys[journeyIndex].completedEntries = activeJourneys[journeyIndex].entries.filter(\.isCompleted).count

        // Check if journey is complete
        if activeJourneys[journeyIndex].isComplete {
            activeJourneys[journeyIndex].isActive = false

            // Record to spiritual graph
            await PersonalSpiritualGraphService.shared.recordRhythm(
                .scripture, source: .bereanChat
            )
            await PersonalSpiritualGraphService.shared.recordObedienceAction(
                category: "Completed \(activeJourneys[journeyIndex].type.displayName)",
                source: .bereanChat
            )
        }

        saveLocalJourneys()
        await persistToFirestore(activeJourneys[journeyIndex])
    }

    // MARK: - Get Today's Entries

    /// Returns today's entries across all active journeys.
    func todaysEntries() -> [(journey: ReflectionJourney, entry: JourneyDayEntry)] {
        activeJourneys
            .filter(\.isActive)
            .compactMap { journey in
                guard let entry = journey.currentEntry else { return nil }
                return (journey, entry)
            }
    }

    /// Builds a system prompt block for Berean about active journeys.
    func systemPromptForActiveJourneys() -> String {
        let todays = todaysEntries()
        guard !todays.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("--- Active Reflection Journeys ---")

        for (journey, entry) in todays {
            lines.append("Journey: \(journey.title) (Day \(entry.dayNumber)/\(journey.entries.count))")
            lines.append("Today's theme: \(entry.theme)")
            lines.append("Scripture: \(entry.scriptureReference)")
            lines.append("Reflection: \(entry.reflectionPrompt)")
            lines.append("")
        }

        lines.append("If the user's conversation relates to their journey, weave it in naturally.")
        lines.append("--- End Journeys ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Delete Journey

    func deleteJourney(_ journeyId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        activeJourneys.removeAll { $0.id == journeyId }
        saveLocalJourneys()

        do {
            try await db.collection("users").document(uid)
                .collection("reflectionJourneys")
                .document(journeyId)
                .delete()
        } catch {
            dlog("[Journey] Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Entry Builders

    private func buildEntries(for type: ReflectionJourneyType, startDate: Date) -> [JourneyDayEntry] {
        let cal = Calendar.current

        switch type {
        case .holyWeek:
            return buildHolyWeekEntries(startDate: startDate)
        case .lentCondensed:
            return buildLentCondensedEntries(startDate: startDate)
        case .adventCondensed:
            return buildAdventCondensedEntries(startDate: startDate)
        case .easterCelebration:
            return buildEasterEntries(startDate: startDate)
        case .pentecostPrayer:
            return buildPentecostEntries(startDate: startDate)
        case .lentFull:
            // Generate 40 days using 7-day pattern repeated ~6 times
            return buildRepeatingEntries(
                baseDays: buildLentCondensedEntries(startDate: startDate),
                totalDays: 40,
                startDate: startDate,
                seasonTheme: "Lent"
            )
        case .adventFull:
            return buildRepeatingEntries(
                baseDays: buildAdventCondensedEntries(startDate: startDate),
                totalDays: 28,
                startDate: startDate,
                seasonTheme: "Advent"
            )
        case .custom:
            return [] // Custom journeys are built by churches
        }
    }

    private func buildHolyWeekEntries(startDate: Date) -> [JourneyDayEntry] {
        let cal = Calendar.current
        let days: [(title: String, theme: String, scripture: String, reflection: String, action: String, prayer: String)] = [
            ("Palm Sunday", "Triumphal Entry", "Matthew 21:1-11",
             "The crowds shouted Hosanna — but some would turn away. Where does your heart stand with Jesus today?",
             "Read the Palm Sunday passage slowly. Journal about where you stand with Jesus right now.",
             "Lord, I want to follow You not just when it's easy, but through whatever comes this week."),

            ("Holy Monday", "Cleansing the Temple", "Mark 11:15-18",
             "Jesus confronted what didn't belong in God's house. What doesn't belong in your heart?",
             "Identify one thing in your life that needs to be cleansed or removed.",
             "God, reveal what I've allowed to clutter the space that belongs to You."),

            ("Holy Tuesday", "Teaching & Parables", "Matthew 24:42-44",
             "Jesus taught with urgency. How would you live differently if you took His words more seriously?",
             "Choose one teaching of Jesus and write down how it applies to your life today.",
             "Jesus, help me not just hear Your words but live them."),

            ("Holy Wednesday", "Betrayal", "Matthew 26:14-16",
             "Judas chose silver over the Savior. Where have you traded something eternal for something temporary?",
             "Reflect on any area where you've compromised your faithfulness to God.",
             "Lord, keep me faithful. Show me where my loyalty has wavered."),

            ("Maundy Thursday", "The Last Supper", "John 13:1-17",
             "Jesus washed His disciples' feet. What does humble service look like in your life?",
             "Serve someone today in a tangible, humble way — without expecting anything in return.",
             "Jesus, give me the heart of a servant. Let me love the way You loved."),

            ("Good Friday", "The Cross", "John 19:28-30",
             "It is finished. What does the cross confront in you?",
             "Sit with the cross today. Write down what Jesus' sacrifice means for your specific situation.",
             "Father, I don't take the cross lightly. Thank You for the price that was paid."),

            ("Easter Sunday", "Resurrection", "Matthew 28:1-10",
             "He is risen. What in your life needs resurrection hope?",
             "Declare one area of your life where you're choosing hope over fear, life over death.",
             "Risen Lord, breathe new life into the places that feel dead. I believe You make all things new.")
        ]

        return days.enumerated().map { index, day in
            let date = Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
            return JourneyDayEntry(
                id: "hw_\(index + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: index + 1,
                title: day.title,
                theme: day.theme,
                scriptureReference: day.scripture,
                scriptureText: nil,
                reflectionPrompt: day.reflection,
                actionStep: day.action,
                prayerGuide: day.prayer,
                scheduledDate: date,
                isCompleted: false
            )
        }
    }

    private func buildLentCondensedEntries(startDate: Date) -> [JourneyDayEntry] {
        let days: [(title: String, theme: String, scripture: String, reflection: String, action: String, prayer: String)] = [
            ("Return", "Turning Back to God", "Joel 2:12-13",
             "God invites you to return — not with performance, but with your whole heart.",
             "Identify one area where you've drifted from God. Take the first step back.",
             "Lord, I'm turning back to You. Not perfectly, but honestly."),

            ("Examine", "Searching the Heart", "Psalm 139:23-24",
             "Ask God to search your heart. What is He revealing?",
             "Spend 10 minutes in silence, asking God to show you what needs to change.",
             "Search me, O God. Show me what I can't see on my own."),

            ("Surrender", "Letting Go", "Matthew 16:24-25",
             "What are you holding onto that God is asking you to release?",
             "Write down one thing you're surrendering to God today.",
             "I lay it down, Lord. Help me trust You with what I can't control."),

            ("Fast", "Making Room for God", "Isaiah 58:6-7",
             "Fasting creates space for God. What are you fasting from, and what are you making room for?",
             "Fast from one thing today — food, phone, or a habit — and use that time for God.",
             "God, as I empty myself, fill me with more of You."),

            ("Pray", "Drawing Near", "James 4:8",
             "Draw near to God and He will draw near to you. How close have you been?",
             "Set aside 15 minutes of focused, uninterrupted prayer today.",
             "I draw near to You, Father. Meet me here."),

            ("Serve", "Outward Focus", "Galatians 5:13",
             "Lent isn't only inward — it's also outward. Who needs your love today?",
             "Perform one act of service for someone in need.",
             "Lord, help me see others the way You see them."),

            ("Hope", "Looking Forward", "Romans 8:24-25",
             "Lent points toward Easter. What are you hoping for?",
             "Write a letter to yourself about the hope you're carrying into Easter.",
             "Thank You that this season ends in resurrection. I trust what's ahead.")
        ]

        return days.enumerated().map { index, day in
            let date = Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
            return JourneyDayEntry(
                id: "lent_\(index + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: index + 1, title: day.title, theme: day.theme,
                scriptureReference: day.scripture, scriptureText: nil,
                reflectionPrompt: day.reflection, actionStep: day.action,
                prayerGuide: day.prayer, scheduledDate: date, isCompleted: false
            )
        }
    }

    private func buildAdventCondensedEntries(startDate: Date) -> [JourneyDayEntry] {
        let days: [(title: String, theme: String, scripture: String, reflection: String, action: String, prayer: String)] = [
            ("Hope", "The Promise", "Isaiah 9:6",
             "A child is promised. Where do you most need hope right now?",
             "Write down one area where you're choosing hope over despair.",
             "Lord, You are the God of hope. Fill me with anticipation for what You're doing."),

            ("Peace", "The Calm", "Isaiah 26:3",
             "Perfect peace comes from a mind fixed on God. What is disturbing your peace?",
             "Identify one source of anxiety and surrender it to God in prayer.",
             "Prince of Peace, guard my heart and mind today."),

            ("Joy", "The Song", "Luke 1:46-47",
             "Mary sang in the midst of uncertainty. Can you find joy before the answer comes?",
             "Choose joy today — not because everything is perfect, but because God is faithful.",
             "Lord, let my soul magnify You even in the waiting."),

            ("Love", "The Gift", "John 3:16",
             "God gave His only Son. What does that kind of love require of you?",
             "Show love to someone today in a way that costs you something.",
             "God, help me love the way You love — sacrificially and freely."),

            ("Prepare", "Making Room", "Luke 1:26-38",
             "Mary said yes to the impossible. What is God asking you to make room for?",
             "Clear one distraction from your life to make space for God this season.",
             "Here I am, Lord. Let it be according to Your word."),

            ("Wait", "Holy Patience", "Psalm 27:14",
             "Waiting is not passive — it's active trust. What are you waiting on God for?",
             "Practice waiting today. Don't rush to fill silence. Let God speak.",
             "I will wait for You, Lord. Strengthen my heart."),

            ("Emmanuel", "God With Us", "Matthew 1:23",
             "God chose to come near. How does that change everything?",
             "Reflect on what it means that God is with you — right now, in this moment.",
             "Thank You for not staying distant. You are here. Emmanuel.")
        ]

        return days.enumerated().map { index, day in
            let date = Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
            return JourneyDayEntry(
                id: "advent_\(index + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: index + 1, title: day.title, theme: day.theme,
                scriptureReference: day.scripture, scriptureText: nil,
                reflectionPrompt: day.reflection, actionStep: day.action,
                prayerGuide: day.prayer, scheduledDate: date, isCompleted: false
            )
        }
    }

    private func buildEasterEntries(startDate: Date) -> [JourneyDayEntry] {
        let days: [(String, String, String, String, String, String)] = [
            ("He Is Risen", "Resurrection", "Matthew 28:5-6", "The tomb is empty. What dead thing in your life needs to come alive?", "Declare one area where you're choosing new life.", "Risen Lord, bring resurrection to the dead places in my life."),
            ("New Creation", "Identity", "2 Corinthians 5:17", "In Christ, the old is gone. What old identity are you still carrying?", "Write down who you are in Christ — not who you were.", "I am a new creation. Help me live like it."),
            ("Witness", "Sharing", "Acts 1:8", "The disciples were witnesses. Who needs to hear about what God has done in your life?", "Share your testimony with one person today.", "Give me boldness to be Your witness."),
            ("Community", "Gathering", "Acts 2:42-47", "The early church gathered, shared, and grew. How are you connected?", "Reach out to a believer and encourage them.", "Lord, help me not walk alone."),
            ("Mission", "Purpose", "Matthew 28:19-20", "Go and make disciples. What is your mission?", "Identify one way you can serve God's mission this week.", "Send me, Lord. I'm available."),
            ("Gratitude", "Thanksgiving", "Psalm 118:24", "This is the day the Lord has made. What are you grateful for?", "Write 10 things you're thankful for because of Easter.", "Thank You, Lord, for everything."),
            ("Forward", "Living Hope", "1 Peter 1:3", "Easter isn't just a day — it's a living hope. How will you carry it forward?", "Set one faith goal for the season ahead.", "Let Easter change how I live every day.")
        ]

        return days.enumerated().map { index, day in
            let date = Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
            return JourneyDayEntry(
                id: "easter_\(index + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: index + 1, title: day.0, theme: day.1,
                scriptureReference: day.2, scriptureText: nil,
                reflectionPrompt: day.3, actionStep: day.4,
                prayerGuide: day.5, scheduledDate: date, isCompleted: false
            )
        }
    }

    private func buildPentecostEntries(startDate: Date) -> [JourneyDayEntry] {
        let days: [(String, String, String, String, String, String)] = [
            ("The Promise", "Waiting for Power", "Acts 1:4-5", "Jesus told them to wait. Are you willing to wait for God's power instead of rushing ahead?", "Pause your agenda today and ask God what He wants.", "Holy Spirit, I wait for You."),
            ("The Fire", "Holy Spirit Descends", "Acts 2:1-4", "The Spirit came like fire. Where do you need God's fire in your life?", "Pray specifically for the Holy Spirit to fill one area of your life.", "Come, Holy Spirit. Set my heart on fire."),
            ("Boldness", "Fearless Witness", "Acts 4:31", "The early church was filled with boldness. Where are you holding back?", "Do one thing today that requires spiritual courage.", "Give me boldness I don't have on my own."),
            ("Prayer", "Spirit-Led Prayer", "Romans 8:26-27", "The Spirit intercedes when we don't know what to pray. Can you let Him lead?", "Spend 10 minutes in silent, Spirit-led prayer.", "Pray through me, Holy Spirit."),
            ("Gifts", "Spiritual Gifts", "1 Corinthians 12:4-7", "The Spirit gives gifts for the common good. How are you using yours?", "Identify one spiritual gift and use it today.", "Help me steward what You've given me."),
            ("Unity", "One Body", "Ephesians 4:3-4", "The Spirit creates unity. Where is division or isolation in your life?", "Reach out to someone you've been disconnected from.", "Make us one, Lord, by Your Spirit."),
            ("Mission", "Sent Out", "Acts 1:8", "You will be my witnesses. The Spirit sends, not just fills. Where is He sending you?", "Take one step toward the mission God has placed on your heart.", "I'm available, Lord. Send me.")
        ]

        return days.enumerated().map { index, day in
            let date = Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
            return JourneyDayEntry(
                id: "pent_\(index + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: index + 1, title: day.0, theme: day.1,
                scriptureReference: day.2, scriptureText: nil,
                reflectionPrompt: day.3, actionStep: day.4,
                prayerGuide: day.5, scheduledDate: date, isCompleted: false
            )
        }
    }

    private func buildRepeatingEntries(baseDays: [JourneyDayEntry], totalDays: Int, startDate: Date, seasonTheme: String) -> [JourneyDayEntry] {
        var entries: [JourneyDayEntry] = []
        let cal = Calendar.current

        for i in 0..<totalDays {
            let baseEntry = baseDays[i % baseDays.count]
            let week = (i / baseDays.count) + 1
            let date = cal.date(byAdding: .day, value: i, to: startDate) ?? startDate

            entries.append(JourneyDayEntry(
                id: "\(seasonTheme.lowercased())_\(i + 1)_\(UUID().uuidString.prefix(8))",
                dayNumber: i + 1,
                title: "Week \(week): \(baseEntry.title)",
                theme: baseEntry.theme,
                scriptureReference: baseEntry.scriptureReference,
                scriptureText: nil,
                reflectionPrompt: baseEntry.reflectionPrompt,
                actionStep: baseEntry.actionStep,
                prayerGuide: baseEntry.prayerGuide,
                scheduledDate: date,
                isCompleted: false
            ))
        }

        return entries
    }

    // MARK: - Persistence

    private func loadLocalJourneys() {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let journeys = try? JSONDecoder().decode([ReflectionJourney].self, from: data) else {
            return
        }
        activeJourneys = journeys
    }

    private func saveLocalJourneys() {
        guard let data = try? JSONEncoder().encode(activeJourneys) else { return }
        UserDefaults.standard.set(data, forKey: localStorageKey)
    }

    private func persistToFirestore(_ journey: ReflectionJourney) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let data = try Firestore.Encoder().encode(journey)
            try await db.collection("users").document(uid)
                .collection("reflectionJourneys")
                .document(journey.id)
                .setData(data, merge: true)
        } catch {
            dlog("[Journey] Firestore persist failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        activeJourneys.removeAll()
        UserDefaults.standard.removeObject(forKey: localStorageKey)
    }
}
