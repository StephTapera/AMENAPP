//
//  SMART_QUIET_HOURS_EXAMPLES.swift
//  AMENAPP
//
//  Example usage patterns for smart notification features
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

// MARK: - Example 1: Basic Setup

func exampleBasicSetup() async {
    // Enable quiet hours with default times
    let quietHours: [String: Any] = [
        "enabled": true,
        "startTime": "22:00",
        "endTime": "07:00",
        "progressiveQuieting": true,
        "adaptiveLearning": true
    ]

    // Save to Firestore
    guard let userId = Auth.auth().currentUser?.uid else { return }
    try? await Firestore.firestore()
        .collection("users").document(userId)
        .collection("settings").document("notifications")
        .setData(["quietHours": quietHours], merge: true)

    print("✅ Basic quiet hours configured")
}

// MARK: - Example 2: Activity Tracking Integration

@MainActor
struct ExampleActivityTracking: View {
    var body: some View {
        VStack {
            Button("Create Post") {
                Task {
                    // Track post creation
                    await AdaptiveQuietHoursEngine.shared.recordActivity(
                        type: UserActivityType.postCreated
                    )

                    // Create post logic...
                }
            }

            Button("Send Message") {
                Task {
                    // Track messaging
                    await AdaptiveQuietHoursEngine.shared.recordActivity(
                        type: UserActivityType.messagesSent
                    )

                    // Send message logic...
                }
            }
        }
        .onAppear {
            // Track app open
            Task {
                await AdaptiveQuietHoursEngine.shared.recordActivity(
                    type: UserActivityType.appOpened
                )
            }
        }
        .onDisappear {
            // Track app close/background
            Task {
                await AdaptiveQuietHoursEngine.shared.recordInactivity()
            }
        }
    }
}

// MARK: - Example 3: ML Intent Detection

func exampleMLIntentDetection() async {
    let exampleMessages = [
        "Can you pray for my mom? She's in the hospital 🙏",
        "Hey! Just wanted to say hi",
        "URGENT: Need someone to talk to right now",
        "Check out this link: bit.ly/xyz123",
        "Great post! Amen 🙏✨"
    ]

    for message in exampleMessages {
        let intent = await MLNotificationClassifier.shared.detectIntent(
            content: message,
            category: .directMessages
        )

        print("""
        Message: "\(message)"
        Intent: \(intent.type)
        Priority Boost: +\(Int(intent.priorityBoost * 100))%
        Confidence: \(Int(intent.confidence * 100))%
        Keywords: \(intent.detectedKeywords.joined(separator: ", "))
        ---
        """)
    }

    // Example Output:
    // Message: "Can you pray for my mom? She's in the hospital 🙏"
    // Intent: prayerRequest
    // Priority Boost: +50%
    // Confidence: 82%
    // Keywords: question, prayer, personal
}

// MARK: - Example 4: Safety Assessment

func exampleSafetyAssessment() async {
    let testMessages = [
        "Hope you're having a blessed day!",
        "BUY NOW!!! CLICK HERE FOR FREE MONEY!!!",
        "You're so stupid, just shut up",
        "Check this out: https://bit.ly/spam123"
    ]

    for message in testMessages {
        let safety = await MLNotificationClassifier.shared.assessSafety(
            content: message,
            fromUserId: "test_user_123"
        )

        print("""
        Message: "\(message)"
        Safety Score: \(Int(safety.safetyScore * 100))%
        Should Block: \(safety.shouldBlock ? "❌ YES" : "✅ NO")
        Flags: \(safety.flags.map { "\($0)" }.joined(separator: ", "))
        ---
        """)
    }
}

// MARK: - Example 5: Progressive Quieting

func exampleProgressiveQuieting() {
    let quietStart = "22:00"
    let quietEnd = "07:00"

    // Simulate different times
    let testTimes = [
        ("20:00", "2 hours before quiet"),
        ("21:00", "1 hour before quiet"),
        ("21:30", "30 minutes before quiet"),
        ("21:50", "10 minutes before quiet"),
        ("22:30", "During quiet hours"),
        ("02:00", "During quiet hours (night)"),
        ("07:30", "After quiet hours")
    ]

    for (time, description) in testTimes {
        // This is a simplified example - in real usage, you'd parse the time properly
        let level = ProgressiveQuietingEngine.shared.calculateQuietLevel(
            quietHoursStart: quietStart,
            quietHoursEnd: quietEnd
        )

        print("""
        Time: \(time) (\(description))
        Quiet Level: \(level.displayName)
        Minimum Priority: \(level.minimumPriority)
        ---
        """)
    }

    // Example Output:
    // Time: 21:00 (1 hour before quiet)
    // Quiet Level: Minimal
    // Minimum Priority: 0.3
    // ---
    // Time: 21:30 (30 minutes before quiet)
    // Quiet Level: Moderate
    // Minimum Priority: 0.5
}

