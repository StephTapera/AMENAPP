//
//  NotificationExamples.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  Usage examples for AI-powered notifications
//

import SwiftUI
import FirebaseAuth

// MARK: - Notification Usage Examples

struct NotificationUsageExamples {
    
    let genkitService = NotificationGenkitService.shared
    
    // MARK: - Example 1: New Message Notification
    
    func sendNewMessageNotification(
        from sender: MockUser,
        to recipient: MockUser,
        messageText: String
    ) async {
        do {
            let senderProfile = NotificationUserProfile(
                id: sender.id,
                name: sender.name,
                interests: sender.interests ?? [],
                denomination: sender.denomination,
                location: sender.location
            )
            
            try await genkitService.sendSmartNotification(
                eventType: .message,
                senderName: sender.name,
                senderProfile: senderProfile,
                recipientId: recipient.id,
                context: messageText,
                metadata: ["messagePreview": String(messageText.prefix(50))],
                customData: [
                    "senderId": sender.id,
                    "conversationId": "\(sender.id)_\(recipient.id)",
                    "messageId": UUID().uuidString
                ]
            )
            
            print("✅ Message notification sent")
        } catch {
            print("❌ Error sending message notification: \(error)")
        }
    }
    
    // MARK: - Example 2: New Match Notification
    
    func sendNewMatchNotification(
        matchedUser: MockUser,
        currentUser: MockUser
    ) async {
        do {
            let matchProfile = NotificationUserProfile(
                id: matchedUser.id,
                name: matchedUser.name,
                interests: matchedUser.interests ?? [],
                denomination: matchedUser.denomination,
                location: matchedUser.location
            )
            
            // Find shared interests
            let sharedInterests = Set(currentUser.interests ?? [])
                .intersection(Set(matchedUser.interests ?? []))
            
            let context = sharedInterests.isEmpty
                ? "You have a new match!"
                : "You both enjoy: \(sharedInterests.joined(separator: ", "))"
            
            try await genkitService.sendSmartNotification(
                eventType: .match,
                senderName: matchedUser.name,
                senderProfile: matchProfile,
                recipientId: currentUser.id,
                context: context,
                metadata: [
                    "sharedInterests": Array(sharedInterests),
                    "compatibilityScore": 85
                ],
                customData: [
                    "matchId": matchedUser.id,
                    "matchType": "mutual"
                ]
            )
            
            print("✅ Match notification sent")
        } catch {
            print("❌ Error sending match notification: \(error)")
        }
    }
    
    // MARK: - Example 3: Prayer Request Notification
    
    func sendPrayerRequestNotification(
        requester: MockUser,
        prayerRequest: String,
        prayerCircleMembers: [MockUser],
        isUrgent: Bool = false
    ) async {
        
        for member in prayerCircleMembers {
            do {
                let requesterProfile = NotificationUserProfile(
                    id: requester.id,
                    name: requester.name,
                    interests: requester.interests ?? [],
                    denomination: requester.denomination,
                    location: requester.location
                )
                
                let context = isUrgent
                    ? "URGENT: \(prayerRequest)"
                    : prayerRequest
                
                try await genkitService.sendSmartNotification(
                    eventType: .prayerRequest,
                    senderName: requester.name,
                    senderProfile: requesterProfile,
                    recipientId: member.id,
                    context: context,
                    metadata: [
                        "urgent": isUrgent,
                        "category": "prayer"
                    ],
                    customData: [
                        "requesterId": requester.id,
                        "prayerRequestId": UUID().uuidString,
                        "priority": isUrgent ? "high" : "medium"
                    ]
                )
                
                print("✅ Prayer request notification sent to \(member.name)")
            } catch {
                print("❌ Error sending prayer notification to \(member.name): \(error)")
            }
        }
    }
    
    // MARK: - Example 4: Event Reminder
    
    func sendEventReminderNotification(
        event: Event,
        attendees: [MockUser],
        minutesUntilStart: Int
    ) async {
        
        for attendee in attendees {
            do {
                let context = "\(event.title) starts in \(minutesUntilStart) minutes at \(event.location)"
                
                try await genkitService.sendSmartNotification(
                    eventType: .eventReminder,
                    senderName: event.organizerName,
                    senderProfile: nil,
                    recipientId: attendee.id,
                    context: context,
                    metadata: [
                        "eventType": event.type,
                        "minutesUntil": minutesUntilStart
                    ],
                    customData: [
                        "eventId": event.id,
                        "eventTitle": event.title,
                        "eventLocation": event.location,
                        "eventTime": event.startTime.timeIntervalSince1970
                    ]
                )
                
                print("✅ Event reminder sent to \(attendee.name)")
            } catch {
                print("❌ Error sending event reminder to \(attendee.name): \(error)")
            }
        }
    }
    
    // MARK: - Example 5: Batch Notification Summary
    
