//
//  PersonalSpiritualGraphService.swift
//  AMENAPP
//
//  Personal Spiritual Graph (PSG) — a private, evolving model of the
//  user's spiritual life. Tracks recurring struggles, obedience patterns,
//  spiritual rhythms, emotional triggers, and growth velocity over time.
//
//  Privacy guarantees:
//    - All data is stored per-user in Firestore (users/{uid}/spiritualGraph/)
//    - Raw conversation content is NEVER stored — only classified patterns
//    - User can delete their graph at any time
//    - Graph data is never shared or aggregated without anonymization
//    - TTL: pattern entries expire after 90 days unless reinforced
//
//  Architecture:
//    PersonalSpiritualGraphService (singleton, @MainActor)
//    ├── SpiritualPatternEntry      (one detected pattern instance)
//    ├── SpiritualGraphSnapshot      (aggregated view of the user's graph)
//    ├── recordPattern()             (writes a new pattern observation)
//    ├── getSnapshot()               (builds current aggregated view)
//    └── detectRecurringThemes()     (cross-week pattern analysis)
//
//  Integration points:
//    - ScriptureIntelligenceEngine: snapshot feeds context tag detection
//    - PredictiveInterventionEngine: snapshot feeds anticipation logic
//    - BereanViewModel: system prompt enriched with graph context
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Struggle Category

/// Categories of recurring spiritual struggles tracked by the PSG.
enum SpiritualStruggleCategory: String, Codable, CaseIterable {
    case fear           = "fear"
    case anxiety        = "anxiety"
    case anger          = "anger"
    case lust           = "lust"
    case pride          = "pride"
    case isolation      = "isolation"
    case doubt          = "doubt"
    case unforgiveness  = "unforgiveness"
    case addiction      = "addiction"
    case discouragement = "discouragement"
    case jealousy       = "jealousy"
    case laziness       = "laziness"
    case greed          = "greed"
    case impatience     = "impatience"

    var displayName: String {
        rawValue.capitalized
    }

    /// Maps struggle to context tags for ScriptureIntelligenceEngine.
    var contextTags: [ContextTag] {
        switch self {
        case .fear:           return [.fear, .anxiety]
        case .anxiety:        return [.anxiety, .stress]
        case .anger:          return [.anger, .conflict, .impulsivity]
        case .lust:           return [.temptation, .impulsivity, .compulsiveUse]
        case .pride:          return [.pride, .conflict]
        case .isolation:      return [.isolation, .inactivity]
        case .doubt:          return [.fear, .spiritualStagnation]
        case .unforgiveness:  return [.conflict, .relationships]
        case .addiction:      return [.temptation, .compulsiveUse, .impulsivity]
        case .discouragement: return [.hopelessness, .spiritualStagnation]
        case .jealousy:       return [.conflict, .relationships, .pride]
        case .laziness:       return [.laziness, .inconsistency, .avoidance]
        case .greed:          return [.priorities, .worldlyInfluence]
        case .impatience:     return [.anger, .impulsivity]
        }
    }
}

// MARK: - Spiritual Rhythm

/// Tracked spiritual disciplines/rhythms.
enum SpiritualRhythm: String, Codable, CaseIterable {
    case prayer         = "prayer"
    case scripture      = "scripture"
    case churchAttendance = "church_attendance"
    case fellowship     = "fellowship"
    case fasting        = "fasting"
    case worship        = "worship"
    case serving        = "serving"
    case giving         = "giving"
    case journaling     = "journaling"

    var displayName: String {
        switch self {
        case .prayer: return "Prayer"
        case .scripture: return "Scripture Reading"
        case .churchAttendance: return "Church Attendance"
        case .fellowship: return "Fellowship"
        case .fasting: return "Fasting"
        case .worship: return "Worship"
        case .serving: return "Serving"
        case .giving: return "Giving"
        case .journaling: return "Journaling"
        }
    }
}

// MARK: - Pattern Entry

