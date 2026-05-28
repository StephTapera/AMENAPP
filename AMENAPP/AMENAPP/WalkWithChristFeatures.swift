// WalkWithChristFeatures.swift
// AMENAPP — Walk With Christ enhanced features:
//   • Season Discernment Engine
//   • Sunday-to-Week Application Path
//   • Faithful Follow-Through Planner

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

// MARK: - Spiritual Season

enum WalkSpiritualSeason: String, CaseIterable, Codable {
    case starting    = "Starting"
    case returning   = "Returning"
    case steady      = "Steady"
    case dry         = "Dry Season"
    case overwhelmed = "Overwhelmed"

    var icon: String {
        switch self {
        case .starting:    return "sunrise.fill"
        case .returning:   return "arrow.uturn.left.circle.fill"
        case .steady:      return "leaf.fill"
        case .dry:         return "cloud.sun.fill"
        case .overwhelmed: return "wind"
        }
    }

    var color: Color {
        switch self {
        case .starting:    return Color(red: 0.95, green: 0.70, blue: 0.25)
        case .returning:   return Color(red: 0.42, green: 0.72, blue: 0.58)
        case .steady:      return Color(red: 0.28, green: 0.62, blue: 0.92)
        case .dry:         return Color(red: 0.78, green: 0.55, blue: 0.35)
        case .overwhelmed: return Color(red: 0.70, green: 0.42, blue: 0.75)
        }
    }

    var description: String {
        switch self {
        case .starting:    return "New beginnings with God"
        case .returning:   return "Coming back to grace"
        case .steady:      return "Building consistency"
        case .dry:         return "Walking through dryness"
        case .overwhelmed: return "Finding rest in Him"
        }
    }

    var bereanPrompt: String {
        switch self {
        case .starting:
            return "I'm just starting my faith journey. What does the Bible say about new beginnings with God?"
        case .returning:
            return "I'm returning to faith after being away. What does the Bible say about coming back to God?"
        case .steady:
            return "I'm in a steady season with God. How do I go deeper and avoid complacency?"
        case .dry:
            return "I'm in a dry spiritual season — feeling distant from God. What does the Bible say about spiritual dryness?"
        case .overwhelmed:
            return "I feel spiritually overwhelmed. What does the Bible say about finding peace and rest in Christ?"
        }
    }

    var scripture: (text: String, ref: String) {
        switch self {
        case .starting:
            return ("Therefore, if anyone is in Christ, he is a new creation.", "2 Corinthians 5:17")
        case .returning:
            return ("But while he was still a long way off, his father saw him and felt compassion.", "Luke 15:20")
        case .steady:
            return ("Let us not grow weary of doing good, for in due season we will reap.", "Galatians 6:9")
        case .dry:
            return ("He does not faint or grow weary; his understanding is unsearchable.", "Isaiah 40:28")
        case .overwhelmed:
            return ("Come to me, all who labor and are heavy laden, and I will give you rest.", "Matthew 11:28")
        }
    }
}

// MARK: - Season Discernment Band

