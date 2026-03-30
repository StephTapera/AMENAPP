// SpiritualIdentitySystem.swift
// AMENAPP
//
// Identity + Reputation System (Non-Social Metrics)
//
// Not likes. Not followers. Real growth metrics:
//   - Consistency (showing up daily)
//   - Reflection depth (quality of engagement)
//   - Obedience actions (following through)
//   - Encouragement given (building others up)
//   - Scripture engagement (studying, not just reading)
//   - Community contribution (prayer, support)
//
// Display:
//   - Private growth stats (default)
//   - Optional sharing
//   - Progress over time
//
// Also includes Personal Doctrine Builder:
//   - Tracks what user believes
//   - Shows gaps and growth
//   - Belief map over time
//
// Entry points:
//   SpiritualIdentitySystem.shared.recordActivity(_ activity:)
//   SpiritualIdentitySystem.shared.getGrowthProfile() -> SpiritualGrowthProfile
//   SpiritualIdentitySystem.shared.getBeliefMap() async -> BeliefMap

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

/// The user's spiritual growth profile (private by default)
struct SpiritualGrowthProfile: Codable {
    let userId: String
    let lastUpdated: Date

    // Core metrics (0-100)
    var consistencyScore: Double
    var reflectionDepthScore: Double
    var obedienceScore: Double
    var encouragementScore: Double
    var scriptureEngagementScore: Double
    var communityContributionScore: Double

    // Composite
    var overallGrowthScore: Double {
        (consistencyScore + reflectionDepthScore + obedienceScore +
         encouragementScore + scriptureEngagementScore + communityContributionScore) / 6.0
    }

    // Activity counts
    var totalReflections: Int
    var totalActionsCompleted: Int
    var totalPrayersPosted: Int
    var totalEncouragements: Int
    var totalWordStudies: Int
    var totalSermonNotes: Int

    // Streaks
    var currentDailyStreak: Int
    var longestDailyStreak: Int
    var lastActiveDate: Date?

    // Sharing preference
    var isPublic: Bool
}

/// Activity that contributes to spiritual identity
struct SpiritualActivity {
    let type: ActivityType
    let value: Double               // Weight of the activity
    let timestamp: Date
    let metadata: [String: String]

    enum ActivityType: String {
        case dailyReading = "daily_reading"
        case bereanConversation = "berean_conversation"
        case wordStudy = "word_study"
        case sermonNote = "sermon_note"
        case prayerPosted = "prayer_posted"
        case encouragementGiven = "encouragement"
        case actionCompleted = "action_completed"
        case reflectionWritten = "reflection"
        case communitySupport = "community_support"
        case churchAttendance = "church_attendance"
        case scriptureShared = "scripture_shared"
        case growthLoopResponse = "growth_loop"
    }
}

/// Personal belief map
struct BeliefMap: Codable {
    let userId: String
    let lastUpdated: Date
    let beliefs: [BeliefEntry]
    let gaps: [String]              // Areas not yet explored
    let growthAreas: [String]       // Areas showing development
}

struct BeliefEntry: Codable, Identifiable {
    let id: String
    let topic: String               // "Salvation", "Grace", "Prayer", etc.
    let currentUnderstanding: String
    let confidence: Double          // How confident they are (0-1)
    let scriptures: [String]        // Verses they've studied on this
    let lastExplored: Date
    let explorationDepth: Int       // How many times they've engaged
}

// MARK: - SpiritualIdentitySystem

@MainActor
final class SpiritualIdentitySystem: ObservableObject {

    static let shared = SpiritualIdentitySystem()

    @Published var profile: SpiritualGrowthProfile
    @Published var beliefMap: BeliefMap?
    @Published var isLoading = false

    // Today's activities
    @Published var todayActivities: [SpiritualActivity] = []

    private let db = Firestore.firestore()
    private let aiService = ClaudeService.shared

    // Score weights
    private let scoreWeights: [SpiritualActivity.ActivityType: (metric: String, points: Double)] = [
        .dailyReading: ("consistency", 5),
        .bereanConversation: ("scriptureEngagement", 3),
        .wordStudy: ("scriptureEngagement", 8),
        .sermonNote: ("reflectionDepth", 10),
        .prayerPosted: ("communityContribution", 5),
        .encouragementGiven: ("encouragement", 7),
        .actionCompleted: ("obedience", 10),
        .reflectionWritten: ("reflectionDepth", 8),
        .communitySupport: ("communityContribution", 6),
        .churchAttendance: ("consistency", 10),
        .scriptureShared: ("encouragement", 4),
        .growthLoopResponse: ("obedience", 8),
    ]