/// A single observed pattern event. Stored in Firestore with a 90-day TTL.
struct SpiritualPatternEntry: Codable, Identifiable {
    let id: String
    let userId: String
    let category: String                 // SpiritualStruggleCategory.rawValue or SpiritualRhythm.rawValue
    let patternType: PatternType
    let intensity: Double                // 0.0 – 1.0
    let source: PatternSource
    let detectedAt: Date
    let expiresAt: Date                  // 90 days from detection
    let weekNumber: Int                  // ISO week for aggregation

    enum PatternType: String, Codable {
        case struggle       // Negative pattern (fear, anger, etc.)
        case rhythm         // Positive discipline (prayer, scripture, etc.)
        case emotionalTrigger // Emotional state detected
        case obedienceAction  // User took a concrete obedience step
    }

    enum PatternSource: String, Codable {
        case bereanChat         // Detected from Berean conversation
        case churchNotes        // Detected from church notes content
        case prayerRequest      // Detected from prayer requests
        case appBehavior        // Detected from usage patterns (not content)
        case selfReport         // User explicitly reported
        case testimony          // Detected from testimony posts
    }
}

// MARK: - Growth Velocity

/// Measures how quickly the user is growing in a particular area.
struct GrowthVelocity: Codable {
    let category: String
    let velocityScore: Double    // -1.0 (declining) to 1.0 (rapid growth)
    let dataPoints: Int          // Number of observations
    let trend: VelocityTrend
    let measuredAt: Date

    enum VelocityTrend: String, Codable {
        case accelerating    // Getting better faster
        case steady          // Consistent
        case plateaued       // No change
        case declining       // Getting worse
        case insufficient    // Not enough data
    }
}

// MARK: - Graph Snapshot

/// Aggregated view of the user's spiritual graph at a point in time.
/// This is what gets fed into the intelligence layer.
struct SpiritualGraphSnapshot: Codable {
    let userId: String
    let generatedAt: Date

    // Top recurring struggles (sorted by frequency)
    let topStruggles: [StruggleSummary]

    // Active spiritual rhythms
    let activeRhythms: [RhythmSummary]

    // Growth velocities per area
    let growthVelocities: [GrowthVelocity]

    // Derived context tags for ScriptureIntelligenceEngine
    let derivedContextTags: [ContextTag]

    // Overall spiritual health score (0.0 – 1.0)
    let overallHealthScore: Double

    // Weeks of data available
    let weeksOfData: Int

    struct StruggleSummary: Codable {
        let category: SpiritualStruggleCategory
        let occurrences: Int          // In last 30 days
        let averageIntensity: Double  // 0.0 – 1.0
        let lastSeen: Date
        let isRecurring: Bool         // Appeared in 3+ separate weeks
    }

    struct RhythmSummary: Codable {
        let rhythm: SpiritualRhythm
        let engagements: Int          // In last 30 days
        let currentStreak: Int        // Consecutive days/weeks
        let isConsistent: Bool        // Engaged 3+ times in last 2 weeks
    }

