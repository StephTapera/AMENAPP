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
    
    private var sessionStartTime: Date?
    private var timer: Timer?
    private var lastSaveDate: Date?
    
    private let usageKey = "app_usage_today"
    private let limitKey = "daily_time_limit"
    private let lastSaveDateKey = "last_save_date"
    
    private init() {
        loadUsageData()
        setupTimer()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking session when app becomes active
    func startSession() {
        sessionStartTime = Date()
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
        
        // Check if we've JUST reached the limit and haven't shown dialog yet
        // Only show dialog when we FIRST hit the exact limit
        if todayUsageMinutes == dailyLimitMinutes && !hasShownLimitDialog {
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
        UserDefaults.standard.set(todayUsageMinutes, forKey: usageKey)
        UserDefaults.standard.set(Date(), forKey: lastSaveDateKey)
        lastSaveDate = Date()
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Daily Limit Dialog View

struct DailyLimitReachedDialog: View {
    @EnvironmentObject var tracker: AppUsageTracker
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                // ✅ Liquid glass icon with neomorphic shadows
                ZStack {
                    Circle()
                        .fill(Color(red: 0.94, green: 0.94, blue: 0.95))
                        .frame(width: 100, height: 100)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 6, y: 6)
                        .shadow(color: .white.opacity(0.8), radius: 10, x: -6, y: -6)
                    
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.black.opacity(0.7))
                }
                
                // Title
                Text("Time for a Break")
                    .font(.system(size: 32, weight: .light, design: .serif))
                    .foregroundStyle(.black)
                    .tracking(0.5)
                
                // Message
                Text("You've spent **\(tracker.dailyLimitMinutes) minutes** in the app today. We encourage taking a break to pray, reflect, or spend time with loved ones.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)
                
                // ✅ Liquid glass stats card
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("\(tracker.todayUsageMinutes)")
                            .font(.system(size: 28, weight: .thin, design: .rounded))
                            .foregroundStyle(.black)
                        Text("Minutes Used")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 1, height: 40)
                    
                    VStack(spacing: 4) {
                        Text("\(tracker.dailyLimitMinutes)")
                            .font(.system(size: 28, weight: .thin, design: .rounded))
                            .foregroundStyle(.black)
                        Text("Daily Limit")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.black.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.94, green: 0.94, blue: 0.95))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 4, y: 4)
                        .shadow(color: .white.opacity(0.7), radius: 8, x: -4, y: -4)
                )
                .padding(.horizontal, 32)
                
                // Bible verse encouragement
                VStack(spacing: 6) {
                    Text("\"Be still, and know that I am God\"")
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(.black.opacity(0.8))
                        .italic()
                    Text("Psalm 46:10")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.black.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(1)
                }
                .padding(.horizontal, 32)
                
                // ✅ Liquid glass buttons
                VStack(spacing: 12) {
                    // Take a Break button - closes app
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tracker.showLimitReachedDialog = false
                        }
                        
                        // ✅ Close the app after brief delay for animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // Request scene suspension (graceful close that allows reopening)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
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
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.black)
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            )
                    }
                    
                    // Continue button - liquid glass style
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tracker.showLimitReachedDialog = false
                        }
                    } label: {
                        Text("Continue Anyway")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.black.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.94, green: 0.94, blue: 0.95))
                                    .shadow(color: .black.opacity(0.1), radius: 6, x: 3, y: 3)
                                    .shadow(color: .white.opacity(0.7), radius: 6, x: -3, y: -3)
                            )
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.96, blue: 0.97),
                                Color(red: 0.92, green: 0.92, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 40, y: 20)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(
            Color.black.opacity(0.4)
                .blur(radius: 10)
        )
        .ignoresSafeArea()
    }
}
