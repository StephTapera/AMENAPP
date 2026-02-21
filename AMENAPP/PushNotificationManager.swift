//
//  PushNotificationManager.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//
//  Handles push notifications via Firebase Cloud Messaging (FCM)
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var deviceToken: String?
    @Published var fcmToken: String?
    @Published var notificationPermissionGranted = false
    
    private let db = Firestore.firestore()
    private var fcmTokenObserver: NSObjectProtocol?
    
    // P0 FIX: Prevent duplicate FCM setup
    private var hasSetupFCM = false
    
    private override init() {
        super.init()
    }
    
    deinit {
        if let observer = fcmTokenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        print("🧹 PushNotificationManager deallocated, observers removed")
    }
    
    // MARK: - Request Permissions
    
    @MainActor
    func requestNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                notificationPermissionGranted = granted
            }
            
            if granted {
                print("✅ Notification permission granted")
                await registerForRemoteNotifications()
            } else {
                print("❌ Notification permission denied")
            }
            
            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    @MainActor
    func checkNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let granted = settings.authorizationStatus == .authorized
        
        await MainActor.run {
            notificationPermissionGranted = granted
        }
        
        return granted
    }
    
    // MARK: - Register for Remote Notifications
    
    func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
        print("📱 Registering for remote notifications...")
    }
    
    // MARK: - Handle Device Token
    
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        self.deviceToken = token
        print("📱 Device Token: \(token)")
        
        // Set APNs token for FCM
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - FCM Token Management
    
    func setupFCMToken() {
        // P0 FIX: Prevent duplicate setup (called 3x in codebase)
        guard !hasSetupFCM else {
            print("⚠️ FCM already set up, skipping duplicate setup")
            return
        }
        hasSetupFCM = true
        
        #if targetEnvironment(simulator)
        print("⚠️ Skipping FCM setup on simulator (APNS not available)")
        return
        #else
        // Get FCM token
        Messaging.messaging().token { [weak self] token, error in
            guard let self = self else { return }
            
            if let error = error {
                // Only log as warning, not error, since it's expected on simulator
                print("⚠️ FCM token unavailable: \(error.localizedDescription)")
                return
            }
            
            if let token = token {
                Task { @MainActor in
                    self.fcmToken = token
                    print("🔑 FCM Token: \(token)")
                    await self.saveFCMTokenToFirestore(token)
                }
            }
        }
        #endif
        
        // P0 FIX: Remove old observer before adding new one
        if let observer = fcmTokenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Listen for token refresh - store observer for cleanup
        fcmTokenObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.MessagingRegistrationTokenRefreshed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fcmTokenRefreshed()
        }
        
        print("✅ FCM setup complete")
    }
    
    private func fcmTokenRefreshed() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self = self, let token = token else { return }
            
            Task { @MainActor in
                self.fcmToken = token
                print("🔄 FCM Token refreshed: \(token)")
                await self.saveFCMTokenToFirestore(token)
            }
        }
    }
    
    // MARK: - Save Token to Firestore
    
    private func saveFCMTokenToFirestore(_ token: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user to save FCM token")
            return
        }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": token,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
                "platform": "ios"
            ])
            
            print("✅ FCM token saved to Firestore for user: \(userId)")
        } catch {
            print("❌ Error saving FCM token to Firestore: \(error)")
        }
    }
    
    // MARK: - Remove Token on Logout
    
    func removeFCMTokenFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete()
            ])
            
            print("✅ FCM token removed from Firestore")
        } catch {
            print("❌ Error removing FCM token: \(error)")
        }
    }
    
    // MARK: - Handle Foreground Notifications
    
    func handleForegroundNotification(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        
        print("📬 Received foreground notification:")
        print("   Title: \(notification.request.content.title)")
        print("   Body: \(notification.request.content.body)")
        print("   User Info: \(userInfo)")
        
        // Update badge count
        updateBadgeCount()
        
        // Post local notification for app to handle
        NotificationCenter.default.post(
            name: Notification.Name("pushNotificationReceived"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        print("👆 User tapped notification:")
        print("   User Info: \(userInfo)")
        
        // Extract notification type and data
        if let notificationType = userInfo["type"] as? String {
            handleNotificationAction(type: notificationType, data: userInfo)
        }
    }
    
    @MainActor
    private func handleNotificationAction(type: String, data: [AnyHashable: Any]) {
        // Handle different notification types
        switch type {
        case "message":
            // Open specific conversation
            if let conversationId = data["conversationId"] as? String {
                print("📬 Opening conversation: \(conversationId)")
                Task { @MainActor in
                    MessagingCoordinator.shared.openConversation(conversationId)
                }
            }
        case "messageRequest":
            // Open message requests tab
            if let conversationId = data["conversationId"] as? String {
                print("📨 Opening message request: \(conversationId)")
                Task { @MainActor in
                    MessagingCoordinator.shared.openMessageRequests()
                }
            }
        default:
            // Post notification for app to handle navigation
            NotificationCenter.default.post(
                name: Notification.Name("pushNotificationTapped"),
                object: nil,
                userInfo: data as? [String: Any] ?? [:]
            )
        }
    }
    
    // MARK: - Badge Management
    
    /// Update badge count (delegates to BadgeCountManager for thread-safety and caching)
    func updateBadgeCount() {
        Task { @MainActor in
            BadgeCountManager.shared.requestBadgeUpdate()
        }
    }
    
    /// Clear badge count
    func clearBadge() {
        Task { @MainActor in
            BadgeCountManager.shared.clearBadge()
        }
    }
    
    // MARK: - Test Notification
    
    func scheduleTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This is a test notification from AMENAPP"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Test notification scheduled")
        } catch {
            print("❌ Error scheduling test notification: \(error)")
        }
    }
    
    // MARK: - Daily Reminder Notifications
    
    /// Schedule 2 daily prayer reminders with rotating Bible verses (changes each day)
    func scheduleDailyReminders() async {
        // Cancel existing reminders first
        await cancelDailyReminders()
        
        // Get today's verses (rotates based on day of year)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let morningVerseIndex = dayOfYear % morningVerses.count
        let eveningVerseIndex = dayOfYear % eveningVerses.count
        
        // Morning Prayer - 8:00 AM
        await scheduleDailyReminder(
            identifier: "morning_prayer",
            title: "Morning Prayer",
            body: morningVerses[morningVerseIndex],
            hour: 8,
            minute: 0
        )
        
        // Evening Prayer - 8:00 PM
        await scheduleDailyReminder(
            identifier: "evening_prayer",
            title: "Evening Prayer",
            body: eveningVerses[eveningVerseIndex],
            hour: 20,
            minute: 0
        )
        
        print("✅ Daily prayer reminders scheduled (2 notifications)")
        print("   Morning: \(morningVerses[morningVerseIndex].prefix(50))...")
        print("   Evening: \(eveningVerses[eveningVerseIndex].prefix(50))...")
    }
    
    // MARK: - Rotating Bible Verses
    
    /// Morning verses focused on starting the day with God
    private let morningVerses = [
        "This is the day the Lord has made; let us rejoice and be glad in it. - Psalm 118:24",
        "In the morning, Lord, you hear my voice; in the morning I lay my requests before you. - Psalm 5:3",
        "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning. - Lamentations 3:22-23",
        "Let the morning bring me word of your unfailing love, for I have put my trust in you. - Psalm 143:8",
        "Satisfy us in the morning with your unfailing love, that we may sing for joy and be glad all our days. - Psalm 90:14",
        "Very early in the morning, while it was still dark, Jesus got up and went off to pray. - Mark 1:35",
        "The steadfast love of the Lord never ceases; his mercies never come to an end. - Lamentations 3:22",
        "Commit to the Lord whatever you do, and he will establish your plans. - Proverbs 16:3",
        "Trust in the Lord with all your heart and lean not on your own understanding. - Proverbs 3:5",
        "Seek first his kingdom and his righteousness, and all these things will be given to you. - Matthew 6:33",
        "I can do all things through Christ who strengthens me. - Philippians 4:13",
        "The Lord is my strength and my shield; my heart trusts in him, and he helps me. - Psalm 28:7",
        "This is the confidence we have in approaching God: that if we ask anything according to his will, he hears us. - 1 John 5:14",
        "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you. - Joshua 1:9",
        "Give thanks to the Lord, for he is good; his love endures forever. - Psalm 107:1"
    ]
    
    /// Evening verses focused on reflection, peace, and rest
    private let eveningVerses = [
        "In peace I will lie down and sleep, for you alone, Lord, make me dwell in safety. - Psalm 4:8",
        "Cast all your anxiety on him because he cares for you. - 1 Peter 5:7",
        "Come to me, all you who are weary and burdened, and I will give you rest. - Matthew 11:28",
        "The Lord bless you and keep you; the Lord make his face shine on you and be gracious to you. - Numbers 6:24-25",
        "Be still, and know that I am God. - Psalm 46:10",
        "Give thanks in all circumstances; for this is God's will for you in Christ Jesus. - 1 Thessalonians 5:18",
        "May the God of hope fill you with all joy and peace as you trust in him. - Romans 15:13",
        "The Lord is near to all who call on him, to all who call on him in truth. - Psalm 145:18",
        "Do not be anxious about anything, but in every situation, by prayer and petition, present your requests to God. - Philippians 4:6",
        "The Lord will watch over your coming and going both now and forevermore. - Psalm 121:8",
        "I will both lie down in peace, and sleep; for You alone, O Lord, make me dwell in safety. - Psalm 4:8",
        "Peace I leave with you; my peace I give you. I do not give to you as the world gives. - John 14:27",
        "The Lord gives strength to his people; the Lord blesses his people with peace. - Psalm 29:11",
        "When you lie down, you will not be afraid; when you lie down, your sleep will be sweet. - Proverbs 3:24",
        "He who watches over you will not slumber. - Psalm 121:3"
    ]
    
    /// Schedule custom reminder notifications with rotating Bible verses
    func scheduleRemindersWithRotatingVerses() async {
        // Cancel existing reminders first
        await cancelDailyReminders()
        
        // Array of inspirational Bible verses
        let verses = [
            "\"I can do all things through Christ who strengthens me.\" - Philippians 4:13",
            "\"For God so loved the world that He gave His only Son.\" - John 3:16",
            "\"The Lord is my shepherd; I shall not want.\" - Psalm 23:1",
            "\"Be strong and courageous. Do not be afraid.\" - Joshua 1:9",
            "\"Cast all your anxiety on Him because He cares for you.\" - 1 Peter 5:7",
            "\"The joy of the Lord is your strength.\" - Nehemiah 8:10",
            "\"His mercies are new every morning.\" - Lamentations 3:22-23",
            "\"God is our refuge and strength.\" - Psalm 46:1"
        ]
        
        // Get current day of week (0 = Sunday, 6 = Saturday)
        let dayOfWeek = Calendar.current.component(.weekday, from: Date()) - 1
        let todayVerse = verses[dayOfWeek % verses.count]
        
        // Morning verse - 7:00 AM
        await scheduleDailyReminder(
            identifier: "morning_verse",
            title: "Good Morning! 🌅",
            body: todayVerse,
            hour: 7,
            minute: 0
        )
        
        // Afternoon reminder - 2:00 PM
        await scheduleDailyReminder(
            identifier: "afternoon_reminder",
            title: "Stay Connected 💙",
            body: "Take a moment to pray and reflect on God's goodness",
            hour: 14,
            minute: 0
        )
        
        // Evening verse - 7:00 PM
        await scheduleDailyReminder(
            identifier: "evening_verse",
            title: "Evening Blessing 🌙",
            body: verses[(dayOfWeek + 1) % verses.count],
            hour: 19,
            minute: 0
        )
        
        print("✅ Rotating verse reminders scheduled")
    }
    
    /// Schedule a single daily reminder notification
    private func scheduleDailyReminder(
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 0 // Don't increment badge for reminders
        content.categoryIdentifier = "DAILY_REMINDER"
        content.userInfo = ["type": "daily_reminder", "reminderType": identifier]
        
        // Create date components for the notification
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        // Create trigger that repeats daily at specified time
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Scheduled daily reminder: \(identifier) at \(hour):\(String(format: "%02d", minute))")
        } catch {
            print("❌ Error scheduling daily reminder \(identifier): \(error)")
        }
    }
    
    /// Cancel all daily reminder notifications
    func cancelDailyReminders() async {
        let identifiers = [
            // Standard daily reminders
            "early_morning_prayer",
            "morning_prayer",
            "mid_morning_verse",
            "midday_devotional",
            "afternoon_prayer",
            "evening_gratitude",
            "evening_prayer",
            "night_prayer",
            // Rotating verse reminders
            "morning_verse",
            "afternoon_reminder",
            "evening_verse"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🗑️ Cancelled all daily reminders")
    }
    
    /// Check if daily reminders are currently scheduled
    func areDailyRemindersScheduled() async -> Bool {
        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        
        let reminderIdentifiers = [
            "early_morning_prayer",
            "morning_prayer",
            "mid_morning_verse",
            "midday_devotional",
            "afternoon_prayer",
            "evening_gratitude",
            "evening_prayer",
            "night_prayer"
        ]
        
        let scheduledReminders = pendingRequests.filter { request in
            reminderIdentifiers.contains(request.identifier)
        }
        
        // Return true if at least half of the reminders are scheduled
        return scheduledReminders.count >= (reminderIdentifiers.count / 2)
    }
    
    /// Get list of all scheduled daily reminders with their times
    func getScheduledReminders() async -> [(identifier: String, hour: Int, minute: Int)] {
        let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        
        var reminders: [(identifier: String, hour: Int, minute: Int)] = []
        
        for request in pendingRequests {
            if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                let dateComponents = trigger.dateComponents
                if let hour = dateComponents.hour,
                   let minute = dateComponents.minute {
                    reminders.append((request.identifier, hour, minute))
                }
            }
        }
        
        return reminders.sorted { $0.hour < $1.hour }
    }
    
    // MARK: - Verse of the Day
    
    /// Get a daily Bible verse based on the current day
    func getVerseOfTheDay() -> (reference: String, text: String) {
        let verses = [
            (reference: "Philippians 4:13", text: "I can do all things through Christ who strengthens me."),
            (reference: "John 3:16", text: "For God so loved the world that He gave His only Son, that whoever believes in Him shall not perish but have eternal life."),
            (reference: "Psalm 23:1", text: "The Lord is my shepherd; I shall not want."),
            (reference: "Joshua 1:9", text: "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go."),
            (reference: "1 Peter 5:7", text: "Cast all your anxiety on Him because He cares for you."),
            (reference: "Nehemiah 8:10", text: "The joy of the Lord is your strength."),
            (reference: "Lamentations 3:22-23", text: "Because of the Lord's great love we are not consumed, for His compassions never fail. They are new every morning."),
            (reference: "Psalm 46:1", text: "God is our refuge and strength, an ever-present help in trouble."),
            (reference: "Jeremiah 29:11", text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future."),
            (reference: "Romans 8:28", text: "And we know that in all things God works for the good of those who love Him."),
            (reference: "Proverbs 3:5-6", text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to Him, and He will make your paths straight."),
            (reference: "Isaiah 40:31", text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles."),
            (reference: "Matthew 6:33", text: "But seek first His kingdom and His righteousness, and all these things will be given to you as well."),
            (reference: "2 Corinthians 12:9", text: "My grace is sufficient for you, for My power is made perfect in weakness."),
            (reference: "Psalm 118:24", text: "This is the day the Lord has made; let us rejoice and be glad in it."),
            (reference: "Hebrews 11:1", text: "Now faith is confidence in what we hope for and assurance about what we do not see."),
            (reference: "Romans 12:2", text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind."),
            (reference: "Matthew 11:28", text: "Come to Me, all you who are weary and burdened, and I will give you rest."),
            (reference: "Psalm 27:1", text: "The Lord is my light and my salvation—whom shall I fear?"),
            (reference: "1 Corinthians 13:13", text: "And now these three remain: faith, hope and love. But the greatest of these is love."),
            (reference: "Galatians 5:22-23", text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control."),
            (reference: "Ephesians 2:8", text: "For it is by grace you have been saved, through faith—and this is not from yourselves, it is the gift of God."),
            (reference: "Isaiah 41:10", text: "So do not fear, for I am with you; do not be dismayed, for I am your God."),
            (reference: "Psalm 91:1-2", text: "Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty."),
            (reference: "James 1:2-3", text: "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds."),
            (reference: "Colossians 3:23", text: "Whatever you do, work at it with all your heart, as working for the Lord."),
            (reference: "1 John 4:19", text: "We love because He first loved us."),
            (reference: "Psalm 37:4", text: "Take delight in the Lord, and He will give you the desires of your heart."),
            (reference: "Matthew 5:16", text: "Let your light shine before others, that they may see your good deeds and glorify your Father in heaven."),
            (reference: "Revelation 21:4", text: "He will wipe every tear from their eyes. There will be no more death or mourning or crying or pain.")
        ]
        
        // Use day of year to rotate through verses (ensures same verse each day)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let verseIndex = (dayOfYear - 1) % verses.count
        
        return verses[verseIndex]
    }
    
    /// Schedule a one-time verse of the day notification
    func scheduleVerseOfTheDayNotification(at hour: Int = 9, minute: Int = 0) async {
        let verse = getVerseOfTheDay()
        
        let content = UNMutableNotificationContent()
        content.title = "📖 Verse of the Day"
        content.body = "\"\(verse.text)\" - \(verse.reference)"
        content.sound = .default
        content.badge = 0
        content.categoryIdentifier = "VERSE_OF_THE_DAY"
        content.userInfo = ["type": "verse_of_the_day", "reference": verse.reference]
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "verse_of_the_day",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Verse of the day notification scheduled for \(hour):\(String(format: "%02d", minute))")
        } catch {
            print("❌ Error scheduling verse of the day: \(error)")
        }
    }
    
    /// Schedule custom reminder at specific time
    func scheduleCustomReminder(
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        repeats: Bool = true
    ) async {
        await scheduleDailyReminder(
            identifier: identifier,
            title: title,
            body: body,
            hour: hour,
            minute: minute
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    
    // Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleForegroundNotification(notification)
        }
        
        // Show notification even in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Called when user taps notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationTap(response)
        }
        
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension PushNotificationManager: MessagingDelegate {
    
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        
        Task { @MainActor in
            self.fcmToken = fcmToken
            print("🔑 FCM Token received: \(fcmToken)")
            await self.saveFCMTokenToFirestore(fcmToken)
        }
    }
}