    /// Builds a system prompt block for Berean from this snapshot.
    func toSystemPromptBlock() -> String {
        guard !topStruggles.isEmpty || !activeRhythms.isEmpty else {
            return ""
        }

        var lines: [String] = []
        lines.append("--- Personal Spiritual Context (Private) ---")

        if !topStruggles.isEmpty {
            let recurring = topStruggles.filter(\.isRecurring)
            if !recurring.isEmpty {
                let names = recurring.map(\.category.displayName).joined(separator: ", ")
                lines.append("Recurring areas of struggle: \(names)")
            }

            if let top = topStruggles.first {
                lines.append("Most frequent recent struggle: \(top.category.displayName) (\(top.occurrences) times in 30 days)")
            }
        }

        if !activeRhythms.isEmpty {
            let consistent = activeRhythms.filter(\.isConsistent)
            if !consistent.isEmpty {
                let names = consistent.map(\.rhythm.displayName).joined(separator: ", ")
                lines.append("Active spiritual disciplines: \(names)")
            }

            let gaps = SpiritualRhythm.allCases.filter { rhythm in
                !activeRhythms.contains(where: { $0.rhythm == rhythm && $0.isConsistent })
            }
            if !gaps.isEmpty {
                let gapNames = gaps.prefix(3).map(\.displayName).joined(separator: ", ")
                lines.append("Areas needing attention: \(gapNames)")
            }
        }

        if !growthVelocities.isEmpty {
            let growing = growthVelocities.filter { $0.trend == .accelerating }
            if !growing.isEmpty {
                let names = growing.map(\.category).joined(separator: ", ")
                lines.append("Areas of active growth: \(names)")
            }
        }

        lines.append("Approach with awareness of these patterns. Do not list them mechanically.")
        lines.append("Use them to ask better questions and offer more relevant Scripture.")
        lines.append("--- End Personal Context ---")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Personal Spiritual Graph Service

@MainActor
final class PersonalSpiritualGraphService: ObservableObject {

    static let shared = PersonalSpiritualGraphService()

    @Published private(set) var currentSnapshot: SpiritualGraphSnapshot?
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private let snapshotCacheKey = "psg_snapshot_v1"
    private let snapshotCacheTTL: TimeInterval = 3600 // 1 hour

    private init() {
        loadCachedSnapshot()
    }

    // MARK: - Record Pattern

    /// Records a new pattern observation to the user's spiritual graph.
    /// Call this when Berean detects a struggle, rhythm, or emotional trigger.
    func recordPattern(
        category: String,
        type: SpiritualPatternEntry.PatternType,
        intensity: Double,
        source: SpiritualPatternEntry.PatternSource
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let now = Date()
        let calendar = Calendar.current
        let weekNumber = calendar.component(.weekOfYear, from: now)
        let expiresAt = calendar.date(byAdding: .day, value: 90, to: now) ?? now

        let entry = SpiritualPatternEntry(
            id: UUID().uuidString,
            userId: uid,
            category: category,
            patternType: type,
            intensity: min(1.0, max(0.0, intensity)),
            source: source,
            detectedAt: now,
            expiresAt: expiresAt,
            weekNumber: weekNumber
        )

        do {
            let data = try Firestore.Encoder().encode(entry)
            try await db.collection("users").document(uid)
                .collection("spiritualGraph")
                .document(entry.id)
                .setData(data)
        } catch {
            dlog("[PSG] Failed to record pattern: \(error.localizedDescription)")
        }
    }

    /// Convenience: record a struggle from Berean chat analysis.
    func recordStruggle(
        _ struggle: SpiritualStruggleCategory,
        intensity: Double = 0.5,
        source: SpiritualPatternEntry.PatternSource = .bereanChat
    ) async {
        await recordPattern(
            category: struggle.rawValue,
            type: .struggle,
            intensity: intensity,
            source: source
        )
    }

    /// Convenience: record a spiritual rhythm engagement.
    func recordRhythm(
        _ rhythm: SpiritualRhythm,
        source: SpiritualPatternEntry.PatternSource = .appBehavior
    ) async {
        await recordPattern(
            category: rhythm.rawValue,
            type: .rhythm,
            intensity: 1.0,
            source: source
        )
    }

    /// Convenience: record an obedience action (user followed through).
    func recordObedienceAction(category: String, source: SpiritualPatternEntry.PatternSource = .bereanChat) async {
        await recordPattern(
            category: category,
            type: .obedienceAction,
            intensity: 1.0,
            source: source
        )
    }

    // MARK: - Get Snapshot

    /// Returns the current aggregated spiritual graph snapshot.
    /// Fetches fresh data if the cache is stale.
    func getSnapshot() async -> SpiritualGraphSnapshot? {
        if let cached = currentSnapshot,
           Date().timeIntervalSince(cached.generatedAt) < snapshotCacheTTL {
            return cached
        }
        return await refreshSnapshot()
    }

    /// Forces a fresh snapshot build from Firestore data.
    @discardableResult
    func refreshSnapshot() async -> SpiritualGraphSnapshot? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        isLoading = true
        defer { isLoading = false }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        do {
            let querySnapshot = try await db.collection("users").document(uid)
                .collection("spiritualGraph")
                .whereField("detectedAt", isGreaterThan: Timestamp(date: thirtyDaysAgo))
                .order(by: "detectedAt", descending: true)
                .limit(to: 500)
                .getDocuments()

            let entries: [SpiritualPatternEntry] = querySnapshot.documents.compactMap { doc in
                try? doc.data(as: SpiritualPatternEntry.self)
            }

            let snapshot = buildSnapshot(userId: uid, entries: entries)
            self.currentSnapshot = snapshot
            cacheSnapshot(snapshot)
            return snapshot

        } catch {
            dlog("[PSG] Failed to refresh snapshot: \(error.localizedDescription)")
            return currentSnapshot
        }
    }

    // MARK: - Detect Recurring Themes

    /// Analyzes patterns across weeks to detect recurring themes.
    /// Returns struggle categories that appeared in 3+ separate weeks.
    func detectRecurringThemes() async -> [SpiritualStruggleCategory] {
        guard let snapshot = await getSnapshot() else { return [] }
        return snapshot.topStruggles
            .filter(\.isRecurring)
            .map(\.category)
    }

    /// Returns context tags derived from the user's spiritual graph.
    /// Used by ScriptureIntelligenceEngine for verse matching.
    func derivedContextTags() async -> Set<ContextTag> {
        guard let snapshot = await getSnapshot() else { return [] }
        return Set(snapshot.derivedContextTags)
    }

    // MARK: - Delete Graph

    /// Deletes the user's entire spiritual graph. Called on account deletion or user request.
    func deleteGraph() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let docs = try await db.collection("users").document(uid)
                .collection("spiritualGraph")
                .limit(to: 500)
                .getDocuments()

            let batch = db.batch()
            for doc in docs.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()

            currentSnapshot = nil
            clearCachedSnapshot()
            dlog("[PSG] Graph deleted for user \(uid)")

        } catch {
            dlog("[PSG] Failed to delete graph: \(error.localizedDescription)")
        }
    }

    // MARK: - Snapshot Builder

    private func buildSnapshot(userId: String, entries: [SpiritualPatternEntry]) -> SpiritualGraphSnapshot {
        let now = Date()

        // Separate struggles vs rhythms
        let struggles = entries.filter { $0.patternType == .struggle }
        let rhythms = entries.filter { $0.patternType == .rhythm }
        let obedience = entries.filter { $0.patternType == .obedienceAction }

        // Build struggle summaries
        let struggleCounts = Dictionary(grouping: struggles, by: \.category)
        let struggleSummaries: [SpiritualGraphSnapshot.StruggleSummary] = struggleCounts.compactMap { (key, items) in
            guard let category = SpiritualStruggleCategory(rawValue: key) else { return nil }
            let weekNumbers = Set(items.map(\.weekNumber))
            let avgIntensity = items.map(\.intensity).reduce(0, +) / Double(max(1, items.count))
            let lastSeen = items.map(\.detectedAt).max() ?? now

            return SpiritualGraphSnapshot.StruggleSummary(
                category: category,
                occurrences: items.count,
                averageIntensity: avgIntensity,
                lastSeen: lastSeen,
                isRecurring: weekNumbers.count >= 3
            )
        }.sorted { $0.occurrences > $1.occurrences }

        // Build rhythm summaries
        let rhythmCounts = Dictionary(grouping: rhythms, by: \.category)
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let rhythmSummaries: [SpiritualGraphSnapshot.RhythmSummary] = rhythmCounts.compactMap { (key, items) in
            guard let rhythm = SpiritualRhythm(rawValue: key) else { return nil }
            let recentItems = items.filter { $0.detectedAt > twoWeeksAgo }
            let streak = computeStreak(dates: items.map(\.detectedAt))

            return SpiritualGraphSnapshot.RhythmSummary(
                rhythm: rhythm,
                engagements: items.count,
                currentStreak: streak,
                isConsistent: recentItems.count >= 3
            )
        }.sorted { $0.engagements > $1.engagements }

        // Build growth velocities
        let allCategories = Set(entries.map(\.category))
        let velocities: [GrowthVelocity] = allCategories.compactMap { category in
            computeVelocity(for: category, entries: entries)
        }

        // Derive context tags from top struggles
        var derivedTags: [ContextTag] = []
        for summary in struggleSummaries.prefix(5) {
            derivedTags.append(contentsOf: summary.category.contextTags)
        }
        // Add tags for missing rhythms
        let activeRhythmKeys = Set(rhythmSummaries.filter(\.isConsistent).map(\.rhythm))
        if !activeRhythmKeys.contains(.prayer) { derivedTags.append(.discipline) }
        if !activeRhythmKeys.contains(.scripture) { derivedTags.append(.spiritualStagnation) }
        if !activeRhythmKeys.contains(.churchAttendance) { derivedTags.append(.isolation) }
        if !activeRhythmKeys.contains(.fellowship) { derivedTags.append(.isolation) }

        // Overall health score
        let rhythmScore = Double(rhythmSummaries.filter(\.isConsistent).count) / Double(max(1, SpiritualRhythm.allCases.count))
        let struggleWeight = Double(struggleSummaries.filter(\.isRecurring).count) * 0.1
        let obedienceBonus = min(0.2, Double(obedience.count) * 0.02)
        let healthScore = min(1.0, max(0.0, (rhythmScore * 0.6) - struggleWeight + obedienceBonus + 0.3))

        // Weeks of data
        let weekNumbers = Set(entries.map(\.weekNumber))

        return SpiritualGraphSnapshot(
            userId: userId,
            generatedAt: now,
            topStruggles: Array(struggleSummaries.prefix(5)),
            activeRhythms: rhythmSummaries,
            growthVelocities: velocities,
            derivedContextTags: Array(Set(derivedTags)),
            overallHealthScore: healthScore,
            weeksOfData: weekNumbers.count
        )
    }

    // MARK: - Helpers

    private func computeStreak(dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sortedDays = Set(dates.map { calendar.startOfDay(for: $0) }).sorted(by: >)
        guard let today = sortedDays.first else { return 0 }

        var streak = 1
        var current = today
        for day in sortedDays.dropFirst() {
            let expected = calendar.date(byAdding: .day, value: -1, to: current)!
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                current = day
            } else {
                break
            }
        }
        return streak
    }

    private func computeVelocity(for category: String, entries: [SpiritualPatternEntry]) -> GrowthVelocity? {
        let relevant = entries.filter { $0.category == category }
        guard relevant.count >= 3 else {
            return GrowthVelocity(
                category: category,
                velocityScore: 0,
                dataPoints: relevant.count,
                trend: .insufficient,
                measuredAt: Date()
            )
        }

        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let recentCount = relevant.filter { $0.detectedAt > twoWeeksAgo }.count
        let olderCount = relevant.count - recentCount

        let halfTotal = Double(relevant.count) / 2.0
        let velocity: Double
        let trend: GrowthVelocity.VelocityTrend

        if relevant.first?.patternType == .struggle {
            // For struggles: fewer recent = better (positive velocity)
            if Double(recentCount) < halfTotal * 0.5 {
                velocity = 0.5; trend = .accelerating
            } else if Double(recentCount) > halfTotal * 1.5 {
                velocity = -0.5; trend = .declining
            } else {
                velocity = 0.0; trend = .steady
            }
        } else {
            // For rhythms: more recent = better
            if Double(recentCount) > Double(olderCount) * 1.3 {
                velocity = 0.5; trend = .accelerating
            } else if Double(recentCount) < Double(olderCount) * 0.7 {
                velocity = -0.5; trend = .declining
            } else {
                velocity = 0.0; trend = .steady
            }
        }

        return GrowthVelocity(
            category: category,
            velocityScore: velocity,
            dataPoints: relevant.count,
            trend: trend,
            measuredAt: now
        )
    }

    // MARK: - Cache

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: snapshotCacheKey),
              let snapshot = try? JSONDecoder().decode(SpiritualGraphSnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.generatedAt) < snapshotCacheTTL else {
            return
        }
        currentSnapshot = snapshot
    }

    private func cacheSnapshot(_ snapshot: SpiritualGraphSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotCacheKey)
    }

    private func clearCachedSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotCacheKey)
    }
}
