//
//  AdaptiveQuietHoursEngine.swift
//  AMENAPP
//
//  Adaptive quiet hours that learn from user behavior
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import UserNotifications
import CoreLocation
import EventKit

/// Learns user behavior patterns and automatically suggests/adjusts quiet hours
@MainActor
class AdaptiveQuietHoursEngine: ObservableObject {
    static let shared = AdaptiveQuietHoursEngine()

    private lazy var db = Firestore.firestore()
    private let calendar = Calendar.current

    @Published var learnedPattern: QuietHoursPattern?
    @Published var suggestions: [QuietHoursSuggestion] = []
    @Published var isLearning: Bool = true

    // MARK: - Behavior Learning

    /// Tracks user activity patterns to determine natural quiet hours
    struct ActivityPattern: Codable {
        var hourlyActivity: [Int: Double] = [:]  // Hour (0-23) → Activity Score (0-1)
        var dayOfWeekActivity: [Int: Double] = [:] // DayOfWeek (1-7) → Activity Score
        var lastActiveTime: Date?
        var lastInactiveTime: Date?
        var typicalSleepStart: TimeComponents?
        var typicalSleepEnd: TimeComponents?
        var confidenceScore: Double = 0.0  // 0-1, how confident we are in the pattern
        var sampleCount: Int = 0

        struct TimeComponents: Codable {
            var hour: Int
            var minute: Int

            var timeString: String {
                String(format: "%02d:%02d", hour, minute)
            }
        }
    }

    /// Suggested quiet hours based on learned behavior
    struct QuietHoursSuggestion: Identifiable {
        let id = UUID()
        let startTime: String  // "22:00"
        let endTime: String    // "08:00"
        let confidence: Double // 0-1
        let reason: SuggestionReason
        let dataPoints: Int

        enum SuggestionReason {
            case sleepPattern
            case inactivityPattern
            case focusModeSync
            case calendarEvents
            case locationPattern
        }
    }

    struct QuietHoursPattern: Codable {
        var weekdayStart: String    // "22:30"
        var weekdayEnd: String      // "07:00"
        var weekendStart: String    // "23:00"
        var weekendEnd: String      // "08:30"
        var confidence: Double
        var lastUpdated: Date
    }

    // MARK: - Core Learning Functions

    /// Record user activity timestamp to build behavior pattern
    func recordActivity(type: UserActivityType, timestamp: Date = Date()) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let hour = calendar.component(.hour, from: timestamp)
        let dayOfWeek = calendar.component(.weekday, from: timestamp)

        // Log to Firestore for ML training
        let activityData: [String: Any] = [
            "userId": userId,
            "type": type.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "hour": hour,
            "dayOfWeek": dayOfWeek,
            "isWeekend": [1, 7].contains(dayOfWeek)
        ]