// MARK: - Example 6: Smart Batching

func exampleSmartBatching() async {
    let batcher = SmartNotificationBatcher.shared

    // Add multiple low-priority notifications to batch
    await batcher.addToBatch(
        category: .reactions,
        fromUserId: "user1",
        fromUsername: "Sarah",
        content: "liked your post",
        priority: 0.2
    )

    await batcher.addToBatch(
        category: .reactions,
        fromUserId: "user2",
        fromUsername: "Jordan",
        content: "reacted with 🙏",
        priority: 0.2
    )

    await batcher.addToBatch(
        category: .follows,
        fromUserId: "user3",
        fromUsername: "Michael",
        content: "started following you",
        priority: 0.25
    )

    await batcher.addToBatch(
        category: .replies,
        fromUserId: "user4",
        fromUsername: "Emily",
        content: "Amen! Great post",
        priority: 0.4
    )

    // Deliver as summary (e.g., at 9 AM daily digest time)
    guard let userId = Auth.auth().currentUser?.uid else { return }
    await batcher.deliverBatchSummary(forUserId: userId)

    // User receives single notification:
    // Title: "You have 4 new notifications"
    // Body: "2 reactions, 1 follow, Emily: Amen! Great post"
}

// MARK: - Example 7: Catch-Up Summary

func exampleCatchUpSummary() async {
    guard let userId = Auth.auth().currentUser?.uid else { return }

    // When user opens app after quiet hours (e.g., 7:30 AM after 22:00-07:00 quiet hours)
    let quietHoursEndTime = Calendar.current.date(
        bySettingHour: 7, minute: 0, second: 0, of: Date()
    ) ?? Date()

    if let summary = await SmartNotificationBatcher.shared.generateCatchUpSummary(
        forUserId: userId,
        since: quietHoursEndTime
    ) {
        print("""
        🌅 Good Morning! Here's what you missed:

        Total Notifications: \(summary.totalCount)
        Time Period: \(Int(summary.totalTime / 3600)) hours

        Highlights:
        """)

        for highlight in summary.highlights {
            switch highlight.type {
            case .highPriority:
                print("⭐️ \(highlight.fromUsername): \(highlight.content)")
            case .categorySummary:
                print("📊 \(highlight.fromUsername)")
            case .trending:
                print("🔥 \(highlight.fromUsername)")
            }
        }

        if let mostActive = summary.mostActiveUser {
            print("\n👤 Most Active: \(mostActive)")
        }
    }

    // Example Output:
    // 🌅 Good Morning! Here's what you missed:
    //
    // Total Notifications: 24
    // Time Period: 8 hours
    //
    // Highlights:
    // ⭐️ Jordan: Can you pray for my interview tomorrow?
    // ⭐️ Sarah: Thank you so much for your encouragement!
    // 📊 8 comments
    // 📊 12 reactions
    // 📊 2 mentions
    //
    // 👤 Most Active: Sarah Thompson
}

// MARK: - Example 8: Adaptive Suggestions

@MainActor
struct ExampleAdaptiveSuggestionsView: View {
    @ObservedObject private var engine = AdaptiveQuietHoursEngine.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("AI Quiet Hours Suggestions")
                .font(.headline)

            if engine.suggestions.isEmpty {
                Text("Learning your patterns... Check back in a few days!")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(suggestion.startTime) - \(suggestion.endTime)")
                                .font(.title3.bold())
                            Spacer()
                            Text("\(Int(suggestion.confidence * 100))%")
                                .foregroundStyle(.orange)
                        }