    private init() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        profile = SpiritualGrowthProfile(
            userId: uid,
            lastUpdated: Date(),
            consistencyScore: 0,
            reflectionDepthScore: 0,
            obedienceScore: 0,
            encouragementScore: 0,
            scriptureEngagementScore: 0,
            communityContributionScore: 0,
            totalReflections: 0,
            totalActionsCompleted: 0,
            totalPrayersPosted: 0,
            totalEncouragements: 0,
            totalWordStudies: 0,
            totalSermonNotes: 0,
            currentDailyStreak: 0,
            longestDailyStreak: 0,
            lastActiveDate: nil,
            isPublic: false
        )
        loadProfile()
    }

    // MARK: - Activity Recording

    /// Record a spiritual activity
    func recordActivity(_ activity: SpiritualActivity) {
        todayActivities.append(activity)

        // Update relevant score
        if let weight = scoreWeights[activity.type] {
            switch weight.metric {
            case "consistency":
                profile.consistencyScore = min(100, profile.consistencyScore + weight.points * activity.value)
            case "reflectionDepth":
                profile.reflectionDepthScore = min(100, profile.reflectionDepthScore + weight.points * activity.value)
            case "obedience":
                profile.obedienceScore = min(100, profile.obedienceScore + weight.points * activity.value)
            case "encouragement":
                profile.encouragementScore = min(100, profile.encouragementScore + weight.points * activity.value)
            case "scriptureEngagement":
                profile.scriptureEngagementScore = min(100, profile.scriptureEngagementScore + weight.points * activity.value)
            case "communityContribution":
                profile.communityContributionScore = min(100, profile.communityContributionScore + weight.points * activity.value)
            default: break
            }
        }

        // Update counts
        switch activity.type {
        case .reflectionWritten, .growthLoopResponse: profile.totalReflections += 1
        case .actionCompleted: profile.totalActionsCompleted += 1
        case .prayerPosted: profile.totalPrayersPosted += 1
        case .encouragementGiven: profile.totalEncouragements += 1
        case .wordStudy: profile.totalWordStudies += 1
        case .sermonNote: profile.totalSermonNotes += 1
        default: break
        }

        // Update streak
        updateStreak()
        profile.lastUpdated = Date()

        // Persist
        saveProfile()
    }

    // MARK: - Belief Map

    /// Generate/update the personal belief map
    func getBeliefMap() async -> BeliefMap? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        isLoading = true
        defer { isLoading = false }

        // Get context from knowledge graph
        let memories = PersonalKnowledgeGraph.shared.memories
        let learningMemories = memories.filter { $0.category == .learning }
        let learningContext = learningMemories.prefix(20).map { $0.content }.joined(separator: "\n")

        let prompt = """
        Based on this user's learning history, generate a belief map. Return as JSON:
        {
            "userId": "\(uid)",
            "lastUpdated": "\(ISO8601DateFormatter().string(from: Date()))",
            "beliefs": [
                {
                    "id": "b1",
                    "topic": "Salvation",
                    "currentUnderstanding": "What the user seems to understand about this topic",
                    "confidence": 0.7,
                    "scriptures": ["Key verses they've engaged with"],
                    "lastExplored": "\(ISO8601DateFormatter().string(from: Date()))",
                    "explorationDepth": 3
                }
            ],
            "gaps": ["Theological topics they haven't explored yet"],
            "growthAreas": ["Topics where they're actively growing"]
        }

        User's learning context:
        \(learningContext.isEmpty ? "No learning history yet — generate a starter belief map with common Christian doctrine topics" : learningContext)

        Include 8-12 belief entries covering core Christian doctrine.
        Return ONLY valid JSON.
        """

        do {
            let response = try await aiService.sendMessage(prompt)
            let data = Data(cleanJSON(response).utf8)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let map = try decoder.decode(BeliefMap.self, from: data)
            beliefMap = map
            return map
        } catch {
            dlog("❌ [SpiritualIdentity] Belief map failed: \(error)")
            return nil
        }
    }

    // MARK: - Growth Profile

    func getGrowthProfile() -> SpiritualGrowthProfile {
        return profile
    }

    // MARK: - Private

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastActive = profile.lastActiveDate {
            let lastDay = calendar.startOfDay(for: lastActive)

            if lastDay == today {
                // Already active today, no change
            } else if calendar.date(byAdding: .day, value: -1, to: today) == lastDay {
                // Consecutive day
                profile.currentDailyStreak += 1
                profile.longestDailyStreak = max(profile.longestDailyStreak, profile.currentDailyStreak)
            } else {
                // Streak broken
                profile.currentDailyStreak = 1
            }
        } else {
            profile.currentDailyStreak = 1
        }

        profile.lastActiveDate = Date()
    }

    private func loadProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        db.collection("users").document(uid)
            .collection("spiritualProfile").document("current")
            .getDocument { [weak self] snapshot, _ in
                guard let data = snapshot?.data(),
                      let profile = try? Firestore.Decoder().decode(SpiritualGrowthProfile.self, from: data) else { return }
                Task { @MainActor [weak self] in
                    self?.profile = profile
                }
            }
    }

    private func saveProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try? db.collection("users").document(uid)
            .collection("spiritualProfile").document("current")
            .setData(from: profile, merge: true)
    }

    private func cleanJSON(_ response: String) -> String {
        var s = response
        if let start = s.range(of: "{"), let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.upperBound])
        }
        return s
    }
}

