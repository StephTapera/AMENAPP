
//
//  SpiritualHealthView.swift
//  AMENAPP
//
//  Spiritual health check-ins, growth tracking, reflection journal,
//  weekly faith score visualization, and Berean AI reflection prompts.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Data Models

struct SpiritualCheckIn: Identifiable, Codable {
    var id: String = UUID().uuidString
    var userID: String
    var weekOf: Date          // Monday of the check-in week
    var scoreScripture: Int   // 1–5
    var scorePrayer: Int      // 1–5
    var scoreCommunity: Int   // 1–5
    var scoreMindset: Int     // 1–5
    var scoreGratitude: Int   // 1–5
    var reflectionNote: String
    var prayerRequest: String
    var mood: SpiritualMood
    var createdAt: Date
    var overallScore: Double {
        Double(scoreScripture + scorePrayer + scoreCommunity + scoreMindset + scoreGratitude) / 5.0
    }
}

enum SpiritualMood: String, Codable, CaseIterable {
    case flourishing = "Flourishing"
    case growing     = "Growing"
    case steady      = "Steady"
    case struggling  = "Struggling"
    case seekingHelp = "Seeking Help"

    var emoji: String {
        switch self {
        case .flourishing: return "🌟"
        case .growing:     return "🌱"
        case .steady:      return "🙏"
        case .struggling:  return "💙"
        case .seekingHelp: return "🤝"
        }
    }

    var color: Color {
        switch self {
        case .flourishing: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .growing:     return Color(red: 0.20, green: 0.65, blue: 0.38)
        case .steady:      return Color(red: 0.28, green: 0.52, blue: 0.90)
        case .struggling:  return Color(red: 0.55, green: 0.35, blue: 0.85)
        case .seekingHelp: return Color(red: 0.85, green: 0.35, blue: 0.30)
        }
    }
}

struct ReflectionEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var userID: String
    var title: String
    var body: String
    var scripture: String
    var tags: [String]
    var createdAt: Date
}

struct GrowthMilestone: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var icon: String
    var color: Color
    var target: Int        // e.g., 4 check-ins
    var category: String
}

// MARK: - Store

@MainActor
final class SpiritualHealthStore: ObservableObject {
    static let shared = SpiritualHealthStore()

    @Published var checkIns: [SpiritualCheckIn] = []
    @Published var reflections: [ReflectionEntry] = []
    @Published var currentStreak: Int = 0
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var checkInListener: ListenerRegistration?
    private var reflectionListener: ListenerRegistration?

    private init() {}