                        Text(reasonDescription(suggestion.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Apply") {
                                Task {
                                    await engine.applySuggestion(suggestion)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Not Now") {
                                // Dismiss
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .task {
            await engine.loadLearnedPattern()
        }
    }

    private func reasonDescription(_ reason: AdaptiveQuietHoursEngine.QuietHoursSuggestion.SuggestionReason) -> String {
        switch reason {
        case .sleepPattern:
            return "Based on your typical sleep schedule"
        case .inactivityPattern:
            return "You're usually inactive during these hours"
        case .focusModeSync:
            return "Matches your iOS Focus Mode schedule"
        case .calendarEvents:
            return "Based on recurring calendar events"
        case .locationPattern:
            return "Based on when you're typically at home"
        }
    }
}

// MARK: - Example 9: Full Notification Routing with All Features

func exampleFullNotificationRouting() async {
    // Incoming notification
    let notification = IncomingNotification(
        category: .directMessages,
        fromUserId: "user123",
        fromUsername: "Jordan Smith",
        toUserId: "currentUser",
        content: "Can you pray for me? Going through a tough time right now.",
        entityId: "msg_456",
        metadata: ["conversationId": "conv_789"]
    )

    // 1. ML Intent Detection
    let intent = await MLNotificationClassifier.shared.detectIntent(
        content: notification.content,
        category: notification.category
    )

    // 2. Safety Check
    let safety = await MLNotificationClassifier.shared.assessSafety(
        content: notification.content,
        fromUserId: notification.fromUserId
    )

    // Block unsafe content
    guard !safety.shouldBlock else {
        print("❌ Blocked: Safety score too low (\(safety.safetyScore))")
        return
    }

    // 3. Calculate base priority
    var priority = 0.6  // Base priority for DMs

    // 4. Apply ML intent boost
    priority += intent.priorityBoost

    print("Base Priority: 0.6")
    print("ML Intent Boost: +\(intent.priorityBoost)")
    print("Final Priority: \(priority)")

    // 5. Check progressive quieting level
    let quietLevel = ProgressiveQuietingEngine.shared.calculateQuietLevel(
        quietHoursStart: "22:00",
        quietHoursEnd: "07:00"
    )

    // 6. Make delivery decision
    let routing = NotificationRouting(
        category: notification.category,
        priority: NotificationPriorityScore(score: priority),
        timestamp: Date()
    )

    let decision = ProgressiveQuietingEngine.shared.shouldDeliver(
        notification: routing,
        currentLevel: quietLevel
    )

    // 7. Execute decision
    switch decision {
    case .deliver(let channel, let reason):
        print("✅ DELIVER via \(channel): \(reason)")
        // Send push notification

    case .batch(let reason):
        print("📦 BATCH: \(reason)")
        await SmartNotificationBatcher.shared.addToBatch(
            category: notification.category,
            fromUserId: notification.fromUserId,
            fromUsername: notification.fromUsername,
            content: notification.content,
            priority: priority
        )

    case .suppress(let reason):
        print("🔇 SUPPRESS: \(reason)")
        // Notification suppressed
    }
}

struct IncomingNotification {
    let category: NotificationCategory
    let fromUserId: String
    let fromUsername: String
    let toUserId: String
    let content: String
    let entityId: String
    let metadata: [String: Any]
}

// MARK: - Example 10: Location-Based Auto-Activation

func exampleLocationBasedQuietHours() async {
    // Simulate arriving home at night
    let homeLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)  // San Francisco

    if let context = await AdaptiveQuietHoursEngine.shared.detectLocationContext(
        location: homeLocation
    ) {
        switch context.type {
        case .home:
            print("🏠 You're home!")
            if context.shouldEnableQuietHours,
               let start = context.suggestedStart,
               let end = context.suggestedEnd {
                print("🌙 Enabling quiet hours: \(start) - \(end)")
                // Auto-enable quiet hours
            }

        case .church:
            print("⛪️ You're at church!")
            if context.shouldEnableQuietHours {
                print("🙏 Enabling worship mode (quiet hours)")
                // Immediately enable quiet hours
            }

        case .work:
            print("💼 You're at work!")

        case .unknown:
            print("📍 Unknown location")
        }
    }
}

// MARK: - Example 11: Testing Progressive Levels

func exampleTestProgressiveLevels() {
    let levels: [ProgressiveQuietingEngine.QuietLevel] = [
        .none, .minimal, .moderate, .substantial, .critical
    ]

    let testNotifications = [
        ("Reaction", 0.2),
        ("Comment", 0.5),
        ("Reply", 0.6),
        ("Question DM", 0.8),
        ("Crisis Alert", 1.0)
    ]

    print("Progressive Quieting Test Results")
    print("=" * 50)

    for level in levels {
        print("\n\(level.displayName) (threshold: \(level.minimumPriority))")
        print("-" * 50)

        for (name, priority) in testNotifications {
            let wouldDeliver = priority >= level.minimumPriority
            let emoji = wouldDeliver ? "✅" : "❌"
            print("\(emoji) \(name) (priority: \(priority))")
        }
    }

    // Example Output:
    // Progressive Quieting Test Results
    // ==================================================
    //
    // All Notifications (threshold: 0.0)
    // --------------------------------------------------
    // ✅ Reaction (priority: 0.2)
    // ✅ Comment (priority: 0.5)
    // ✅ Reply (priority: 0.6)
    // ✅ Question DM (priority: 0.8)
    // ✅ Crisis Alert (priority: 1.0)
    //
    // Mostly Quiet (threshold: 0.3)
    // --------------------------------------------------
    // ❌ Reaction (priority: 0.2)
    // ✅ Comment (priority: 0.5)
    // ✅ Reply (priority: 0.6)
    // ✅ Question DM (priority: 0.8)
    // ✅ Crisis Alert (priority: 1.0)
}