struct SeasonDiscernmentBandView: View {
    @Binding var selectedSeason: WalkSpiritualSeason?
    let onBereanTap: (String) -> Void

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPIRITUAL SEASON")
                        .font(.systemScaled(10, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(slate)
                    Text("Where are you right now?")
                        .font(.systemScaled(15, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                if let season = selectedSeason {
                    Button {
                        onBereanTap(season.bereanPrompt)
                    } label: {
                        Label("Ask Berean", systemImage: "sparkles")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(warm)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(warm.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WalkSpiritualSeason.allCases, id: \.self) { season in
                        SeasonPill(
                            season: season,
                            isSelected: selectedSeason == season
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedSeason = selectedSeason == season ? nil : season
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
            }

            if let season = selectedSeason {
                SeasonContextCard(season: season) {
                    onBereanTap(season.bereanPrompt)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

private struct SeasonPill: View {
    let season: WalkSpiritualSeason
    let isSelected: Bool
    let onTap: () -> Void

    private let ink = Color(red: 0.10, green: 0.09, blue: 0.09)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: season.icon)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : season.color)
                Text(season.rawValue)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? season.color : Color.white)
                    .shadow(color: season.color.opacity(isSelected ? 0.35 : 0.12), radius: 6, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : season.color.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SeasonContextCard: View {
    let season: WalkSpiritualSeason
    let onAskBerean: () -> Void

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(season.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(season.description)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(season.color)

                Text("\"\(season.scripture.text)\"")
                    .font(.systemScaled(13, design: .serif))
                    .italic()
                    .foregroundStyle(ink.opacity(0.80))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(season.scripture.ref)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(season.color.opacity(0.80))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(season.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(season.color.opacity(0.18), lineWidth: 0.8)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onAskBerean() }
    }
}

// MARK: - Sunday-to-Week Application Path

struct SundayApplicationPath: Identifiable, Codable {
    let id: String
    let sermonTitle: String
    let scriptureRef: String
    let keyTheme: String
    let applicationSteps: [String]
    let bereanPrompt: String
    let createdAt: Date
}

@MainActor
final class SundayApplicationViewModel: ObservableObject {
    @Published var currentPath: SundayApplicationPath?
    @Published var isLoading = false
    @Published var completedStepIndices: Set<Int> = []

    func loadLatestPath() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            currentPath = defaultApplicationPath()
            return
        }
        isLoading = true
        let db = Firestore.firestore()
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("walkWithChrist").document("applicationPaths")
                .collection("items")
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()

            if let doc = snap.documents.first {
                let data = doc.data()
                currentPath = SundayApplicationPath(
                    id: doc.documentID,
                    sermonTitle: data["sermonTitle"] as? String ?? "This Sunday's Message",
                    scriptureRef: data["scriptureRef"] as? String ?? "",
                    keyTheme: data["keyTheme"] as? String ?? "",
                    applicationSteps: data["applicationSteps"] as? [String] ?? defaultSteps(),
                    bereanPrompt: data["bereanPrompt"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                completedStepIndices = Set(data["completedSteps"] as? [Int] ?? [])
            } else {
                currentPath = defaultApplicationPath()
            }
        } catch {
            currentPath = defaultApplicationPath()
        }
        isLoading = false
    }

    func toggleStep(_ index: Int) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let pathId = currentPath?.id else { return }

        if completedStepIndices.contains(index) {
            completedStepIndices.remove(index)
        } else {
            completedStepIndices.insert(index)
        }

        let db = Firestore.firestore()
        try? await db
            .collection("users").document(uid)
            .collection("walkWithChrist").document("applicationPaths")
            .collection("items").document(pathId)
            .updateData(["completedSteps": Array(completedStepIndices)])
    }

    private func defaultSteps() -> [String] {
        [
            "Spend 5 minutes reflecting on Sunday's message",
            "Share one insight with someone this week",
            "Apply the main teaching in one decision today"
        ]
    }

    private func defaultApplicationPath() -> SundayApplicationPath {
        SundayApplicationPath(
            id: UUID().uuidString,
            sermonTitle: "Apply the Message This Week",
            scriptureRef: "James 1:22",
            keyTheme: "Be doers of the word",
            applicationSteps: [
                "Recall one truth from Sunday and write it down",
                "Ask: where does this truth meet my real life today?",
                "Share it with one person before the week ends"
            ],
            bereanPrompt: "How do I apply what I hear in church to my daily life?",
            createdAt: Date()
        )
    }
}

struct SundayApplicationCard: View {
    @StateObject private var vm = SundayApplicationViewModel()
    let onBereanTap: (String) -> Void

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEKLY APPLICATION")
                        .font(.systemScaled(10, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(slate)
                    Text("Sunday to Saturday")
                        .font(.systemScaled(15, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            if vm.isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(warm)
                    Text("Loading your path…")
                        .font(.systemScaled(13))
                        .foregroundStyle(slate)
                }
                .padding(.horizontal, 24)
            } else if let path = vm.currentPath {
                applicationCard(path: path)
                    .padding(.horizontal, 24)
            }
        }
        .task { await vm.loadLatestPath() }
    }

    @ViewBuilder
    private func applicationCard(path: SundayApplicationPath) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(warm.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "book.closed.fill")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(warm)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(path.sermonTitle)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    if !path.scriptureRef.isEmpty {
                        Text(path.scriptureRef)
                            .font(.systemScaled(12))
                            .foregroundStyle(warm)
                    }
                }
                Spacer()
            }

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)

            VStack(spacing: 8) {
                ForEach(Array(path.applicationSteps.enumerated()), id: \.offset) { index, step in
                    ApplicationStepRow(
                        index: index,
                        text: step,
                        isComplete: vm.completedStepIndices.contains(index)
                    ) {
                        Task { await vm.toggleStep(index) }
                    }
                }
            }

            let completedCount = vm.completedStepIndices.count
            let total = path.applicationSteps.count

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.90, green: 0.88, blue: 0.84))
                            .frame(height: 4)
                        Capsule()
                            .fill(warm)
                            .frame(
                                width: total > 0
                                    ? geo.size.width * CGFloat(completedCount) / CGFloat(total)
                                    : 0,
                                height: 4
                            )
                            .animation(.easeOut(duration: 0.4), value: completedCount)
                    }
                }
                .frame(height: 4)

