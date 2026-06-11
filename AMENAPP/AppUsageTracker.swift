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

/// Tracks app usage time and manages daily time limits
@MainActor
class AppUsageTracker: ObservableObject {
    static let shared = AppUsageTracker()
    
    @Published var todayUsageMinutes: Int = 0
    @Published var dailyLimitMinutes: Int = 45
    @Published var showLimitReachedDialog: Bool = false
    @Published var hasShownLimitDialog: Bool = false
    @Published var snoozeUntil: Date? = nil
    /// Frozen snapshot of todayUsageMinutes captured the moment the limit dialog fires.
    /// Used by DailyLimitReachedDialog so the displayed count doesn't tick live.
    @Published var snapshotUsageMinutes: Int = 0
    
    private var sessionStartTime: Date?
    private var currentSessionStartTime: Date?  // Track current continuous session
    private var timer: Timer?
    private var lastSaveDate: Date?
    /// Stored handle for the per-tick smart-break analysis task so it can be
    /// cancelled in deinit rather than leaking into the next timer cycle.
    private var smartBreakTask: Task<Void, Never>?
    
    private let usageKey = "app_usage_today"
    private let limitKey = "daily_time_limit"
    private let lastSaveDateKey = "last_save_date"
    
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
        todayUsageMinutes = 0
        hasShownLimitDialog = false
        saveUsageData()
        
        // Also reset smart break reminder counters
        smartBreakReminder.resetDailyCounters()
        
        dlog("🔄 AppUsageTracker: Daily usage reset")
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
            // Cancel any in-flight task from the previous tick before starting a new one.
            smartBreakTask?.cancel()
            smartBreakTask = Task { [weak self] in
                guard let self else { return }
                await self.smartBreakReminder.analyzeUsageAndRemind(
                    continuousMinutes: continuousMinutes,
                    totalMinutesToday: self.todayUsageMinutes,
                    dailyLimit: self.dailyLimitMinutes
                )
            }
        }
        
        // Show dialog when limit is reached (or re-reached after a snooze)
        if todayUsageMinutes >= dailyLimitMinutes && !hasShownLimitDialog {
            if let snoozeEnd = snoozeUntil, Date() < snoozeEnd { return }
            snapshotUsageMinutes = todayUsageMinutes
            showLimitReachedDialog = true
            hasShownLimitDialog = true
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            dlog("⏰ AppUsageTracker: Daily limit of \(dailyLimitMinutes) minutes reached! Showing dialog.")
        }
    }

    /// Hide the dialog and re-arm it after the given number of minutes.
    func snooze(minutes: Int) {
        snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        hasShownLimitDialog = false
        showLimitReachedDialog = false
        dlog("⏰ AppUsageTracker: Snoozed for \(minutes) min")
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
        smartBreakTask?.cancel()
    }
}

// MARK: - Daily Limit Dialog View

struct DailyLimitReachedDialog: View {
    @EnvironmentObject var tracker: AppUsageTracker
    @State private var orbPulse = false
    @State private var appear = false

    private var usageFraction: Double {
        guard tracker.dailyLimitMinutes > 0 else { return 0 }
        return min(1.5, Double(tracker.snapshotUsageMinutes) / Double(tracker.dailyLimitMinutes))
    }

