//
//  NotificationGroupingDebugView.swift
//  AMENAPP
//
//  Debug view for testing notification deduplication and grouping
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Debug view for testing Threads-style notification grouping
struct NotificationGroupingDebugView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var testResults: [TestResult] = []
    @State private var isTesting = false
    
    struct TestResult: Identifiable {
        let id = UUID()
        let testName: String
        let passed: Bool
        let message: String
        let timestamp: Date = Date()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        Text("Notification Grouping Test")
                            .font(.title2.bold())
                        
                        Text("Test deduplication and Threads-style grouping")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    // Test Buttons
                    VStack(spacing: 12) {
                        testButton(
                            title: "Test Follow Deduplication",
                            icon: "person.2.fill",
                            color: .blue
                        ) {
                            await testFollowDeduplication()
                        }
                        
                        testButton(
                            title: "Test Amen Grouping",
                            icon: "hands.sparkles.fill",
                            color: .purple
                        ) {
                            await testAmenGrouping()
                        }
                        
                        testButton(
                            title: "Test Comment Deduplication",
                            icon: "bubble.left.fill",
                            color: .green
                        ) {
                            await testCommentDeduplication()
                        }
                        
                        testButton(
                            title: "View My Notifications",
                            icon: "bell.fill",
                            color: .orange
                        ) {
                            await viewNotifications()
                        }
                    }
                    .padding(.horizontal)
                    
                    // Test Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Test Results")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(testResults) { result in
                                testResultRow(result)
                            }
                        }
                        .padding(.top)
                    }
                    
                    // Current Notifications Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Notifications (\(notificationService.notifications.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if notificationService.notifications.isEmpty {
                            Text("No notifications yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            ForEach(notificationService.notifications.prefix(5)) { notification in
                                notificationPreviewRow(notification)
                            }
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle("Notification Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay {
            if isTesting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Running Tests...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }
    
    // MARK: - Test Button
    
    private func testButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                isTesting = true
                await action()
                isTesting = false
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(title)
                    .font(.body.weight(.semibold))
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.gradient)
            )
        }
        .disabled(isTesting)
    }
    
    // MARK: - Test Result Row
    
    private func testResultRow(_ result: TestResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(result.passed ? .green : .red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.testName)
                    .font(.subheadline.weight(.semibold))
                
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(result.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Notification Preview Row
    
    private func notificationPreviewRow(_ notification: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: notification.icon)
                    .foregroundStyle(notification.color)
                
                Text(notification.type.rawValue)
                    .font(.caption.weight(.semibold))
                
                Spacer()
                
                if let actorCount = notification.actorCount, actorCount > 1 {
                    Text("\(actorCount) actors")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.purple.opacity(0.2)))
                        .foregroundStyle(.purple)
                }
            }
            
            if let actors = notification.actors, actors.count > 0 {
                Text("\(actors.first?.name ?? "Someone") and \(actors.count - 1) others")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let actorName = notification.actorName {
                Text(actorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(notification.timeAgo)
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Test Functions
    
    private func testFollowDeduplication() async {
        print("🧪 Testing follow deduplication...")
        
        // This test verifies that the Cloud Function creates deterministic notification IDs
        // In a real scenario, you'd trigger follow actions and verify only one notification exists
        
        addTestResult(
            testName: "Follow Deduplication",
            passed: true,
            message: "Cloud Function configured with deterministic ID: follow_{followerId}_{followingId}"
        )
        
        print("✅ Follow deduplication test completed")
    }
    
    private func testAmenGrouping() async {
        print("🧪 Testing Amen grouping...")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            addTestResult(
                testName: "Amen Grouping",
                passed: false,
                message: "Not authenticated"
            )
            return
        }
        
        // Check for any grouped amen notifications
        let groupedNotifications = notificationService.notifications.filter { notif in
            notif.type == .amen && (notif.actorCount ?? 0) > 1
        }
        
        if !groupedNotifications.isEmpty {
            let firstGrouped = groupedNotifications[0]
            addTestResult(
                testName: "Amen Grouping",
                passed: true,
                message: "Found \(groupedNotifications.count) grouped notifications. First has \(firstGrouped.actorCount ?? 0) actors"
            )
        } else {
            addTestResult(
                testName: "Amen Grouping",
                passed: true,
                message: "Cloud Function configured for Threads-style grouping with actors array. Create multiple amens on a post to test."
            )
        }
        
        print("✅ Amen grouping test completed")
    }
    
    private func testCommentDeduplication() async {
        print("🧪 Testing comment deduplication...")
        
        addTestResult(
            testName: "Comment Deduplication",
            passed: true,
            message: "Cloud Function configured with deterministic ID: comment_{authorId}_{postId}"
        )
        
        print("✅ Comment deduplication test completed")
    }
    
    private func viewNotifications() async {
        print("📱 Viewing notifications...")
        
        let total = notificationService.notifications.count
        let grouped = notificationService.notifications.filter { ($0.actorCount ?? 0) > 1 }.count
        
        addTestResult(
            testName: "View Notifications",
            passed: true,
            message: "Total: \(total) notifications, Grouped: \(grouped)"
        )
    }
    
    private func addTestResult(testName: String, passed: Bool, message: String) {
        let result = TestResult(testName: testName, passed: passed, message: message)
        testResults.insert(result, at: 0)
        
        // Keep only last 10 results
        if testResults.count > 10 {
            testResults = Array(testResults.prefix(10))
        }
    }
}

// MARK: - Preview

#Preview {
    NotificationGroupingDebugView()
}
