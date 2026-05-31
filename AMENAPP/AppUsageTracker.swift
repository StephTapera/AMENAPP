//
//  AppUsageTracker.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Tracks daily app usage time and shows reminders when limit is reached
//

import SwiftUI
import Combine

/// One day's usage record — used by WellbeingDashboardView's Charts bar chart.
struct UsageDayEntry: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let minutes: Int
}

/// Tracks app usage time and manages daily time limits
@MainActor
class AppUsageTracker: ObservableObject {
    static let shared = AppUsageTracker()
    
    @Published var todayUsageMinutes: Int = 0
    @Published var dailyLimitMinutes: Int = 45
    @Published var showLimitReachedDialog: Bool = false
    @Published var hasShownLimitDialog: Bool = false
    /// Frozen snapshot of todayUsageMinutes captured the moment the limit dialog fires.
    /// Used by DailyLimitReachedDialog so the displayed count doesn't tick live.
    @Published var snapshotUsageMinutes: Int = 0
    
    private var sessionStartTime: Date?
    private var currentSessionStartTime: Date?  // Track current continuous session
    private var timer: Timer?
    private var lastSaveDate: Date?
    
    private let usageKey = "app_usage_today"
    private let limitKey = "daily_time_limit"
    private let lastSaveDateKey = "last_save_date"
    private let historyKey = "app_usage_week_history_v1"

    // Archived daily entries for the past 7 days (does not include today).
    @Published private var archivedHistory: [UsageDayEntry] = []
    
    // Smart break reminder integration
    private let smartBreakReminder = SmartBreakReminderService.shared
    
    private init() {
        loadUsageData()
        setupTimer()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking session when app becomes active
    func startSession() {
        // Guard against duplicate calls (e.g. scenePhase .active + ContentView .task)
        guard sessionStartTime == nil else { return }
        sessionStartTime = Date()
        currentSessionStartTime = Date()  // Start continuous session tracking
        dlog("📊 AppUsageTracker: Session started")
    }
    
    /// End tracking session when app becomes inactive
    func endSession() {
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        let sessionMinutes = Int(sessionDuration / 60)
        
        todayUsageMinutes += sessionMinutes
        saveUsageData()
        sessionStartTime = nil
        currentSessionStartTime = nil  // End continuous session tracking
        
        dlog("📊 AppUsageTracker: Session ended. Duration: \(sessionMinutes) minutes. Total today: \(todayUsageMinutes) minutes")
    }
    
    /// Update daily time limit
    func updateDailyLimit(_ minutes: Int) {
        dailyLimitMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: limitKey)
        dlog("⏱️ AppUsageTracker: Daily limit updated to \(minutes) minutes")
    }
    
    /// Reset usage for a new day
    func resetDailyUsage() {
        archiveYesterdayUsage()
        todayUsageMinutes = 0
        hasShownLimitDialog = false
        saveUsageData()

        // Also reset smart break reminder counters
        smartBreakReminder.resetDailyCounters()

        dlog("🔄 AppUsageTracker: Daily usage reset")
    }