                Text("\(completedCount)/\(total)")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(warm)
            }

            if !path.bereanPrompt.isEmpty {
                Button {
                    onBereanTap(path.bereanPrompt)
                } label: {
                    Label("Explore with Berean", systemImage: "sparkles")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(warm)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(warm.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(warm.opacity(0.20), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color(red: 0.10, green: 0.09, blue: 0.09).opacity(0.07), radius: 8, y: 2)
        )
    }
}

private struct ApplicationStepRow: View {
    let index: Int
    let text: String
    let isComplete: Bool
    let onToggle: () -> Void

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isComplete ? warm : Color(red: 0.92, green: 0.90, blue: 0.86))
                        .frame(width: 24, height: 24)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.systemScaled(10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(slate)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isComplete)

                Text(text)
                    .font(.systemScaled(13))
                    .foregroundStyle(isComplete ? slate : ink)
                    .strikethrough(isComplete, color: slate.opacity(0.5))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: isComplete)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Faithful Follow-Through Planner

enum FollowThroughArea: String, CaseIterable, Codable {
    case prayer    = "Prayer"
    case scripture = "Scripture"
    case service   = "Service"
    case community = "Community"
    case gratitude = "Gratitude"
    case fasting   = "Fasting"

    var icon: String {
        switch self {
        case .prayer:    return "hands.sparkles.fill"
        case .scripture: return "book.fill"
        case .service:   return "figure.wave"
        case .community: return "person.3.fill"
        case .gratitude: return "heart.fill"
        case .fasting:   return "leaf.arrow.circlepath"
        }
    }

    var defaultBereanPrompt: String {
        switch self {
        case .prayer:    return "Help me build a consistent daily prayer habit"
        case .scripture: return "Give me a simple plan for reading Scripture daily"
        case .service:   return "How do I start serving others more intentionally?"
        case .community: return "How do I invest more deeply in Christian community?"
        case .gratitude: return "What does the Bible say about cultivating gratitude?"
        case .fasting:   return "How do I practice fasting as a spiritual discipline?"
        }
    }
}

enum FollowThroughFrequency: String, CaseIterable, Codable {
    case daily    = "Daily"
    case weekdays = "Weekdays"
    case weekly   = "Weekly"

    var notificationWeekdays: [Int] {
        switch self {
        case .daily:    return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekly:   return [1]
        }
    }
}

