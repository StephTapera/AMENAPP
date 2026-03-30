//
//  WellnessGuardianService.swift
//  AMENAPP
//
//  Screen time intelligence & mental health breaks
//  Promotes healthy engagement patterns
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class WellnessGuardianService: ObservableObject {
    static let shared = WellnessGuardianService()
    
    @Published var isEnabled = true
    @Published var sessionStartTime: Date?
    @Published var totalScrollCount = 0
    @Published var shouldShowBreakReminder = false
    @Published var breakReminderMessage = ""
    @Published var dailyUsageMinutes = 0
    @Published var weeklyUsageMinutes = 0
    
    private let db = Firestore.firestore()
    private var breakCheckTimer: Timer?

    // Tracks when the last reminder was dismissed so we don't re-fire immediately
    private var lastReminderDismissedAt: Date? = nil
    // Minimum time between any two wellness prompts (30 minutes)
    private let reminderCooldown: TimeInterval = 1800

    // Configurable thresholds
    private var scrollThreshold = 150  // Posts scrolled before suggesting break (raised from 50)
    private var timeThreshold: TimeInterval = 2700  // 45 minutes in seconds (raised from 20)
    private var bedtimeHourStart = 22  // 10 PM
    private var bedtimeHourEnd = 6     // 6 AM
    // Bedtime reminder only fires after user has been active for this long (minutes)
    private let bedtimeMinActiveMinutes: TimeInterval = 600  // 10 minutes
    
    struct UsageSession {
        let startTime: Date
        let endTime: Date
        let duration: TimeInterval
        let scrollCount: Int
        let breaksTaken: Int
    }
    
    struct WellnessStats {
        var todayMinutes: Int
        var weekMinutes: Int
        var longestStreak: Int // days of healthy usage
        var breaksTaken: Int
        var averageDailyMinutes: Int
    }
    
    private init() {
        // PERF: Don't call loadTodaysUsage() here — auth is not yet resolved
        // at init time. Usage is loaded lazily on first trackSessionStart() call.
    }

    // MARK: - Session Tracking

    func trackSessionStart() {
        sessionStartTime = Date()
        totalScrollCount = 0

        // Lazy-load today's usage on first session start (auth is guaranteed by this point)
        if dailyUsageMinutes == 0 { loadTodaysUsage() }

        // Do NOT show bedtime immediately on session start.
        // Bedtime is checked in checkIfBreakNeeded() after the user
        // has been actively using the app for bedtimeMinActiveMinutes.

        dlog("💚 Wellness Guardian: Session started")
    }
    
    func trackSessionEnd() {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)
        saveSessionToFirestore(duration: duration, scrollCount: totalScrollCount)

        sessionStartTime = nil
        totalScrollCount = 0

        // PERF: Stop the break-check timer when session ends to prevent it
        // firing while the app is backgrounded and causing spurious @Published updates.
        breakCheckTimer?.invalidate()
        breakCheckTimer = nil

        dlog("💚 Wellness Guardian: Session ended (\(Int(duration/60)) minutes)")
    }
    
    func trackScroll() {
        totalScrollCount += 1
        
        // Check if break is needed
        checkIfBreakNeeded()
    }
    
    // MARK: - Smart Breaks
    
    func enableSmartBreaks(scrollThreshold: Int = 50, timeThreshold: Int = 20) {
        self.scrollThreshold = scrollThreshold
        self.timeThreshold = TimeInterval(timeThreshold * 60)
        
        // Start periodic check
        breakCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIfBreakNeeded()
            }
        }
        
        dlog("💚 Wellness Guardian: Smart breaks enabled (scroll: \(scrollThreshold), time: \(timeThreshold)min)")
    }
    
    private func checkIfBreakNeeded() {
        guard isEnabled, let startTime = sessionStartTime else { return }

        // Enforce cooldown: don't re-fire within 30 minutes of the last dismissal
        if let lastDismissed = lastReminderDismissedAt,
           Date().timeIntervalSince(lastDismissed) < reminderCooldown {
            return
        }

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Check bedtime — only after user has been active for at least bedtimeMinActiveMinutes
        if isBedtime() && elapsedTime >= bedtimeMinActiveMinutes {
            showBreakReminder(type: .bedtime)
            return
        }

        // Check scroll threshold
        if totalScrollCount >= scrollThreshold {
            showBreakReminder(type: .scrollOverload)
            return
        }

        // Check time threshold
        if elapsedTime >= timeThreshold {
            showBreakReminder(type: .timeLimit)
            return
        }
    }
    
    enum BreakReminderType {
        case scrollOverload
        case timeLimit
        case bedtime
    }
    
    private func showBreakReminder(type: BreakReminderType) {
        guard !shouldShowBreakReminder else { return } // Don't spam
        
        switch type {
        case .scrollOverload:
            breakReminderMessage = "You've scrolled through \(totalScrollCount) posts. Take a breath? 🙏"
        case .timeLimit:
            let minutes = sessionStartTime.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
            breakReminderMessage = "You've been here for \(minutes) minutes. Time for a break? 🌟"
        case .bedtime:
            breakReminderMessage = "It's getting late. Rest well and see you tomorrow! 🌙"
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            shouldShowBreakReminder = true
        }
        
        // Auto-dismiss after 10 seconds.
        // PERF: Use Task instead of DispatchQueue.main.asyncAfter — consistent with
        // @MainActor and avoids a retain cycle through the dispatch closure capture.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.dismissBreakReminder()
        }
        
        dlog("💚 Wellness Guardian: Break reminder shown (\(type))")
    }
    
    func dismissBreakReminder() {
        lastReminderDismissedAt = Date()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            shouldShowBreakReminder = false
        }
    }
    
    func takeBreak() {
        // Reset counters and session timer so the next reminder is a full cycle away
        totalScrollCount = 0
        sessionStartTime = Date()
        dismissBreakReminder()  // also sets lastReminderDismissedAt
        
        // Log break taken
        Task {
            try? await logBreakTaken()
        }
        
        dlog("💚 Wellness Guardian: Break taken, counters reset")
    }
    
    // MARK: - Bedtime Mode
    
    private func isBedtime() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= bedtimeHourStart || hour < bedtimeHourEnd
    }
    
    private func showBedtimeReminder() {
        showBreakReminder(type: .bedtime)
    }
    
    // MARK: - Usage Stats
    
    private func loadTodaysUsage() {
        Task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return }
            
            do {
                let snapshot = try await db.collection("users").document(userId)
                    .collection("usageSessions")
                    .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: today))
                    .whereField("startTime", isLessThan: Timestamp(date: tomorrow))
                    .getDocuments()
                
                var totalMinutes = 0
                for doc in snapshot.documents {
                    if let duration = doc.data()["duration"] as? TimeInterval {
                        totalMinutes += Int(duration / 60)
                    }
                }
                
                dailyUsageMinutes = totalMinutes
                dlog("💚 Wellness Guardian: Today's usage - \(totalMinutes) minutes")
                
            } catch {
                dlog("❌ Failed to load usage stats: \(error)")
            }
        }
    }
    
    func getWeeklyStats() async -> WellnessStats {
        guard let userId = Auth.auth().currentUser?.uid else {
            return WellnessStats(todayMinutes: 0, weekMinutes: 0, longestStreak: 0, breaksTaken: 0, averageDailyMinutes: 0)
        }
        
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(timeIntervalSinceNow: -604800)
        
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("usageSessions")
                .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: weekAgo))
                .getDocuments()
            
            var totalMinutes = 0
            var breaksTaken = 0
            
            for doc in snapshot.documents {
                if let duration = doc.data()["duration"] as? TimeInterval {
                    totalMinutes += Int(duration / 60)
                }
                if let breaks = doc.data()["breaksTaken"] as? Int {
                    breaksTaken += breaks
                }
            }
            
            let avgDaily = totalMinutes / 7
            
            return WellnessStats(
                todayMinutes: dailyUsageMinutes,
                weekMinutes: totalMinutes,
                longestStreak: 0, // TODO: Calculate from daily healthy usage
                breaksTaken: breaksTaken,
                averageDailyMinutes: avgDaily
            )
            
        } catch {
            dlog("❌ Failed to get weekly stats: \(error)")
            return WellnessStats(todayMinutes: 0, weekMinutes: 0, longestStreak: 0, breaksTaken: 0, averageDailyMinutes: 0)
        }
    }
    
    // MARK: - Firestore Logging
    
    private func saveSessionToFirestore(duration: TimeInterval, scrollCount: Int) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        // Capture startTime before the async task — sessionStartTime is set to nil
        // synchronously after this call returns, so the force-unwrap inside the task
        // would crash without this capture.
        guard let startTime = sessionStartTime else { return }
        
        Task {
            try? await db.collection("users").document(userId)
                .collection("usageSessions")
                .document().setData([
                    "startTime": Timestamp(date: startTime),                    "endTime": Timestamp(date: Date()),
                    "duration": duration,
                    "scrollCount": scrollCount,
                    "breaksTaken": 0
                ])
        }
    }
    
    private func logBreakTaken() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(userId)
            .collection("wellnessEvents")
            .document().setData([
                "type": "break_taken",
                "timestamp": FieldValue.serverTimestamp()
            ])
    }
}

// MARK: - Break Reminder View

struct WellnessBreakReminderView: View {
    @ObservedObject var wellness: WellnessGuardianService
    
    var body: some View {
        if wellness.shouldShowBreakReminder {
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.pink)
                
                Text(wellness.breakReminderMessage)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    Button("Keep Going") {
                        wellness.dismissBreakReminder()
                    }
                    .font(.custom("OpenSans-Medium", size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                    )
                    
                    Button("Take Break") {
                        wellness.takeBreak()
                    }
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.pink)
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
            .zIndex(999)
        }
    }
}