    private var contextHeading: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 22 || h < 5 { return "Rest your spirit" }
        if h >= 18 { return "Evening wind-down" }
        if h >= 12 { return "Afternoon pause" }
        return "Time for a Break"
    }

    private var contextVerse: (text: String, ref: String) {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 22 || h < 5 { return ("He grants sleep to those he loves", "Psalm 127:2") }
        if h >= 18 { return ("Be still, and know that I am God", "Psalm 46:10") }
        if h >= 12 { return ("Come to me, all who are weary and burdened", "Matthew 11:28") }
        return ("This is the day the Lord has made; rejoice in it", "Psalm 118:24")
    }

    var body: some View {
        ZStack {
            // Warm amber background
            Color(red: 0.99, green: 0.97, blue: 0.93).ignoresSafeArea()

            ambientOrbs

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer(minLength: 56)

                    progressRing
                        .scaleEffect(appear ? 1.0 : 0.7)
                        .opacity(appear ? 1.0 : 0)

                    mainCard
                        .offset(y: appear ? 0 : 24)
                        .opacity(appear ? 1.0 : 0)

                    snoozeRow
                        .offset(y: appear ? 0 : 16)
                        .opacity(appear ? 1.0 : 0)

                    Button("Continue Anyway") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            tracker.showLimitReachedDialog = false
                        }
                    }
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(.vertical, 4)
                    .opacity(appear ? 1.0 : 0)

                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 20)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.05)) {
                appear = true
            }
            orbPulse = true
        }
    }

    // MARK: - Ambient orbs

    private var ambientOrbs: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.93, green: 0.78, blue: 0.30).opacity(0.28), Color.clear],
                        center: .center, startRadius: 0, endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 80, y: -60)
                .blur(radius: 60)
                .scaleEffect(orbPulse ? 1.07 : 1.0)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbPulse)
                .allowsHitTesting(false)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.80, blue: 0.60).opacity(0.22), Color.clear],
                        center: .center, startRadius: 0, endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -60, y: 80)
                .blur(radius: 70)
                .scaleEffect(orbPulse ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: orbPulse)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Progress ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 7)

            Circle()
                .trim(from: 0, to: min(1.0, usageFraction))
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.78, blue: 0.30),
                            Color(red: 0.97, green: 0.88, blue: 0.50)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: usageFraction)

            // Overage arc shown in warm amber when past limit
            if usageFraction > 1.0 {
                Circle()
                    .trim(from: 0, to: min(0.5, usageFraction - 1.0))
                    .stroke(
                        Color(red: 0.88, green: 0.44, blue: 0.22).opacity(0.55),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text("\(tracker.snapshotUsageMinutes)")
                    .font(.systemScaled(48, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(.primary)
                Text("min today")
                    .font(.systemScaled(11, weight: .regular))
                    .foregroundStyle(.black.opacity(0.40))
                    .textCase(.uppercase)
                    .tracking(1.0)
            }
        }
        .frame(width: 168, height: 168)
    }

    // MARK: - Main glass card

    private var mainCard: some View {
        VStack(spacing: 0) {
            // Heading
            VStack(spacing: 10) {
                Text(contextHeading)
                    .font(.systemScaled(28, weight: .light, design: .serif))
                    .foregroundStyle(.primary)
                    .tracking(0.2)

                Group {
                    if usageFraction <= 1.0 {
                        Text("You've reached your **\(tracker.dailyLimitMinutes)-min** daily goal — great time to step away.")
                    } else {
                        Text("You're **\(tracker.snapshotUsageMinutes - tracker.dailyLimitMinutes) min** over your \(tracker.dailyLimitMinutes)-min goal today.")
                    }
                }
                .font(.systemScaled(14, weight: .regular))
                .foregroundStyle(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 4)
            }
            .padding(.top, 26)
            .padding(.horizontal, 20)

            Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

            // Verse
            VStack(spacing: 6) {
                Text("\"\(contextVerse.text)\"")
                    .font(.systemScaled(13, weight: .light, design: .serif))
                    .foregroundStyle(.black.opacity(0.70))
                    .italic()
                    .multilineTextAlignment(.center)
                Text(contextVerse.ref)
                    .font(.systemScaled(10, weight: .regular))
                    .foregroundStyle(.black.opacity(0.35))
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .padding(.horizontal, 24)

            Divider()
                .overlay(Color.black.opacity(0.06))
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

            // Inline daily limit adjuster
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Limit")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.38))
                        .textCase(.uppercase)
                        .tracking(0.7)
                    Text("\(tracker.dailyLimitMinutes) min")
                        .font(.systemScaled(17, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        tracker.updateDailyLimit(max(15, tracker.dailyLimitMinutes - 15))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "minus")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.65))
                            .frame(width: 38, height: 36)
                    }
                    Rectangle()
                        .fill(Color.black.opacity(0.07))
                        .frame(width: 1, height: 18)
                    Button {
                        tracker.updateDailyLimit(min(240, tracker.dailyLimitMinutes + 15))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "plus")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.65))
                            .frame(width: 38, height: 36)
                    }
                }
                // Solid subtle fill — this sits inside the glass card, so it must NOT be
                // glass-on-glass (per the design system's no-nested-glass rule).
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Primary CTA
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tracker.showLimitReachedDialog = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if UIApplication.shared.connectedScenes.first is UIWindowScene {
                        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.systemScaled(14, weight: .medium))
                    Text("Take a Break")
                        .font(.systemScaled(16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        // Canonical Liquid Glass surface (shared GlassEffectStyle system) — replaces the
        // hand-rolled .ultraThinMaterial card so the surface reads as true liquid glass.
        .glassEffect(.prominent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 32, y: 12)
    }

    // MARK: - Snooze options

    private var snoozeRow: some View {
        VStack(spacing: 10) {
            Text("Snooze reminder")
                .font(.systemScaled(11, weight: .regular))
                .foregroundStyle(.black.opacity(0.35))
                .textCase(.uppercase)
                .tracking(0.9)

            HStack(spacing: 10) {
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button {
                        tracker.snooze(minutes: minutes)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(minutes == 60 ? "1 hour" : "\(minutes) min")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.75))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            // Snooze pills sit on the ambient background (not on glass),
                            // so they use the canonical liquid-glass capsule surface.
                            .glassEffect(.regular, in: Capsule())
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    }
                }
            }
        }
    }
}