struct WalkFollowThroughPlan: Identifiable, Codable {
    var id: String = UUID().uuidString
    var commitment: String = ""
    var practiceArea: FollowThroughArea = .prayer
    var frequency: FollowThroughFrequency = .daily
    var reminderHour: Int = 8
    var reminderEnabled: Bool = true
    var bereanContext: String = ""
    var createdAt: Date = Date()
    var completedDates: [Date] = []

    var isActive: Bool {
        guard let last = completedDates.max() else { return false }
        return Calendar.current.isDateInToday(last) || Calendar.current.isDateInYesterday(last)
    }

    var streakDays: Int {
        guard !completedDates.isEmpty else { return 0 }
        var streak = 0
        var check = Calendar.current.startOfDay(for: Date())
        let sorted = completedDates
            .map { Calendar.current.startOfDay(for: $0) }
            .sorted(by: >)
        for date in sorted {
            if Calendar.current.isDate(date, inSameDayAs: check) {
                streak += 1
                guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: check) else { break }
                check = previous
            } else { break }
        }
        return streak
    }
}

@MainActor
final class FaithfulFollowThroughViewModel: ObservableObject {
    @Published var plans: [WalkFollowThroughPlan] = []
    @Published var isLoading = false
    @Published var isSaving = false

    func loadPlans() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        let db = Firestore.firestore()
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("walkWithChrist").document("followThrough")
                .collection("plans")
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments()