    func loadAll() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        // Check-ins listener
        checkInListener = db.collection("spiritualCheckIns")
            .whereField("userID", isEqualTo: uid)
            .order(by: "weekOf", descending: true)
            .limit(to: 52)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                self.isLoading = false
                let loaded = snap.documents.compactMap {
                    try? $0.data(as: SpiritualCheckIn.self)
                }
                if loaded.isEmpty {
                    self.checkIns = SpiritualHealthStore.demoCheckIns
                } else {
                    self.checkIns = loaded
                }
                self.recalculateStreak()
            }

        // Reflections listener
        reflectionListener = db.collection("spiritualReflections")
            .whereField("userID", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                let loaded = snap.documents.compactMap {
                    try? $0.data(as: ReflectionEntry.self)
                }
                self.reflections = loaded.isEmpty ? SpiritualHealthStore.demoReflections : loaded
            }
    }

    func saveCheckIn(_ checkIn: SpiritualCheckIn) async throws {
        try db.collection("spiritualCheckIns")
            .document(checkIn.id)
            .setData(from: checkIn)
        recalculateStreak()
    }

    func saveReflection(_ entry: ReflectionEntry) async throws {
        try db.collection("spiritualReflections")
            .document(entry.id)
            .setData(from: entry)
    }

    func deleteReflection(_ id: String) async throws {
        try await db.collection("spiritualReflections").document(id).delete()
    }

    private func recalculateStreak() {
        // Count consecutive weeks with check-ins
        let calendar = Calendar.current
        let sorted = checkIns.sorted { $0.weekOf > $1.weekOf }
        var streak = 0
        var expectedWeek = calendar.startOfWeek(for: Date())
        for checkIn in sorted {
            let weekStart = calendar.startOfWeek(for: checkIn.weekOf)
            if calendar.isDate(weekStart, equalTo: expectedWeek, toGranularity: .weekOfYear) {
                streak += 1
                expectedWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: expectedWeek) ?? expectedWeek
            } else {
                break
            }
        }
        currentStreak = streak
    }

    func stopListening() {
        checkInListener?.remove()
        reflectionListener?.remove()
    }

    // MARK: - Demo Data

    static let demoCheckIns: [SpiritualCheckIn] = {
        let uid = Auth.auth().currentUser?.uid ?? "demo"
        let calendar = Calendar.current
        var result: [SpiritualCheckIn] = []
        let scores: [(Int,Int,Int,Int,Int,SpiritualMood)] = [
            (5,4,4,5,5,.flourishing),
            (4,5,3,4,4,.growing),
            (3,3,4,3,4,.steady),
            (4,4,5,4,5,.growing),
            (5,5,4,5,5,.flourishing),
            (2,3,2,3,3,.struggling),
            (4,4,3,4,4,.growing),
            (5,5,5,5,5,.flourishing),
        ]
        for (i, s) in scores.enumerated() {
            let weekOf = calendar.date(byAdding: .weekOfYear, value: -i, to: calendar.startOfWeek(for: Date())) ?? Date()
            result.append(SpiritualCheckIn(
                userID: uid,
                weekOf: weekOf,
                scoreScripture: s.0,
                scorePrayer: s.1,
                scoreCommunity: s.2,
                scoreMindset: s.3,
                scoreGratitude: s.4,
                reflectionNote: ["This week I felt God's presence strongly in my daily devotions.", "Struggled with consistency but found renewal through worship.", "A steady, grounding week — leaning into scripture.", "Breakthrough week — prayer felt alive and real.", "Blessed week filled with gratitude and connection.", "Difficult week spiritually. Felt distant but seeking.", "Better week. Community helped pull me back.", "Best week in a while — fully surrendered."][i],
                prayerRequest: ["Guidance on a major decision", "Healing for a family member", "Strength during a difficult season", "Wisdom in relationships", "", "Prayer for restoration and hope", "Consistency in daily prayer", ""][i],
                mood: s.5,
                createdAt: weekOf
            ))
        }
        return result
    }()

    static let demoReflections: [ReflectionEntry] = [
        ReflectionEntry(
            userID: Auth.auth().currentUser?.uid ?? "demo",
            title: "Finding Peace in Uncertainty",
            body: "I've been wrestling with a major life decision and feeling overwhelmed. Today in Philippians 4 I was reminded to not be anxious about anything, but to bring everything to God in prayer. His peace really does guard my heart when I actually do it.",
            scripture: "Philippians 4:6-7",
            tags: ["peace", "prayer", "anxiety"],
            createdAt: Date().addingTimeInterval(-86400 * 3)
        ),
        ReflectionEntry(
            userID: Auth.auth().currentUser?.uid ?? "demo",
            title: "The Parable of the Prodigal Son",
            body: "Reading Luke 15 again this morning. The father running toward his returning son before he even spoke — that image undoes me every time. How quickly I forget that this is exactly how God sees me. Not with disappointment but with joy.",
            scripture: "Luke 15:20",
            tags: ["grace", "forgiveness", "identity"],
            createdAt: Date().addingTimeInterval(-86400 * 10)
        ),
        ReflectionEntry(
            userID: Auth.auth().currentUser?.uid ?? "demo",
            title: "What Does It Mean to Rest?",
            body: "Sabbath is something I always push against. But lately I've been practicing an hour of digital silence on Sundays and something is shifting. Rest isn't laziness — it's trust that God holds everything I step away from.",
            scripture: "Exodus 20:8-10",
            tags: ["sabbath", "rest", "trust"],
            createdAt: Date().addingTimeInterval(-86400 * 21)
        ),
    ]

    static let milestones: [GrowthMilestone] = [
        GrowthMilestone(title: "First Check-In", description: "Completed your first weekly check-in", icon: "star.fill", color: .yellow, target: 1, category: "Consistency"),
        GrowthMilestone(title: "4-Week Streak", description: "4 consecutive weekly check-ins", icon: "flame.fill", color: .orange, target: 4, category: "Consistency"),
        GrowthMilestone(title: "3-Month Journey", description: "12 consecutive weekly check-ins", icon: "crown.fill", color: Color(red: 0.85, green: 0.65, blue: 0.10), target: 12, category: "Consistency"),
        GrowthMilestone(title: "Faithful Writer", description: "Written 5 reflection entries", icon: "pencil.and.scribble", color: Color(red: 0.28, green: 0.52, blue: 0.90), target: 5, category: "Reflection"),
        GrowthMilestone(title: "Scripture Reader", description: "Scored 5/5 on Scripture 3 weeks", icon: "book.fill", color: Color(red: 0.20, green: 0.65, blue: 0.38), target: 3, category: "Scripture"),
        GrowthMilestone(title: "Prayer Warrior", description: "Scored 5/5 on Prayer 5 times", icon: "hands.sparkles.fill", color: .purple, target: 5, category: "Prayer"),
    ]
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Main View

