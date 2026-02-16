//
//  SmartBreakReminderService.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Smart break reminder system that uses AI/logic to determine when users need a break
//  ONLY sends "Time for a Break" notifications when user has been on app 30-45+ minutes
//  This is separate from daily inspiration verses (handled by BreakTimeNotificationManager)
//

import Foundation
import UserNotifications
import SwiftUI
import Combine

/// Smart service that monitors app usage and sends intelligent break reminders
/// ONLY sends "Time for a Break" when actual usage is excessive (30-45+ minutes)
/// Maximum 2 usage-based break reminders per day (no scheduled reminders from this service)
@MainActor
class SmartBreakReminderService: ObservableObject {
    static let shared = SmartBreakReminderService()
    
    @Published var lastUsageReminderTime: Date?
    @Published var usageRemindersToday: Int = 0
    
    private let center = UNUserNotificationCenter.current()
    private let maxUsageRemindersPerDay = 2  // Limit usage-based "Time for a Break" reminders
    
    // Usage thresholds (in minutes) - ONLY trigger "Time for a Break" at these levels
    private let continuousUsageThreshold = 30  // Alert after 30 min continuous use
    private let heavyUsageThreshold = 45       // Alert after 45 min total use in session
    
    private let lastReminderKey = "last_usage_reminder_date"
    private let reminderCountKey = "usage_reminders_count_today"
    private let lastCountResetKey = "last_reminder_count_reset"
    
    private init() {
        loadReminderData()
    }
    
    // MARK: - Smart Usage Monitoring
    
    /// Analyze usage patterns and determine if a break reminder is needed
    /// ONLY sends "Time for a Break" if user has been on 30-45+ minutes
    func analyzeUsageAndRemind(
        continuousMinutes: Int,
        totalMinutesToday: Int,
        dailyLimit: Int
    ) async {
        // CRITICAL: Only trigger if actual usage is high enough (30+ continuous OR 45+ total)
        guard continuousMinutes >= continuousUsageThreshold || totalMinutesToday >= heavyUsageThreshold else {
            return
        }
        
        // Check if we've already sent max reminders today
        guard usageRemindersToday < maxUsageRemindersPerDay else {
            print("📊 Smart break reminder limit reached (\(maxUsageRemindersPerDay)/day)")
            return
        }
        
        // Check if enough time has passed since last reminder (at least 2 hours)
        if let lastReminder = lastUsageReminderTime {
            let hoursSinceLastReminder = Date().timeIntervalSince(lastReminder) / 3600
            guard hoursSinceLastReminder >= 2.0 else {
                print("📊 Too soon since last usage reminder (only \(Int(hoursSinceLastReminder * 60)) min ago)")
                return
            }
        }
        
        // Calculate usage score (0-100)
        let usageScore = calculateUsageScore(
            continuousMinutes: continuousMinutes,
            totalMinutesToday: totalMinutesToday,
            dailyLimit: dailyLimit
        )
        
        // Trigger reminder if score is high enough (70+)
        if usageScore >= 70 {
            await sendSmartBreakReminder(
                score: usageScore,
                continuousMinutes: continuousMinutes,
                totalMinutes: totalMinutesToday
            )
        }
    }
    
    // MARK: - Usage Score Calculation (AI-style algorithm)
    
    /// Calculate a usage score (0-100) to determine if user needs a break
    private func calculateUsageScore(
        continuousMinutes: Int,
        totalMinutesToday: Int,
        dailyLimit: Int
    ) -> Int {
        var score: Double = 0
        
        // 1. Continuous usage factor (40 points max)
        // Exponential curve: gets serious after 20 minutes
        let continuousScore = min(40.0, pow(Double(continuousMinutes) / 20.0, 1.5) * 40.0)
        score += continuousScore
        
        // 2. Daily limit approach (30 points max)
        // Linear progression toward daily limit
        if dailyLimit > 0 {
            let limitProgress = Double(totalMinutesToday) / Double(dailyLimit)
            let limitScore = min(30.0, limitProgress * 30.0)
            score += limitScore
        }
        
        // 3. Time of day factor (15 points max)
        // Higher score during times when users should rest
        let timeScore = calculateTimeOfDayScore()
        score += timeScore
        
        // 4. Pattern bonus (15 points max)
        // Bonus if user has been using app at unusual times
        let patternScore = calculatePatternScore()
        score += patternScore
        
        return min(100, Int(score))
    }
    