    private func archiveYesterdayUsage() {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) else { return }
        let entry = UsageDayEntry(date: yesterday, minutes: todayUsageMinutes)
        var history = archivedHistory.filter { !cal.isDate($0.date, inSameDayAs: yesterday) }
        history.append(entry)
        let cutoff = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        archivedHistory = history.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if let encoded = try? JSONEncoder().encode(archivedHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    /// Check if limit has been reached
    var hasReachedLimit: Bool {
        todayUsageMinutes >= dailyLimitMinutes
    }
    
    /// Get remaining time in minutes
    var remainingMinutes: Int {
        max(0, dailyLimitMinutes - todayUsageMinutes)
    }
    
    /// Get progress percentage
    var usagePercentage: Double {
        guard dailyLimitMinutes > 0 else { return 0 }
        return min(1.0, Double(todayUsageMinutes) / Double(dailyLimitMinutes))
    }

    /// Past 7 days + today, sorted oldest→newest. Used by WellbeingDashboardView's chart.
    var weekHistoryForChart: [UsageDayEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        var entries = archivedHistory.filter {
            !Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        entries.append(UsageDayEntry(date: today, minutes: todayUsageMinutes))
        return entries.sorted { $0.date < $1.date }
    }

    /// Consecutive days (going backwards from yesterday) where usage was ≤ daily limit.
    var currentStreak: Int {
        var streak = 0
        let cal = Calendar.current
        for offset in 1...7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())),
                  let entry = archivedHistory.first(where: { cal.isDate($0.date, inSameDayAs: day) })
            else { break }
            if entry.minutes <= dailyLimitMinutes { streak += 1 } else { break }
        }
        return streak
    }
    
    // MARK: - Private Methods
    
    private func setupTimer() {
        // Update every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndUpdateUsage()
            }
        }
    }
    
    private func checkAndUpdateUsage() {
        guard sessionStartTime != nil else { return }
        
        // Increment usage by 1 minute
        todayUsageMinutes += 1
        saveUsageData()
        
        // Calculate continuous session duration
        let continuousMinutes: Int
        if let sessionStart = currentSessionStartTime {
            continuousMinutes = Int(Date().timeIntervalSince(sessionStart) / 60)
        } else {
            continuousMinutes = 0
        }
        
        // Check smart break reminder only when below the daily reminder cap.
        // Skipping the Task entirely when the limit is already exhausted avoids
        // spawning an async task + printing "limit reached" on every 1-minute tick
        // for users who have been using the app beyond their daily threshold.
        if smartBreakReminder.usageRemindersToday < 2 {
            Task {
                await smartBreakReminder.analyzeUsageAndRemind(
                    continuousMinutes: continuousMinutes,
                    totalMinutesToday: todayUsageMinutes,
                    dailyLimit: dailyLimitMinutes
                )
            }
        }
        
        // Check if we've JUST reached the limit and haven't shown dialog yet
        // Only show dialog when we FIRST hit the exact limit
        if todayUsageMinutes == dailyLimitMinutes && !hasShownLimitDialog {
            snapshotUsageMinutes = todayUsageMinutes
            showLimitReachedDialog = true
            hasShownLimitDialog = true
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            
            dlog("⏰ AppUsageTracker: Daily limit of \(dailyLimitMinutes) minutes reached! Showing dialog.")
        }
    }
    
    private func loadUsageData() {
        // Load daily limit
        if UserDefaults.standard.object(forKey: limitKey) != nil {
            dailyLimitMinutes = UserDefaults.standard.integer(forKey: limitKey)
        }
        
        // Load last save date
        if let lastDate = UserDefaults.standard.object(forKey: lastSaveDateKey) as? Date {
            lastSaveDate = lastDate
            
            // Check if it's a new day
            if !Calendar.current.isDateInToday(lastDate) {
                resetDailyUsage()
                return
            }
        }
        
        // Load today's usage
        todayUsageMinutes = UserDefaults.standard.integer(forKey: usageKey)

        // Load week history
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([UsageDayEntry].self, from: data) {
            archivedHistory = history
        }
        
        dlog("📊 AppUsageTracker: Loaded usage data - \(todayUsageMinutes) minutes used, \(dailyLimitMinutes) limit")
    }
    
    private func saveUsageData() {
        // Capture values before leaving MainActor
        let minutesSnapshot = todayUsageMinutes
        let now = Date()
        lastSaveDate = now
        // Write to UserDefaults on a background queue — synchronous I/O must not block the main thread
        Task.detached(priority: .utility) {
            UserDefaults.standard.set(minutesSnapshot, forKey: self.usageKey)
            UserDefaults.standard.set(now, forKey: self.lastSaveDateKey)
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Daily Limit Dialog View

struct DailyLimitReachedDialog: View {
    @EnvironmentObject var tracker: AppUsageTracker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var orbLeft = false
    @State private var orbRight = false
    @State private var cardAppeared = false
    @State private var statsAppeared = false
    @State private var verseIndex = 0
    @State private var breakPressed = false
    @State private var continuePressed = false

    private let verses: [(quote: String, ref: String)] = [
        ("Be still, and know that I am God", "Psalm 46:10"),
        ("He gives strength to the weary and increases the power of the weak", "Isaiah 40:29"),
        ("Come to me, all who are weary and burdened, and I will give you rest", "Matthew 11:28"),
        ("He makes me lie down in green pastures; He leads me beside quiet waters", "Psalm 23:2"),
    ]

    private var usageRatio: Double {
        guard tracker.dailyLimitMinutes > 0 else { return 0 }
        return min(1.0, Double(tracker.snapshotUsageMinutes) / Double(tracker.dailyLimitMinutes))
    }

    private var arcColor: Color {
        usageRatio >= 1.0 ? Color.amenPurple : (usageRatio >= 0.75 ? Color.amenGold : Color.amenBlue)
    }

    var body: some View {
        ZStack {
            Color(red: 0.949, green: 0.949, blue: 0.969)
                .ignoresSafeArea()

            atmosphericOrbs

            VStack(spacing: 0) {
                Spacer()
                cardContent
                    .padding(.horizontal, 20)
                    .scaleEffect(cardAppeared ? 1 : 0.93)
                    .opacity(cardAppeared ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.82),
                        value: cardAppeared
                    )
                Spacer()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            orbLeft = true
            orbRight = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.82)) {
                cardAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.84)) {
                    statsAppeared = true
                }
            }
            verseIndex = Calendar.current.component(.minute, from: Date()) % verses.count
        }
    }

    // MARK: Card

    private var cardContent: some View {
        VStack(spacing: 26) {
            iconWithArc
                .opacity(cardAppeared ? 1 : 0)
                .offset(y: cardAppeared ? 0 : 8)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.84).delay(0.06),
                    value: cardAppeared
                )

            titleBlock
                .opacity(cardAppeared ? 1 : 0)
                .offset(y: cardAppeared ? 0 : 8)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.84).delay(0.10),
                    value: cardAppeared
                )

            statsPill
                .opacity(statsAppeared ? 1 : 0)
                .scaleEffect(statsAppeared ? 1 : 0.94)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.84),
                    value: statsAppeared
                )

            verseQuote
                .opacity(statsAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.05), value: statsAppeared)

            actionButtons
                .opacity(statsAppeared ? 1 : 0)
                .offset(y: statsAppeared ? 0 : 6)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.84).delay(0.08),
                    value: statsAppeared
                )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
        .background {
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            if reduceTransparency {
                shape.fill(Color.white)
                    .overlay(shape.strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
            } else {
                shape.fill(.thinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.14)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.48), lineWidth: 0.8))
                    .overlay(
                        shape.stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.02), Color.black.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                    )
            }
        }
        .saturation(reduceTransparency ? 1 : 1.08)
        .shadow(color: .black.opacity(0.10), radius: 40, y: 16)
    }

    // MARK: Icon with Progress Arc

    private var iconWithArc: some View {
        ZStack {
            // Soft glow behind arc
            Circle()
                .fill(arcColor.opacity(0.12))
                .frame(width: 112, height: 112)
                .blur(radius: 18)
                .allowsHitTesting(false)

            // Track ring
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 4)
                .frame(width: 92, height: 92)

            // Progress arc — animates from 0 when stats appear
            Circle()
                .trim(from: 0, to: statsAppeared ? usageRatio : 0)
                .stroke(arcColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 92, height: 92)
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.72, dampingFraction: 0.82),
                    value: statsAppeared
                )

            // Glass icon circle
            ZStack {
                if reduceTransparency {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                } else {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().fill(Color.white.opacity(0.18)))
                }

                Circle()
                    .strokeBorder(Color.white.opacity(0.52), lineWidth: 0.8)
                    .frame(width: 72, height: 72)

                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.systemScaled(30, weight: .light))
                    .foregroundStyle(arcColor)
            }
            .shadow(color: arcColor.opacity(0.20), radius: 14, y: 6)
        }
    }

    // MARK: Title Block

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text("Time for a Break")
                .font(.systemScaled(30, weight: .light, design: .serif))
                .foregroundStyle(.primary)
                .tracking(0.3)
                .accessibilityAddTraits(.isHeader)

            Text("You've spent **\(tracker.snapshotUsageMinutes) minutes** in the app today. We encourage a break to pray, reflect, or be with loved ones.")
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Stats Pill

    private var statsPill: some View {
        HStack(spacing: 0) {
            statCell(value: "\(tracker.snapshotUsageMinutes)", label: "Minutes Used", accent: arcColor)

            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1, height: 36)

            statCell(value: "\(tracker.dailyLimitMinutes)", label: "Daily Limit", accent: Color.amenGold)
        }
        .padding(.vertical, 18)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if reduceTransparency {
                shape.fill(Color(.secondarySystemBackground))
                    .overlay(shape.strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.12)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.40), lineWidth: 0.8))
            }
        }
    }

    private func statCell(value: String, label: String, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.systemScaled(28, weight: .thin, design: .rounded))
                .foregroundStyle(accent)
            Text(label)
                .font(.systemScaled(10, weight: .regular))
                .foregroundStyle(.black.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) minutes")
    }

    // MARK: Verse Quote

    private var verseQuote: some View {
        let verse = verses[verseIndex]
        return VStack(spacing: 5) {
            Text("\"\(verse.quote)\"")
                .font(.systemScaled(13, weight: .light, design: .serif))
                .foregroundStyle(.black.opacity(0.72))
                .italic()
                .multilineTextAlignment(.center)
            Text(verse.ref)
                .font(.systemScaled(10, weight: .regular))
                .foregroundStyle(.black.opacity(0.38))
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .padding(.horizontal, 8)
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Primary — gradient amenBlack→amenPurple pill
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    tracker.showLimitReachedDialog = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if UIApplication.shared.connectedScenes.first is UIWindowScene {
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    }
                }
            } label: {
                Text("Take a Break")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.06, green: 0.06, blue: 0.07), Color.amenPurple.opacity(0.90)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.amenPurple.opacity(0.25), radius: 12, y: 5)
                    )
                    .scaleEffect(breakPressed ? 0.97 : 1.0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82),
                        value: breakPressed
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in breakPressed = true }
                    .onEnded { _ in breakPressed = false }
            )
            .accessibilityLabel("Take a Break")

            // Secondary — ghost glass pill
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    tracker.showLimitReachedDialog = false
                }
            } label: {
                Text("Continue Anyway")
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.black.opacity(0.52))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                        if reduceTransparency {
                            shape.fill(Color(.secondarySystemBackground))
                                .overlay(shape.strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
                        } else {
                            shape.fill(.ultraThinMaterial)
                                .overlay(shape.fill(Color.white.opacity(0.10)))
                                .overlay(shape.strokeBorder(Color.white.opacity(0.38), lineWidth: 0.8))
                        }
                    }
                    .scaleEffect(continuePressed ? 0.97 : 1.0)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82),
                        value: continuePressed
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in continuePressed = true }
                    .onEnded { _ in continuePressed = false }
            )
            .accessibilityLabel("Continue Anyway")
        }
    }

    // MARK: Atmospheric Orbs

    @ViewBuilder
    private var atmosphericOrbs: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.amenPurple.opacity(0.22), Color.amenPurple.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -80, y: 100)
                .blur(radius: 70)
                .scaleEffect(orbLeft ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: orbLeft)
                .allowsHitTesting(false)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.amenGold.opacity(0.18), Color.amenGold.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 80, y: 80)
                .blur(radius: 65)
                .scaleEffect(orbRight ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 11).repeatForever(autoreverses: true), value: orbRight)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