// MARK: - Growth Profile View

struct SpiritualGrowthProfileView: View {
    @StateObject private var system = SpiritualIdentitySystem.shared
    @State private var showBeliefMap = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Overall score
                    VStack(spacing: 8) {
                        Text("\(Int(system.profile.overallGrowthScore))")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.blue.gradient)

                        Text("Growth Score")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(system.profile.currentDailyStreak) day streak")
                                .font(.caption.bold())
                        }
                    }
                    .padding()

                    // Score breakdown
                    VStack(spacing: 12) {
                        scoreRow("Consistency", score: system.profile.consistencyScore, icon: "calendar", color: .blue)
                        scoreRow("Reflection Depth", score: system.profile.reflectionDepthScore, icon: "brain.head.profile.fill", color: .purple)
                        scoreRow("Obedience Actions", score: system.profile.obedienceScore, icon: "checkmark.circle.fill", color: .green)
                        scoreRow("Encouragement", score: system.profile.encouragementScore, icon: "heart.fill", color: .pink)
                        scoreRow("Scripture Engagement", score: system.profile.scriptureEngagementScore, icon: "book.fill", color: .indigo)
                        scoreRow("Community", score: system.profile.communityContributionScore, icon: "person.2.fill", color: .orange)
                    }
                    .padding()

                    Divider()

                    // Activity counts
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        statBox("Reflections", count: system.profile.totalReflections, icon: "pencil.line")
                        statBox("Actions Done", count: system.profile.totalActionsCompleted, icon: "checkmark.circle")
                        statBox("Prayers", count: system.profile.totalPrayersPosted, icon: "hands.sparkles")
                        statBox("Encouragements", count: system.profile.totalEncouragements, icon: "heart")
                        statBox("Word Studies", count: system.profile.totalWordStudies, icon: "textformat.abc")
                        statBox("Sermon Notes", count: system.profile.totalSermonNotes, icon: "doc.text")
                    }
                    .padding()

                    // Belief Map button
                    Button {
                        showBeliefMap = true
                    } label: {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("View Belief Map")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.primary)
                    .padding(.horizontal)

                    // Privacy toggle
                    Toggle("Share Growth Profile", isOn: Binding(
                        get: { system.profile.isPublic },
                        set: { system.profile.isPublic = $0 }
                    ))
                    .padding(.horizontal)
                }
            }
            .navigationTitle("My Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showBeliefMap) {
                BeliefMapView()
            }
        }
    }

    private func scoreRow(_ label: String, score: Double, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(Int(score))")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            ProgressView(value: score, total: 100)
                .frame(width: 80)
                .tint(color)
        }
    }

    private func statBox(_ label: String, count: Int, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Belief Map View

struct BeliefMapView: View {
    @StateObject private var system = SpiritualIdentitySystem.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if system.isLoading {
                    ProgressView("Building your belief map...")
                } else if let map = system.beliefMap {
                    List {
                        Section("Your Beliefs") {
                            ForEach(map.beliefs) { belief in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(belief.topic)
                                            .font(.subheadline.bold())
                                        Spacer()
                                        ProgressView(value: belief.confidence)
                                            .frame(width: 50)
                                    }
                                    Text(belief.currentUnderstanding)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !belief.scriptures.isEmpty {
                                        Text(belief.scriptures.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if !map.gaps.isEmpty {
                            Section("Areas to Explore") {
                                ForEach(map.gaps, id: \.self) { gap in
                                    Label(gap, systemImage: "questionmark.circle")
                                        .font(.subheadline)
                                }
                            }
                        }

                        if !map.growthAreas.isEmpty {
                            Section("Active Growth") {
                                ForEach(map.growthAreas, id: \.self) { area in
                                    Label(area, systemImage: "leaf.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No Belief Map Yet", systemImage: "map",
                        description: Text("Start studying with Berean to build your belief map."))
                }
            }
            .navigationTitle("Belief Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if system.beliefMap == nil {
                    await system.getBeliefMap()
                }
            }
        }
    }
}