        do {
            try await db.collection("userActivityLogs")
                .document(userId)
                .collection("activities")
                .addDocument(data: activityData)

            // Update hourly activity pattern
            await updateActivityPattern(hour: hour, dayOfWeek: dayOfWeek, isActive: true)

        } catch {
            dlog("❌ Failed to record activity: \(error.localizedDescription)")
        }
    }

    /// Record when user goes inactive (app backgrounded, screen locked)
    func recordInactivity(timestamp: Date = Date()) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let hour = calendar.component(.hour, from: timestamp)
        let dayOfWeek = calendar.component(.weekday, from: timestamp)

        let inactivityData: [String: Any] = [
            "userId": userId,
            "type": "inactive",
            "timestamp": Timestamp(date: timestamp),
            "hour": hour,
            "dayOfWeek": dayOfWeek
        ]

        do {
            try await db.collection("userActivityLogs")
                .document(userId)
                .collection("inactivity")
                .addDocument(data: inactivityData)

            await updateActivityPattern(hour: hour, dayOfWeek: dayOfWeek, isActive: false)

        } catch {
            dlog("❌ Failed to record inactivity: \(error.localizedDescription)")
        }
    }

    private func updateActivityPattern(hour: Int, dayOfWeek: Int, isActive: Bool) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let docRef = db.collection("users").document(userId)
            .collection("learningData").document("activityPattern")

        do {
            let doc = try await docRef.getDocument()
            var pattern: ActivityPattern

            if let data = doc.data(),
               let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let decoded = try? JSONDecoder().decode(ActivityPattern.self, from: jsonData) {
                pattern = decoded
            } else {
                pattern = ActivityPattern()
            }

            // Update hourly activity with exponential moving average
            let alpha = 0.1  // Learning rate
            let currentScore = pattern.hourlyActivity[hour] ?? 0.5
            let newScore = isActive ? 1.0 : 0.0
            pattern.hourlyActivity[hour] = currentScore * (1 - alpha) + newScore * alpha

            // Update day of week activity
            let dayScore = pattern.dayOfWeekActivity[dayOfWeek] ?? 0.5
            pattern.dayOfWeekActivity[dayOfWeek] = dayScore * (1 - alpha) + newScore * alpha

            pattern.sampleCount += 1

            // Calculate confidence (more samples = higher confidence)
            pattern.confidenceScore = min(1.0, Double(pattern.sampleCount) / 1000.0)

            // Derive sleep patterns
            await deriveSleepPatterns(from: &pattern)

            // Save back
            if let encoded = try? JSONEncoder().encode(pattern),
               let dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
                try await docRef.setData(dict)
            }

            // Generate suggestions if confidence is high enough
            if pattern.confidenceScore > 0.3 {
                await generateSuggestions(from: pattern)
            }

        } catch {
            dlog("❌ Failed to update activity pattern: \(error.localizedDescription)")
        }
    }

    private func deriveSleepPatterns(from pattern: inout ActivityPattern) async {
        // Find the longest consecutive period of low activity
        // This is likely sleep time

        var inactivePeriods: [(start: Int, end: Int, score: Double)] = []
        var currentStart: Int?
        var consecutiveInactive = 0

        // Scan 24 hours looking for low activity
        for hour in 0..<24 {
            let activityScore = pattern.hourlyActivity[hour] ?? 0.5

            if activityScore < 0.3 {  // Low activity threshold
                if currentStart == nil {
                    currentStart = hour
                }
                consecutiveInactive += 1
            } else {
                if let start = currentStart, consecutiveInactive >= 4 {
                    // Found a period of at least 4 hours
                    let avgScore = (start..<hour).map { pattern.hourlyActivity[$0] ?? 0.5 }.reduce(0, +) / Double(consecutiveInactive)
                    inactivePeriods.append((start, hour - 1, avgScore))
                }
                currentStart = nil
                consecutiveInactive = 0
            }
        }

        // Handle wrap-around (e.g., 22:00 → 06:00)
        if let start = currentStart, consecutiveInactive >= 4 {
            inactivePeriods.append((start, 23, 0.0))
        }

        // Find the longest low-activity period
        if let longestPeriod = inactivePeriods.max(by: { $0.end - $0.start < $1.end - $1.start }) {
            pattern.typicalSleepStart = ActivityPattern.TimeComponents(hour: longestPeriod.start, minute: 0)
            pattern.typicalSleepEnd = ActivityPattern.TimeComponents(hour: (longestPeriod.end + 1) % 24, minute: 0)
        }
    }

    private func generateSuggestions(from pattern: ActivityPattern) async {
        var newSuggestions: [QuietHoursSuggestion] = []

        // 1. Sleep pattern suggestion
        if let sleepStart = pattern.typicalSleepStart,
           let sleepEnd = pattern.typicalSleepEnd,
           pattern.confidenceScore > 0.3 {
            newSuggestions.append(QuietHoursSuggestion(
                startTime: sleepStart.timeString,
                endTime: sleepEnd.timeString,
                confidence: pattern.confidenceScore,
                reason: .sleepPattern,
                dataPoints: pattern.sampleCount
            ))
        }

        // 2. Focus mode suggestion (if integrated)
        if let focusSuggestion = await getFocusModeSuggestion() {
            newSuggestions.append(focusSuggestion)
        }

        // 3. Calendar-based suggestion
        if let calendarSuggestion = await getCalendarSuggestion() {
            newSuggestions.append(calendarSuggestion)
        }

        await MainActor.run {
            self.suggestions = newSuggestions
        }
    }

    // MARK: - iOS Focus Mode Integration

    private func getFocusModeSuggestion() async -> QuietHoursSuggestion? {
        // Note: This requires Focus Mode API which is limited
        // For now, we'll check Do Not Disturb schedule via UserDefaults if available
        // In production, you'd integrate with Focus API or prompt user to share their Focus schedule

        // Placeholder for Focus Mode integration
        // You would check current Focus status and learn from it

        return nil  // Implement when Focus API is available
    }

    /// Sync quiet hours with iOS Focus Modes
    func syncWithFocusMode() async {
        // Check if user has Do Not Disturb scheduled
        // If so, suggest matching quiet hours

        // This would require:
        // 1. Requesting permission to access Focus status
        // 2. Observing Focus mode changes
        // 3. Learning from when user enables Focus manually

        dlog("📱 Focus Mode sync requested (iOS API integration pending)")
    }

    // MARK: - Calendar Integration

    private func getCalendarSuggestion() async -> QuietHoursSuggestion? {
        let eventStore = EKEventStore()

        // Request calendar access
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { return nil }

            // Look for recurring "Sleep" or "Do Not Disturb" calendar events
            let calendars = eventStore.calendars(for: .event)

            let now = Date()
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            let predicate = eventStore.predicateForEvents(withStart: weekAgo, end: now, calendars: calendars)
            let events = eventStore.events(matching: predicate)

            // Find sleep-related events
            let sleepEvents = events.filter {
                $0.title.lowercased().contains("sleep") ||
                $0.title.lowercased().contains("bed") ||
                $0.title.lowercased().contains("do not disturb")
            }

            if let firstSleepEvent = sleepEvents.first {
                let startHour = calendar.component(.hour, from: firstSleepEvent.startDate)
                let endHour = calendar.component(.hour, from: firstSleepEvent.endDate)

                return QuietHoursSuggestion(
                    startTime: String(format: "%02d:00", startHour),
                    endTime: String(format: "%02d:00", endHour),
                    confidence: 0.7,
                    reason: .calendarEvents,
                    dataPoints: sleepEvents.count
                )
            }

        } catch {
            dlog("❌ Calendar access denied: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Location Context

    /// Detect if user is at a known location (home, church) and adjust quiet hours
    func detectLocationContext(location: CLLocation) async -> LocationContext? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }

        do {
            // Fetch user's saved locations
            let doc = try await db.collection("users").document(userId)
                .collection("settings").document("locations").getDocument()

            guard let data = doc.data() else { return nil }

            // Check if near home
            if let homeData = data["home"] as? [String: Any],
               let homeLat = homeData["latitude"] as? Double,
               let homeLon = homeData["longitude"] as? Double {
                let homeLocation = CLLocation(latitude: homeLat, longitude: homeLon)
                let distance = location.distance(from: homeLocation)

                if distance < 200 {  // Within 200 meters
                    return LocationContext(
                        type: .home,
                        shouldEnableQuietHours: true,
                        suggestedStart: "22:00",
                        suggestedEnd: "07:00"
                    )
                }
            }

            // Check if near church
            if let churchData = data["church"] as? [String: Any],
               let churchLat = churchData["latitude"] as? Double,
               let churchLon = churchData["longitude"] as? Double {
                let churchLocation = CLLocation(latitude: churchLat, longitude: churchLon)
                let distance = location.distance(from: churchLocation)

                if distance < 500 {  // Within 500 meters
                    return LocationContext(
                        type: .church,
                        shouldEnableQuietHours: true,
                        suggestedStart: nil,  // Immediate
                        suggestedEnd: nil     // Until user leaves
                    )
                }
            }

        } catch {
            dlog("❌ Failed to fetch location context: \(error.localizedDescription)")
        }

        return nil
    }

    struct LocationContext {
        enum LocationType {
            case home
            case church
            case work
            case unknown
        }

        let type: LocationType
        let shouldEnableQuietHours: Bool
        let suggestedStart: String?
        let suggestedEnd: String?
    }

    // MARK: - Load Learned Pattern

    func loadLearnedPattern() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("learningData").document("quietHoursPattern").getDocument()

            if let data = doc.data(),
               let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let pattern = try? JSONDecoder().decode(QuietHoursPattern.self, from: jsonData) {
                await MainActor.run {
                    self.learnedPattern = pattern
                }
            }

        } catch {
            dlog("❌ Failed to load learned pattern: \(error.localizedDescription)")
        }
    }

    /// Apply suggested quiet hours automatically (with user permission)
    func applySuggestion(_ suggestion: QuietHoursSuggestion, autoApply: Bool = false) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Update user's quiet hours settings
        let quietHours: [String: Any] = [
            "enabled": true,
            "startTime": suggestion.startTime,
            "endTime": suggestion.endTime,
            "source": "adaptive_\(suggestion.reason)",
            "confidence": suggestion.confidence,
            "autoApplied": autoApply,
            "appliedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("settings").document("notifications")
                .updateData(["quietHours": quietHours])

            dlog("✅ Applied adaptive quiet hours: \(suggestion.startTime) - \(suggestion.endTime)")

            // Remove from suggestions
            await MainActor.run {
                self.suggestions.removeAll { $0.id == suggestion.id }
            }

        } catch {
            dlog("❌ Failed to apply suggestion: \(error.localizedDescription)")
        }
    }
}

// MARK: - Activity Types

enum UserActivityType: String, Codable {
    case appOpened
    case postCreated
    case messagesSent
    case feedScrolled
    case notificationInteracted
    case bereanUsed
    case prayerAdded
    case churchNotesEdited
}