    func sendDailyNotificationSummary(userId: String) async {
        do {
            // Fetch pending notifications from Firestore
            let pendingNotifications = try await fetchPendingNotifications(userId: userId)
            
            guard pendingNotifications.count >= 3 else {
                print("⚠️ Not enough notifications to batch")
                return
            }
            
            try await genkitService.sendBatchNotificationSummary(
                userId: userId,
                pendingNotifications: pendingNotifications
            )
            
            print("✅ Daily summary sent to user: \(userId)")
        } catch {
            print("❌ Error sending daily summary: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchPendingNotifications(userId: String) async throws -> [PendingNotification] {
        // This would fetch from Firestore
        // For now, return sample data
        return [
            PendingNotification(
                id: "1",
                type: "message",
                senderName: "Sarah",
                message: "Hi! Would love to chat about your Bible study group",
                timestamp: Date().addingTimeInterval(-3600)
            ),
            PendingNotification(
                id: "2",
                type: "like",
                senderName: "John",
                message: "liked your post about prayer",
                timestamp: Date().addingTimeInterval(-7200)
            ),
            PendingNotification(
                id: "3",
                type: "match",
                senderName: "David",
                message: "You have a new match!",
                timestamp: Date().addingTimeInterval(-10800)
            )
        ]
    }
}

// MARK: - Test View for Notifications

struct NotificationTestView: View {
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    let examples = NotificationUsageExamples()
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Test AI-powered notifications")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Section("Single Notifications") {
                    Button {
                        testMessageNotification()
                    } label: {
                        NotificationTestRow(
                            icon: "message.fill",
                            title: "New Message",
                            description: "Personalized message notification"
                        )
                    }
                    
                    Button {
                        testMatchNotification()
                    } label: {
                        NotificationTestRow(
                            icon: "heart.fill",
                            title: "New Match",
                            description: "Match with shared interests"
                        )
                    }
                    
                    Button {
                        testPrayerNotification()
                    } label: {
                        NotificationTestRow(
                            icon: "hands.sparkles.fill",
                            title: "Prayer Request",
                            description: "Urgent prayer request"
                        )
                    }
                    
                    Button {
                        testEventReminder()
                    } label: {
                        NotificationTestRow(
                            icon: "calendar.badge.clock",
                            title: "Event Reminder",
                            description: "Event starting soon"
                        )
                    }
                }
                
                Section("Batch Notifications") {
                    Button {
                        testBatchSummary()
                    } label: {
                        NotificationTestRow(
                            icon: "tray.full.fill",
                            title: "Daily Summary",
                            description: "Summarize multiple notifications"
                        )
                    }
                }
                
                Section("Info") {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        Text("All notifications are AI-enhanced")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                        Text("Timing is optimized per user")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.green)
                        Text("Content is personalized")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                }
            }
            .navigationTitle("Test AI Notifications")
            .alert("Notification Sent", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Test Functions
    
    func testMessageNotification() {
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            let sender = createMockUser(name: "Sarah", interests: ["Prayer", "Worship", "Bible Study"])
            let recipient = createMockUser(id: currentUserId, name: "You", interests: ["Prayer", "Ministry"])
            
            await examples.sendNewMessageNotification(
                from: sender,
                to: recipient,
                messageText: "Hi! I saw your post about the prayer group and would love to join. Are you meeting this week?"
            )
            
            await MainActor.run {
                alertMessage = "AI-powered message notification sent!\n\nCheck the console for details."
                showingAlert = true
            }
        }
    }
    
    func testMatchNotification() {
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            let matchedUser = createMockUser(name: "David", interests: ["Worship Music", "Prayer", "Youth Ministry"])
            let currentUser = createMockUser(id: currentUserId, name: "You", interests: ["Worship Music", "Bible Study", "Prayer"])
            
            await examples.sendNewMatchNotification(
                matchedUser: matchedUser,
                currentUser: currentUser
            )
            
            await MainActor.run {
                alertMessage = "AI-powered match notification sent!\n\nShared interests highlighted."
                showingAlert = true
            }
        }
    }
    
    func testPrayerNotification() {
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            let requester = createMockUser(name: "John", interests: ["Prayer"])
            let member = createMockUser(id: currentUserId, name: "You", interests: ["Prayer"])
            
            await examples.sendPrayerRequestNotification(
                requester: requester,
                prayerRequest: "Please pray for my father's surgery tomorrow morning. We're trusting God for a successful procedure.",
                prayerCircleMembers: [member],
                isUrgent: true
            )
            
            await MainActor.run {
                alertMessage = "AI-powered prayer notification sent!\n\nMarked as high priority."
                showingAlert = true
            }
        }
    }
    
    func testEventReminder() {
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            let event = Event(
                id: "1",
                title: "Sunday Worship Night",
                organizerName: "City Church",
                type: "worship",
                location: "City Church Main Hall",
                startTime: Date().addingTimeInterval(3600)
            )
            
            let attendee = createMockUser(id: currentUserId, name: "You", interests: ["Worship"])
            
            await examples.sendEventReminderNotification(
                event: event,
                attendees: [attendee],
                minutesUntilStart: 60
            )
            
            await MainActor.run {
                alertMessage = "AI-powered event reminder sent!\n\nTiming optimized."
                showingAlert = true
            }
        }
    }
    
    func testBatchSummary() {
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            await examples.sendDailyNotificationSummary(userId: currentUserId)
            
            await MainActor.run {
                alertMessage = "AI-powered batch summary sent!\n\nMultiple notifications combined."
                showingAlert = true
            }
        }
    }
    
    // MARK: - Mock Data
    
    func createMockUser(id: String = UUID().uuidString, name: String, interests: [String]) -> MockUser {
        MockUser(
            id: id,
            name: name,
            interests: interests,
            denomination: "Non-denominational",
            location: "Los Angeles, CA"
        )
    }
}

// MARK: - Supporting Components

struct NotificationTestRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.purple)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mock Models

struct MockUser {
    let id: String
    let name: String
    let interests: [String]?
    let denomination: String?
    let location: String?
}

struct Event {
    let id: String
    let title: String
    let organizerName: String
    let type: String
    let location: String
    let startTime: Date
}

// MARK: - Preview

#Preview {
    NotificationTestView()
}
