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
        print("📊 AppUsageTracker: Session started")
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
        
        print("📊 AppUsageTracker: Session ended. Duration: \(sessionMinutes) minutes. Total today: \(todayUsageMinutes) minutes")
    }
    
    /// Update daily time limit
    func updateDailyLimit(_ minutes: Int) {
        dailyLimitMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: limitKey)
        print("⏱️ AppUsageTracker: Daily limit updated to \(minutes) minutes")
    }
    
    /// Reset usage for a new day
    func resetDailyUsage() {
        todayUsageMinutes = 0
        hasShownLimitDialog = false
        saveUsageData()
        
        // Also reset smart break reminder counters
        smartBreakReminder.resetDailyCounters()
        
        print("🔄 AppUsageTracker: Daily usage reset")
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
            
            print("⏰ AppUsageTracker: Daily limit of \(dailyLimitMinutes) minutes reached! Showing dialog.")
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
        
        print("📊 AppUsageTracker: Loaded usage data - \(todayUsageMinutes) minutes used, \(dailyLimitMinutes) limit")
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

    // Atmospheric orb animations — mirror the app's onboarding/Berean aesthetic
    @State private var orbLeft = false
    @State private var orbRight = false

    var body: some View {
        ZStack {
            // MARK: Backdrop — matches app's near-white atmospheric background
            Color(red: 0.949, green: 0.949, blue: 0.969)
                .ignoresSafeArea()

            // Atmospheric blobs (same palette as BereanOnboardingView)
            ZStack {
                // Bottom-left — warm red/coral
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.25),
                                Color(red: 1.0, green: 0.45, blue: 0.30).opacity(0.10),
                                Color.clear
                            ],
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

                // Bottom-right — violet/purple
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.55, green: 0.35, blue: 1.0).opacity(0.20),
                                Color(red: 0.40, green: 0.25, blue: 0.90).opacity(0.08),
                                Color.clear
                            ],
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

            // MARK: Card content
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 26) {
                    // Icon — glass circle matching the app's icon treatment
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 88, height: 88)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)

                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.black.opacity(0.65))
                    }

                    // Title
                    Text("Time for a Break")
                        .font(.system(size: 30, weight: .light, design: .serif))
                        .foregroundStyle(.black)
                        .tracking(0.3)

                    // Message
                    Text("You've spent **\(tracker.snapshotUsageMinutes) minutes** in the app today. We encourage a break to pray, reflect, or be with loved ones.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.black.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 8)

                    // Stats row — ultraThinMaterial pill
                    HStack(spacing: 0) {
                        VStack(spacing: 3) {
                            Text("\(tracker.snapshotUsageMinutes)")
                                .font(.system(size: 26, weight: .thin, design: .rounded))
                                .foregroundStyle(.black)
                            Text("Minutes Used")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.black.opacity(0.45))
                                .textCase(.uppercase)
                                .tracking(0.6)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 1, height: 36)

                        VStack(spacing: 3) {
                            Text("\(tracker.dailyLimitMinutes)")
                                .font(.system(size: 26, weight: .thin, design: .rounded))
                                .foregroundStyle(.black)
                            Text("Daily Limit")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.black.opacity(0.45))
                                .textCase(.uppercase)
                                .tracking(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.5),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )

                    // Bible verse
                    VStack(spacing: 5) {
                        Text("\"Be still, and know that I am God\"")
                            .font(.system(size: 13, weight: .light, design: .serif))
                            .foregroundStyle(.black.opacity(0.75))
                            .italic()
                        Text("Psalm 46:10")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.black.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }

                    // Buttons
                    VStack(spacing: 10) {
                        // Primary — Take a Break
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
                            Text("Take a Break")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.black)
                                )
                        }

                        // Secondary — Continue Anyway (ghost/glass style)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                tracker.showLimitReachedDialog = false
                            }
                        } label: {
                            Text("Continue Anyway")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.black.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.7),
                                            Color.white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.08), radius: 40, y: 16)
                )
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            orbLeft = true
            orbRight = true
        }
    }
}