    /// Calculate score based on time of day (encourage breaks late at night, etc.)
    private func calculateTimeOfDayScore() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Late night (10 PM - 2 AM): High priority for rest
        if hour >= 22 || hour < 2 {
            return 15.0
        }
        // Early morning (2 AM - 6 AM): Very high priority
        else if hour >= 2 && hour < 6 {
            return 12.0
        }
        // Meal times (12 PM - 1 PM, 6 PM - 7 PM): Moderate priority
        else if (hour >= 12 && hour < 13) || (hour >= 18 && hour < 19) {
            return 8.0
        }
        // Normal hours: Low priority
        else {
            return 3.0
        }
    }
    
    /// Calculate score based on usage patterns
    private func calculatePatternScore() -> Double {
        // If this is the second reminder today, it's more serious
        if usageRemindersToday == 1 {
            return 15.0
        }
        return 5.0
    }
    
    // MARK: - Send Smart Reminder
    
    /// Send an intelligent break reminder based on usage patterns
    private func sendSmartBreakReminder(
        score: Int,
        continuousMinutes: Int,
        totalMinutes: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "Time for a Break"
        content.sound = .default
        content.categoryIdentifier = "USAGE_BREAK"
        
        // Customize message based on severity
        if score >= 90 {
            content.body = "You've been using AMEN for \(continuousMinutes) minutes straight. Your mind and spirit need rest. Take a break to pray and recharge."
        } else if score >= 80 {
            content.body = "Take a moment to step away and spend time with God. You've been on for \(continuousMinutes) minutes."
        } else {
            content.body = "Consider taking a prayer break. Rest your eyes and refresh your spirit."
        }
        
        content.userInfo = [
            "type": "smart_usage_break",
            "usage_score": score,
            "continuous_minutes": continuousMinutes,
            "total_minutes": totalMinutes
        ]
        
        // Trigger immediately (no delay)
        let request = UNNotificationRequest(
            identifier: "usage_break_\(UUID().uuidString)",
            content: content,
            trigger: nil  // Immediate delivery
        )
        
        do {
            try await center.add(request)
            
            // Update tracking
            lastUsageReminderTime = Date()
            usageRemindersToday += 1
            saveReminderData()
            
            print("✅ Sent smart break reminder (score: \(score), continuous: \(continuousMinutes)m, reminders today: \(usageRemindersToday))")
        } catch {
            print("❌ Failed to send smart break reminder: \(error)")
        }
    }
    
    // MARK: - Notification Categories
    
    /// Setup notification categories for usage breaks
    func setupNotificationCategories() {
        let takeBreakAction = UNNotificationAction(
            identifier: "TAKE_BREAK_NOW",
            title: "Take a Break",
            options: .foreground
        )
        
        let continueAction = UNNotificationAction(
            identifier: "CONTINUE_USING",
            title: "Continue",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: "USAGE_BREAK",
            actions: [takeBreakAction, continueAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Usage Break Reminder",
            options: .customDismissAction
        )
        
        center.setNotificationCategories([category])
        print("✅ Smart break reminder categories configured")
    }
    
    // MARK: - Daily Reset
    
    /// Reset daily counters (call this when new day starts)
    func resetDailyCounters() {
        usageRemindersToday = 0
        saveReminderData()
        print("🔄 Smart break reminder counters reset for new day")
    }
    
    // MARK: - Persistence
    
    private func loadReminderData() {
        // Check if we need to reset for a new day
        if let lastReset = UserDefaults.standard.object(forKey: lastCountResetKey) as? Date {
            if !Calendar.current.isDateInToday(lastReset) {
                resetDailyCounters()
                return
            }
        }
        
        // Load existing data
        if let lastReminder = UserDefaults.standard.object(forKey: lastReminderKey) as? Date {
            lastUsageReminderTime = lastReminder
        }
        
        usageRemindersToday = UserDefaults.standard.integer(forKey: reminderCountKey)
        
        print("📊 Loaded smart reminder data: \(usageRemindersToday) reminders sent today")
    }
    
    private func saveReminderData() {
        if let lastReminder = lastUsageReminderTime {
            UserDefaults.standard.set(lastReminder, forKey: lastReminderKey)
        }
        UserDefaults.standard.set(usageRemindersToday, forKey: reminderCountKey)
        UserDefaults.standard.set(Date(), forKey: lastCountResetKey)
    }
    
    // MARK: - Public Utilities
    
    /// Check if user should receive a break reminder now
    func shouldSendBreakReminder(
        continuousMinutes: Int,
        totalMinutesToday: Int,
        dailyLimit: Int
    ) -> Bool {
        // Don't send if at limit
        guard usageRemindersToday < maxUsageRemindersPerDay else { return false }
        
        // Don't send if too soon since last one
        if let lastReminder = lastUsageReminderTime {
            let hoursSinceLastReminder = Date().timeIntervalSince(lastReminder) / 3600
            guard hoursSinceLastReminder >= 2.0 else { return false }
        }
        
        // Calculate score and check threshold
        let score = calculateUsageScore(
            continuousMinutes: continuousMinutes,
            totalMinutesToday: totalMinutesToday,
            dailyLimit: dailyLimit
        )
        
        return score >= 70
    }
    
    /// Get current reminder status summary
    func getReminderStatus() -> String {
        let remaining = maxUsageRemindersPerDay - usageRemindersToday
        return "Smart break reminders today: \(usageRemindersToday)/\(maxUsageRemindersPerDay) (\(remaining) remaining)"
    }
}