struct SpiritualHealthView: View {
    @StateObject private var store = SpiritualHealthStore.shared
    @State private var selectedTab: SHTab = .overview
    @State private var showCheckInSheet = false
    @State private var showReflectionSheet = false
    @State private var selectedCheckIn: SpiritualCheckIn?
    @State private var selectedReflection: ReflectionEntry?
    @State private var appeared = false

    enum SHTab: String, CaseIterable {
        case overview   = "Overview"
        case history    = "History"
        case journal    = "Journal"
        case milestones = "Milestones"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader
                    tabPills
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    tabContent
                        .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                store.loadAll()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
                    appeared = true
                }
            }
            .onDisappear { store.stopListening() }
            .sheet(isPresented: $showCheckInSheet) {
                CheckInSheet(store: store)
            }
            .sheet(isPresented: $showReflectionSheet) {
                ReflectionEditorSheet(store: store, existingEntry: nil)
            }
            .sheet(item: $selectedReflection) { entry in
                ReflectionDetailSheet(entry: entry, store: store)
            }
        }
    }

    // MARK: - Hero Header

    private let heroInk        = Color(red: 0.13, green: 0.11, blue: 0.09)
    private let heroSecondary  = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let heroPurple     = Color(red: 0.28, green: 0.15, blue: 0.65)

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Off-white parchment base
            Color(red: 0.97, green: 0.96, blue: 0.94)

            // Soft purple radial wash — top trailing
            RadialGradient(
                colors: [heroPurple.opacity(0.09), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 260
            )

            // Decorative ruled lines
            VStack(spacing: 18) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(heroPurple.opacity(0.04))
                        .frame(height: 1)
                }
            }
            .padding(.top, 110)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Top row: streak badge (right-aligned)
                HStack {
                    Spacer()
                    if store.currentStreak > 0 {
                        HStack(spacing: 5) {
                            Text("🔥")
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(store.currentStreak) week\(store.currentStreak == 1 ? "" : "s")")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(heroInk)
                                Text("streak")
                                    .font(.system(size: 10))
                                    .foregroundStyle(heroSecondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(heroPurple.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(heroPurple.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.top, 56)
                .padding(.bottom, 16)

                // Eyebrow
                Text("SPIRITUAL HEALTH")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(2.2)
                    .foregroundStyle(heroSecondary)
                    .padding(.bottom, 8)

                // Title — editorial serif
                Text("Your Faith,\nYour Journey")
                    .font(.custom("Georgia", size: 34))
                    .fontWeight(.regular)
                    .foregroundStyle(heroInk)
                    .lineSpacing(3)
                    .padding(.bottom, 10)

                Text("Weekly check-ins for scripture, prayer & growth.")
                    .font(.system(size: 13))
                    .foregroundStyle(heroSecondary)
                    .padding(.bottom, 20)

                // CTA pill
                Button {
                    showCheckInSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                        Text(hasThisWeeksCheckIn ? "Update This Week" : "Start Check-In")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(heroPurple, in: Capsule())
                    .shadow(color: heroPurple.opacity(0.30), radius: 10, y: 4)
                }
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
    }

    private var hasThisWeeksCheckIn: Bool {
        let cal = Calendar.current
        let thisWeek = cal.startOfWeek(for: Date())
        return store.checkIns.contains {
            cal.isDate(cal.startOfWeek(for: $0.weekOf), equalTo: thisWeek, toGranularity: .weekOfYear)
        }
    }

    // MARK: - Tab Pills

    private var tabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SHTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if selectedTab == tab {
                                        Capsule()
                                            .fill(Color(red: 0.28, green: 0.15, blue: 0.65))
                                    } else {
                                        Capsule()
                                            .fill(Color(.secondarySystemBackground))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:   overviewTab
        case .history:    historyTab
        case .journal:    journalTab
        case .milestones: milestonesTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 20) {
            // Latest score card
            if let latest = store.checkIns.first {
                latestScoreCard(checkIn: latest)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            } else {
                emptyOverviewCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            // 8-week trend sparkline
            if store.checkIns.count >= 2 {
                trendChart
                    .padding(.horizontal, 20)
            }

            // 5 dimensions breakdown
            if let latest = store.checkIns.first {
                dimensionsCard(checkIn: latest)
                    .padding(.horizontal, 20)
            }

            // Berean AI weekly prompt
            bereanPromptCard
                .padding(.horizontal, 20)

            // Quick actions
            HStack(spacing: 12) {
                Button {
                    showCheckInSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Check In")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.28, green: 0.15, blue: 0.65), in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showReflectionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.and.scribble")
                        Text("Reflect")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.28, green: 0.15, blue: 0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.93, green: 0.90, blue: 1.0), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)

            // Wellness Exercises
            VStack(alignment: .leading, spacing: 12) {
                Text("Wellness Exercises")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 20)
                
                VStack(spacing: 10) {
                    NavigationLink(destination: BreathingExerciseView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "wind")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Breathing Exercise")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Calm your mind and center yourself")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink(destination: MovementWellnessView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Movement Wellness")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Gentle movements for body and soul")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink(destination: SleepHygieneView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 12))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sleep Hygiene")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Rest well and restore your spirit")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyOverviewCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
            Text("Start Your First Check-In")
                .font(.system(size: 18, weight: .bold))
            Text("Track your spiritual health each week — scripture, prayer, community, mindset, and gratitude.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func latestScoreCard(checkIn: SpiritualCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Spiritual Health Score")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
                Text(checkIn.mood.emoji)
                    .font(.system(size: 32))
            }

            // Score dial
            HStack(alignment: .bottom, spacing: 0) {
                Text(String(format: "%.1f", checkIn.overallScore))
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(scoreColor(checkIn.overallScore))
                Text("/5")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(checkIn.mood.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(checkIn.mood.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(checkIn.mood.color.opacity(0.12), in: Capsule())

                    let weekStr = weekLabel(checkIn.weekOf)
                    Text(weekStr)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [scoreColor(checkIn.overallScore).opacity(0.7), scoreColor(checkIn.overallScore)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(checkIn.overallScore / 5.0), height: 8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: checkIn.overallScore)
                }
            }
            .frame(height: 8)

            if !checkIn.reflectionNote.isEmpty {
                Text("\"\(checkIn.reflectionNote)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(scoreColor(store.checkIns.first?.overallScore ?? 3).opacity(0.2), lineWidth: 1.5)
        )
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 4.5 { return Color(red: 0.95, green: 0.70, blue: 0.10) }
        if score >= 3.5 { return Color(red: 0.20, green: 0.65, blue: 0.38) }
        if score >= 2.5 { return Color(red: 0.28, green: 0.52, blue: 0.90) }
        return Color(red: 0.55, green: 0.35, blue: 0.85)
    }

    private func weekLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, equalTo: cal.startOfWeek(for: Date()), toGranularity: .weekOfYear) {
            return "This week"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Week of \(f.string(from: date))"
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("8-Week Trend")
                .font(.system(size: 16, weight: .bold))

            let last8 = Array(store.checkIns.prefix(8).reversed())
            let maxScore = 5.0

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let stepX = last8.count > 1 ? w / CGFloat(last8.count - 1) : w
                let points: [CGPoint] = last8.enumerated().map { i, c in
                    CGPoint(
                        x: CGFloat(i) * stepX,
                        y: h - CGFloat(c.overallScore / maxScore) * h
                    )
                }

                ZStack {
                    // Grid lines
                    ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { v in
                        Path { p in
                            let y = h - CGFloat(v / maxScore) * h
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color(.systemGray5), lineWidth: 1)
                    }

                    // Area fill
                    if points.count > 1, let lastPoint = points.last {
                        Path { p in
                            p.move(to: CGPoint(x: points[0].x, y: h))
                            p.addLine(to: points[0])
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                            p.addLine(to: CGPoint(x: lastPoint.x, y: h))
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.25), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Line
                    if points.count > 1 {
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Color(red: 0.42, green: 0.24, blue: 0.82), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    // Dots
                    ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                        Circle()
                            .fill(scoreColor(last8[i].overallScore))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .position(pt)
                    }
                }
            }
            .frame(height: 100)
            .padding(.top, 4)

            // Week labels
            HStack {
                let last8 = Array(store.checkIns.prefix(8).reversed())
                ForEach(Array(last8.enumerated()), id: \.offset) { i, c in
                    Text("W\(i + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if i < last8.count - 1 { Spacer() }
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func dimensionsCard(checkIn: SpiritualCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("5 Dimensions")
                .font(.system(size: 16, weight: .bold))

            let dims: [(String, String, Int, Color)] = [
                ("Scripture", "book.fill", checkIn.scoreScripture, Color(red: 0.20, green: 0.65, blue: 0.38)),
                ("Prayer", "hands.sparkles.fill", checkIn.scorePrayer, Color(red: 0.42, green: 0.24, blue: 0.82)),
                ("Community", "person.3.fill", checkIn.scoreCommunity, Color(red: 0.28, green: 0.52, blue: 0.90)),
                ("Mindset", "brain.head.profile", checkIn.scoreMindset, Color(red: 0.85, green: 0.47, blue: 0.10)),
                ("Gratitude", "heart.fill", checkIn.scoreGratitude, Color(red: 0.85, green: 0.20, blue: 0.35)),
            ]

            VStack(spacing: 12) {
                ForEach(dims, id: \.0) { name, icon, score, color in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 15))
                            .foregroundStyle(color)
                            .frame(width: 22)
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: geo.size.width * CGFloat(score) / 5.0, height: 6)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: score)
                            }
                        }
                        .frame(height: 6)
                        Text("\(score)/5")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // Rotating set of Berean AI-style reflection prompts
    private var bereanPromptCard: some View {
        let prompts = [
            ("\"Be still, and know that I am God.\"", "Psalm 46:10", "Where in your life do you need to stop striving and simply trust God this week?"),
            ("\"Your word is a lamp to my feet and a light to my path.\"", "Psalm 119:105", "How has scripture guided a specific decision or emotion for you recently?"),
            ("\"Therefore, if anyone is in Christ, he is a new creation.\"", "2 Corinthians 5:17", "What old pattern or belief is God inviting you to release this season?"),
            ("\"I can do all this through him who gives me strength.\"", "Philippians 4:13", "What feels impossible right now? How might God be calling you to depend on Him?"),
        ]
        let idx = (Calendar.current.component(.weekOfYear, from: Date()) - 1) % prompts.count
        let prompt = prompts[idx]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                Text("Berean Reflection Prompt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                Spacer()
                Text("This week")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(prompt.0)
                .font(.system(size: 16, weight: .semibold))
                .italic()
                .foregroundStyle(.primary)

            Text(prompt.1)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))

            Divider()

            Text(prompt.2)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button {
                showReflectionSheet = true
            } label: {
                Text("Write a Reflection")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(red: 0.93, green: 0.90, blue: 1.0), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - History Tab

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check-In History")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if store.checkIns.isEmpty {
                emptyOverviewCard
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(store.checkIns.enumerated()), id: \.element.id) { idx, ci in
                        historyRow(ci, delay: Double(idx) * 0.04)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func historyRow(_ ci: SpiritualCheckIn, delay: Double) -> some View {
        HStack(spacing: 14) {
            // Date block
            VStack(spacing: 2) {
                let cal = Calendar.current
                Text(monthShort(ci.weekOf))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(cal.component(.day, from: ci.weekOf))")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.primary)
            }
            .frame(width: 40)

            // Score bar + mood
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(ci.mood.emoji + " " + ci.mood.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ci.mood.color)
                    Spacer()
                    Text(String(format: "%.1f / 5", ci.overallScore))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(scoreColor(ci.overallScore))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(scoreColor(ci.overallScore))
                            .frame(width: geo.size.width * CGFloat(ci.overallScore / 5.0), height: 5)
                    }
                }
                .frame(height: 5)
                if !ci.reflectionNote.isEmpty {
                    Text(ci.reflectionNote)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: appeared)
    }

    private func monthShort(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: d)
    }

    // MARK: - Journal Tab

    private var journalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reflections")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    showReflectionSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if store.reflections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.5))
                    Text("No reflections yet")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Write your first faith reflection — a verse, a prayer, or something God is teaching you.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(store.reflections.enumerated()), id: \.element.id) { idx, entry in
                        reflectionCard(entry, delay: Double(idx) * 0.05)
                            .onTapGesture { selectedReflection = entry }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func reflectionCard(_ entry: ReflectionEntry, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(relativeDate(entry.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !entry.scripture.isEmpty {
                Text(entry.scripture)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
            }
            Text(entry.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !entry.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.93, green: 0.90, blue: 1.0), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: appeared)
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 86400 { return "Today" }
        if diff < 86400 * 2 { return "Yesterday" }
        if diff < 86400 * 7 { return "\(diff / 86400)d ago" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }

    // MARK: - Milestones Tab

    private var milestonesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Growth Milestones")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            LazyVStack(spacing: 12) {
                ForEach(Array(SpiritualHealthStore.milestones.enumerated()), id: \.element.id) { idx, milestone in
                    milestoneCard(milestone, achieved: isAchieved(milestone), delay: Double(idx) * 0.05)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func isAchieved(_ milestone: GrowthMilestone) -> Bool {
        switch milestone.category {
        case "Consistency": return store.currentStreak >= milestone.target
        case "Reflection":  return store.reflections.count >= milestone.target
        case "Scripture":   return store.checkIns.filter { $0.scoreScripture == 5 }.count >= milestone.target
        case "Prayer":      return store.checkIns.filter { $0.scorePrayer == 5 }.count >= milestone.target
        default: return false
        }
    }

    private func milestoneCard(_ m: GrowthMilestone, achieved: Bool, delay: Double) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(achieved ? m.color : Color(.systemGray5))
                    .frame(width: 52, height: 52)
                Image(systemName: m.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(achieved ? .white : Color(.systemGray3))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(achieved ? .primary : .secondary)
                    if achieved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                }
                Text(m.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(m.category)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(m.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(m.color.opacity(0.12), in: Capsule())
            }
            Spacer()

            if !achieved {
                Text("\(progressValue(m))/\(m.target)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(achieved ? m.color.opacity(0.08) : Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(achieved ? m.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: appeared)
    }

    private func progressValue(_ m: GrowthMilestone) -> Int {
        switch m.category {
        case "Consistency": return store.currentStreak
        case "Reflection":  return store.reflections.count
        case "Scripture":   return store.checkIns.filter { $0.scoreScripture == 5 }.count
        case "Prayer":      return store.checkIns.filter { $0.scorePrayer == 5 }.count
        default: return 0
        }
    }
}

// MARK: - Check-In Sheet

struct CheckInSheet: View {
    @ObservedObject var store: SpiritualHealthStore
    @Environment(\.dismiss) private var dismiss

    @State private var scoreScripture: Int = 3
    @State private var scorePrayer: Int = 3
    @State private var scoreCommunity: Int = 3
    @State private var scoreMindset: Int = 3
    @State private var scoreGratitude: Int = 3
    @State private var selectedMood: SpiritualMood = .steady
    @State private var reflectionNote: String = ""
    @State private var prayerRequest: String = ""
    @State private var isSaving = false
    @State private var currentStep = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Progress steps
                    progressIndicator
                        .padding(.top, 8)

                    if currentStep == 0 {
                        moodStep
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    } else if currentStep == 1 {
                        dimensionsStep
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    } else {
                        reflectionStep
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    }

                    navigationButtons
                }
                .padding(20)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentStep)
            }
            .navigationTitle("Weekly Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i <= currentStep ? Color(red: 0.42, green: 0.24, blue: 0.82) : Color(.systemGray5))
                    .frame(height: 5)
                    .animation(.easeOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // Step 0: Mood
    private var moodStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How are you spiritually?")
                    .font(.system(size: 22, weight: .bold))
                Text("Be honest — this is just for you.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SpiritualMood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMood = mood
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(mood.emoji)
                                .font(.system(size: 30))
                            Text(mood.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedMood == mood ? .white : .primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            Group {
                                if selectedMood == mood {
                                    RoundedRectangle(cornerRadius: 14).fill(mood.color)
                                } else {
                                    RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedMood == mood ? mood.color : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Step 1: 5 dimensions
    private var dimensionsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rate your week")
                    .font(.system(size: 22, weight: .bold))
                Text("Score each area 1 (low) – 5 (high)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            let dims: [(String, String, Binding<Int>, Color)] = [
                ("Scripture", "book.fill", $scoreScripture, Color(red: 0.20, green: 0.65, blue: 0.38)),
                ("Prayer", "hands.sparkles.fill", $scorePrayer, Color(red: 0.42, green: 0.24, blue: 0.82)),
                ("Community", "person.3.fill", $scoreCommunity, Color(red: 0.28, green: 0.52, blue: 0.90)),
                ("Mindset", "brain.head.profile", $scoreMindset, Color(red: 0.85, green: 0.47, blue: 0.10)),
                ("Gratitude", "heart.fill", $scoreGratitude, Color(red: 0.85, green: 0.20, blue: 0.35)),
            ]
            VStack(spacing: 20) {
                ForEach(dims, id: \.0) { name, icon, score, color in
                    dimensionSlider(name: name, icon: icon, score: score, color: color)
                }
            }
        }
    }

    private func dimensionSlider(name: String, icon: String, score: Binding<Int>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(score.wrappedValue)/5")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { val in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            score.wrappedValue = val
                        }
                        let hap = UIImpactFeedbackGenerator(style: .light)
                        hap.impactOccurred()
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(val <= score.wrappedValue ? color : Color(.systemGray5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .overlay(
                                Text("\(val)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(val <= score.wrappedValue ? .white : Color(.systemGray2))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Step 2: Reflection
    private var reflectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reflect & Pray")
                    .font(.system(size: 22, weight: .bold))
                Text("Optional — share what's on your heart.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection Note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $reflectionNote)
                    .font(.system(size: 15))
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Group {
                            if reflectionNote.isEmpty {
                                Text("What did God show you this week?")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    )
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Prayer Request")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Share a prayer request (optional)...", text: $prayerRequest, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(3...5)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentStep -= 1
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Button {
                if currentStep < 2 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentStep += 1
                    }
                } else {
                    saveCheckIn()
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(currentStep < 2 ? "Continue" : "Save Check-In")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color(red: 0.42, green: 0.24, blue: 0.82), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)
            .buttonStyle(.plain)
        }
    }

    private func saveCheckIn() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let cal = Calendar.current
        let weekOf = cal.startOfWeek(for: Date())
        let checkIn = SpiritualCheckIn(
            userID: uid,
            weekOf: weekOf,
            scoreScripture: scoreScripture,
            scorePrayer: scorePrayer,
            scoreCommunity: scoreCommunity,
            scoreMindset: scoreMindset,
            scoreGratitude: scoreGratitude,
            reflectionNote: reflectionNote,
            prayerRequest: prayerRequest,
            mood: selectedMood,
            createdAt: Date()
        )
        Task {
            do {
                try await store.saveCheckIn(checkIn)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run { isSaving = false }
            }
        }
    }
}

// MARK: - Reflection Editor Sheet

struct ReflectionEditorSheet: View {
    @ObservedObject var store: SpiritualHealthStore
    var existingEntry: ReflectionEntry?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var scripture: String = ""
    @State private var tagsText: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Give this reflection a title", text: $title)
                }
                Section("Scripture") {
                    TextField("e.g. John 3:16", text: $scripture)
                }
                Section("Reflection") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 140)
                }
                Section("Tags (comma separated)") {
                    TextField("peace, prayer, identity", text: $tagsText)
                }
            }
            .navigationTitle(existingEntry == nil ? "New Reflection" : "Edit Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveReflection()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let e = existingEntry {
                    title = e.title
                    body_ = e.body
                    scripture = e.scripture
                    tagsText = e.tags.joined(separator: ", ")
                }
            }
        }
    }

    private func saveReflection() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var entry = existingEntry ?? ReflectionEntry(userID: uid, title: "", body: "", scripture: "", tags: [], createdAt: Date())
        entry.userID = uid
        entry.title = title.trimmingCharacters(in: .whitespaces)
        entry.body = body_
        entry.scripture = scripture
        entry.tags = tags
        Task {
            do {
                try await store.saveReflection(entry)
                await MainActor.run { isSaving = false; dismiss() }
            } catch {
                await MainActor.run { isSaving = false }
            }
        }
    }
}

// MARK: - Reflection Detail Sheet

struct ReflectionDetailSheet: View {
    var entry: ReflectionEntry
    @ObservedObject var store: SpiritualHealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(entry.title)
                        .font(.system(size: 24, weight: .bold))
                    if !entry.scripture.isEmpty {
                        Text(entry.scripture)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.93, green: 0.90, blue: 1.0), in: Capsule())
                    }
                    Text(entry.body)
                        .font(.system(size: 16))
                        .lineSpacing(6)
                    if !entry.tags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(entry.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(red: 0.93, green: 0.90, blue: 1.0), in: Capsule())
                            }
                        }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showEditSheet = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Delete Reflection", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await store.deleteReflection(entry.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This reflection will be permanently deleted.")
            }
            .sheet(isPresented: $showEditSheet) {
                ReflectionEditorSheet(store: store, existingEntry: entry)
            }
        }
    }
}

// MARK: - Entry Card for ResourcesView

struct SpiritualHealthEntryCard: View {
    @StateObject private var store = SpiritualHealthStore.shared
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.28, green: 0.15, blue: 0.65), Color(red: 0.52, green: 0.20, blue: 0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spiritual Health")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Weekly check-ins · Growth tracking · Reflections")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if store.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                            .font(.system(size: 12))
                        Text("\(store.currentStreak)-week streak")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.10))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.15), lineWidth: 1)
                )
        )
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }
}