            plans = snap.documents.compactMap { doc in
                let d = doc.data()
                return WalkFollowThroughPlan(
                    id: doc.documentID,
                    commitment: d["commitment"] as? String ?? "",
                    practiceArea: FollowThroughArea(rawValue: d["practiceArea"] as? String ?? "") ?? .prayer,
                    frequency: FollowThroughFrequency(rawValue: d["frequency"] as? String ?? "") ?? .daily,
                    reminderHour: d["reminderHour"] as? Int ?? 8,
                    reminderEnabled: d["reminderEnabled"] as? Bool ?? true,
                    bereanContext: d["bereanContext"] as? String ?? "",
                    createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    completedDates: (d["completedDates"] as? [Timestamp])?.map { $0.dateValue() } ?? []
                )
            }
        } catch {
            dlog("⚠️ FaithfulFollowThrough loadPlans: \(error)")
        }
        isLoading = false
    }

    func savePlan(_ plan: WalkFollowThroughPlan) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let db = Firestore.firestore()
        do {
            try await db
                .collection("users").document(uid)
                .collection("walkWithChrist").document("followThrough")
                .collection("plans").document(plan.id)
                .setData([
                    "commitment": plan.commitment,
                    "practiceArea": plan.practiceArea.rawValue,
                    "frequency": plan.frequency.rawValue,
                    "reminderHour": plan.reminderHour,
                    "reminderEnabled": plan.reminderEnabled,
                    "bereanContext": plan.bereanContext,
                    "createdAt": Timestamp(date: plan.createdAt),
                    "completedDates": plan.completedDates.map { Timestamp(date: $0) }
                ])

            if plan.reminderEnabled {
                scheduleNotifications(for: plan)
            }
            if !plans.contains(where: { $0.id == plan.id }) {
                plans.insert(plan, at: 0)
            }
        } catch {
            dlog("⚠️ FaithfulFollowThrough savePlan: \(error)")
        }
        isSaving = false
    }

    func markTodayComplete(planId: String) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let idx = plans.firstIndex(where: { $0.id == planId }) else { return }

        let today = Date()
        plans[idx].completedDates.append(today)

        let db = Firestore.firestore()
        try? await db
            .collection("users").document(uid)
            .collection("walkWithChrist").document("followThrough")
            .collection("plans").document(planId)
            .updateData(["completedDates": FieldValue.arrayUnion([Timestamp(date: today)])])
    }

    private func scheduleNotifications(for plan: WalkFollowThroughPlan) {
        let center = UNUserNotificationCenter.current()
        let ids = plan.frequency.notificationWeekdays.map { "\(plan.id)_day\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let content = UNMutableNotificationContent()
        content.title = "Follow-Through Time"
        content.body = plan.commitment.isEmpty
            ? "Time for your \(plan.practiceArea.rawValue.lowercased()) practice."
            : plan.commitment
        content.sound = .default

        for weekday in plan.frequency.notificationWeekdays {
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = plan.reminderHour
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(plan.id)_day\(weekday)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}

// MARK: - Faithful Follow-Through Planner Sheet

struct FaithfulFollowThroughPlannerSheet: View {
    @ObservedObject var vm: FaithfulFollowThroughViewModel
    @Environment(\.dismiss) private var dismiss
    let onBereanTap: (String) -> Void

    @State private var commitment = ""
    @State private var selectedArea: FollowThroughArea = .prayer
    @State private var selectedFrequency: FollowThroughFrequency = .daily
    @State private var reminderEnabled = true
    @State private var reminderHour = 8
    @State private var isSaved = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerRow
                    commitmentField
                    practiceAreaGrid
                    frequencyRow
                    reminderRow
                    bereanButton
                    saveButton
                    Color.clear.frame(height: 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sub-views

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FAITHFUL FOLLOW-THROUGH")
                    .font(.systemScaled(10, weight: .semibold))
                    .kerning(1.5)
                    .foregroundStyle(slate)
                Text("Make a faith commitment")
                    .font(.systemScaled(22, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(slate)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(white: 0.92)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var commitmentField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is your commitment?")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(ink)

            ZStack(alignment: .topLeading) {
                if commitment.isEmpty {
                    Text("e.g., I will spend 10 minutes in prayer each morning")
                        .font(.systemScaled(14))
                        .foregroundStyle(slate.opacity(0.6))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $commitment)
                    .font(.systemScaled(14))
                    .foregroundStyle(ink)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: ink.opacity(0.06), radius: 4, y: 1)
            )
        }
        .padding(.horizontal, 24)
    }

    private var practiceAreaGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Practice area")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(ink)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(FollowThroughArea.allCases, id: \.self) { area in
                    AreaChip(area: area, isSelected: selectedArea == area) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedArea = area
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var frequencyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How often?")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(ink)

            HStack(spacing: 8) {
                ForEach(FollowThroughFrequency.allCases, id: \.self) { freq in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFrequency = freq
                        }
                    } label: {
                        Text(freq.rawValue)
                            .font(.systemScaled(13, weight: selectedFrequency == freq ? .semibold : .regular))
                            .foregroundStyle(selectedFrequency == freq ? .white : ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedFrequency == freq ? ink : Color.white)
                                    .shadow(color: ink.opacity(0.06), radius: 4, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reminder")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Toggle("", isOn: $reminderEnabled)
                    .labelsHidden()
                    .tint(warm)
            }

            if reminderEnabled {
                HStack {
                    Text("Time")
                        .font(.systemScaled(13))
                        .foregroundStyle(slate)
                    Spacer()
                    Picker("Reminder Hour", selection: $reminderHour) {
                        ForEach([6, 7, 8, 9, 10, 12, 18, 20, 21], id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(warm)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: ink.opacity(0.06), radius: 4, y: 1)
        )
        .padding(.horizontal, 24)
    }

    private var bereanButton: some View {
        Button {
            let prompt = commitment.isEmpty
                ? selectedArea.defaultBereanPrompt
                : "Help me stay faithful to this commitment: \(commitment)"
            onBereanTap(prompt)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(14, weight: .semibold))
                Text("Get Berean Guidance")
                    .font(.systemScaled(14, weight: .semibold))
            }
            .foregroundStyle(warm)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(warm.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(warm.opacity(0.20), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private var saveButton: some View {
        Button {
            Task { await savePlan() }
        } label: {
            Group {
                if vm.isSaving {
                    ProgressView().tint(.white)
                } else if isSaved {
                    Label("Saved!", systemImage: "checkmark")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("Commit to This Plan")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(commitment.isEmpty ? Color(white: 0.75) : ink)
            )
        }
        .buttonStyle(.plain)
        .disabled(commitment.isEmpty || vm.isSaving)
        .padding(.horizontal, 24)
    }

    private func savePlan() async {
        let plan = WalkFollowThroughPlan(
            commitment: commitment,
            practiceArea: selectedArea,
            frequency: selectedFrequency,
            reminderHour: reminderHour,
            reminderEnabled: reminderEnabled
        )
        await vm.savePlan(plan)
        withAnimation { isSaved = true }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        dismiss()
    }

    private func hourLabel(_ h: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = h
        comps.minute = 0
        guard let date = Calendar.current.date(from: comps) else { return "\(h):00" }
        return fmt.string(from: date)
    }
}

// MARK: - Follow-Through Plans Section (in main scroll)

struct FollowThroughPlansSection: View {
    @ObservedObject var vm: FaithfulFollowThroughViewModel
    let onShowPlanner: () -> Void
    let onBereanTap: (String) -> Void

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOLLOW-THROUGH")
                        .font(.systemScaled(10, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(slate)
                    Text("Faithful Commitments")
                        .font(.systemScaled(15, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Button(action: onShowPlanner) {
                    Label("New Plan", systemImage: "plus")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(warm)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(warm.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            if vm.plans.isEmpty {
                emptyState
            } else {
                plansList
            }
        }
        .task { await vm.loadPlans() }
    }

    private var emptyState: some View {
        Button(action: onShowPlanner) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(warm.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(warm)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create your first plan")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(ink)
                    Text("Build consistency with a simple faith commitment")
                        .font(.systemScaled(12))
                        .foregroundStyle(slate)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(slate.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private var plansList: some View {
        VStack(spacing: 10) {
            ForEach(vm.plans.prefix(3)) { plan in
                FollowThroughPlanRow(plan: plan) {
                    Task { await vm.markTodayComplete(planId: plan.id) }
                } onBerean: {
                    onBereanTap(
                        plan.bereanContext.isEmpty
                            ? plan.practiceArea.defaultBereanPrompt
                            : plan.bereanContext
                    )
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct FollowThroughPlanRow: View {
    let plan: WalkFollowThroughPlan
    let onCheckOff: () -> Void
    let onBerean: () -> Void

    @State private var tappedToday = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)

    private var isDoneToday: Bool { tappedToday || plan.isActive }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(warm.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: plan.practiceArea.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(warm)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.commitment)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(plan.frequency.rawValue)
                        .font(.systemScaled(11))
                        .foregroundStyle(slate)
                    if plan.streakDays > 0 {
                        Text("·").foregroundStyle(slate.opacity(0.5))
                        Text("\(plan.streakDays)d streak")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(warm)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tappedToday = true
                }
                onCheckOff()
            } label: {
                ZStack {
                    Circle()
                        .fill(isDoneToday ? warm : Color(red: 0.92, green: 0.90, blue: 0.86))
                        .frame(width: 30, height: 30)
                    Image(systemName: "checkmark")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(isDoneToday ? .white : slate.opacity(0.4))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
        )
        .onAppear { tappedToday = plan.isActive }
    }
}

// MARK: - Area Chip (used in FaithfulFollowThroughPlannerSheet)

private struct AreaChip: View {
    let area: FollowThroughArea
    let isSelected: Bool
    let onTap: () -> Void

    private let ink  = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let warm = Color(red: 0.62, green: 0.48, blue: 0.30)

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: area.icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isSelected ? .white : warm)
                Text(area.rawValue)
                    .font(.systemScaled(11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? ink : Color.white)
                    .shadow(color: ink.opacity(0.06), radius: 4, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
