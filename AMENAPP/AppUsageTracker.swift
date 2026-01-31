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
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.orange.opacity(0.3),
                                    Color.orange.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 12) {
                    Text("Time for a Break")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.primary)
                    
                    Text("You've spent **\(tracker.dailyLimitMinutes) minutes** in the app today. We encourage taking a break to pray, reflect, or spend time with loved ones.")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 32)
                
                // Stats
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("\(tracker.todayUsageMinutes)")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.orange)
                        Text("Minutes Used")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(spacing: 4) {
                        Text("\(tracker.dailyLimitMinutes)")
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.blue)
                        Text("Daily Limit")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 32)
                
                // Bible verse encouragement
                VStack(spacing: 8) {
                    Text("\"Be still, and know that I am God\"")
                        .font(.custom("OpenSans-Italic", size: 15))
                        .foregroundStyle(.primary)
                    Text("Psalm 46:10")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                
                // Buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tracker.showLimitReachedDialog = false
                        }
                    } label: {
                        Text("Take a Break")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                            )
                    }
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tracker.showLimitReachedDialog = false
                        }
                    } label: {
                        Text("Continue Anyway")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(Color.black.opacity(0.5))
        .ignoresSafeArea()
    }
}
