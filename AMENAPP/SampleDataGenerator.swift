//
//  SampleDataGenerator.swift
//  AMENAPP
//
//  Created for App Store Screenshots
//
//  Generates realistic sample posts for OpenTable, Prayer, and Testimonies
//

import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Generates sample posts for App Store screenshots
@MainActor
class SampleDataGenerator {
    static let shared = SampleDataGenerator()

    private let db = Firestore.firestore()

    // MARK: - Sample Posts Data

    /// High-quality OpenTable discussion posts
    private let openTablePosts = [
        "How do you find peace when everything feels chaotic? I've been struggling lately and would love to hear your thoughts. 🙏",

        "What does it mean to truly forgive someone who hurt you deeply? Wrestling with this question today.",

        "Can we talk about finding purpose in our daily work? Sometimes it feels mundane, but I know God has a plan."
    ]

    /// Heartfelt prayer requests
    private let prayerPosts = [
        "Please pray for my mom who's going in for surgery tomorrow. She's been so strong but I know she's scared. Praying for peace and healing. 💙",

        "Asking for prayers as I start my new job on Monday. Feeling nervous but trusting God's plan for this next chapter.",

        "My marriage is going through a really difficult season. Please pray for reconciliation, wisdom, and God's presence in our home."
    ]

    /// Powerful testimonies
    private let testimonyPosts = [
        "God brought me out of the darkest depression I've ever faced. I never thought I'd smile again, but He restored my joy. If you're in the darkness, hold on - breakthrough is coming! ✨",

        "I was drowning in debt and had no way out. Started tithing in faith even when it didn't make sense. Within 6 months, completely debt free. God is faithful! 💪",

        "My doctor said I'd never have children. Today I'm holding my miracle baby. God had the final say! Never stop believing. 👶💕"
    ]

    // MARK: - Generate Sample Posts

    /// Creates sample posts for all categories
    func generateAllSamplePosts() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "SampleDataGenerator", code: 401, userInfo: [NSLocalizedDescriptionKey: "Must be signed in to generate sample data"])
        }

        let userId = currentUser.uid
        let userName = currentUser.displayName ?? "Demo User"
        let userInitials = String(userName.prefix(2).uppercased())

        print("🎬 Generating sample posts for App Store screenshots...")
        print("   User: \(userName) (\(userId))")

        // Generate 3 posts for each category
        try await generateCategoryPosts(
            posts: Array(openTablePosts.prefix(3)),
            category: "openTable",
            userId: userId,
            userName: userName,
            userInitials: userInitials
        )

        try await generateCategoryPosts(
            posts: Array(prayerPosts.prefix(3)),
            category: "prayer",
            userId: userId,
            userName: userName,
            userInitials: userInitials
        )

        try await generateCategoryPosts(
            posts: Array(testimonyPosts.prefix(3)),
            category: "testimonies",
            userId: userId,
            userName: userName,
            userInitials: userInitials
        )

        print("✅ Sample posts generated successfully!")
        print("   Total: 9 posts (3 per category)")
    }

    /// Generates posts for a specific category
    private func generateCategoryPosts(
        posts: [String],
        category: String,
        userId: String,
        userName: String,
        userInitials: String
    ) async throws {

        for (index, content) in posts.enumerated() {
            // Create post data matching FirebasePostService structure
            let postData: [String: Any] = [
                "authorId": userId,
                "authorName": userName,
                "authorInitials": userInitials,
                "content": content,
                "category": category,
                "visibility": "everyone",
                "allowComments": true,
                "createdAt": Timestamp(date: Date().addingTimeInterval(-Double(index * 3600))), // Space posts 1 hour apart
                "amenCount": Int.random(in: 5...25),
                "lightbulbCount": Int.random(in: 3...20),
                "commentCount": Int.random(in: 0...8),
                "repostCount": Int.random(in: 0...5),
                "isRepost": false
            ]

            // Add to Firestore
            try await db.collection("posts").addDocument(data: postData)

            print("   ✓ Created \(category) post: \(content.prefix(40))...")
        }
    }

    // MARK: - Clear Sample Posts

    /// Removes all sample posts (useful after taking screenshots)
    func clearSamplePosts() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "SampleDataGenerator", code: 401, userInfo: [NSLocalizedDescriptionKey: "Must be signed in"])
        }

        let userId = currentUser.uid

        print("🗑️ Clearing sample posts...")

        // Fetch all posts by current user
        let snapshot = try await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .getDocuments()

        // Delete each post
        for document in snapshot.documents {
            try await document.reference.delete()
        }

        print("✅ Cleared \(snapshot.documents.count) sample posts")
    }
}

// MARK: - Developer Menu Integration

/// Developer view for generating sample data
struct SampleDataGeneratorView: View {
    @State private var isGenerating = false
    @State private var isClearing = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Generate realistic sample posts for App Store screenshots")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sample Data Generator")
                }

                Section {
                    Button {
                        generateSamplePosts()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("Generate Sample Posts")
                                .foregroundStyle(.primary)

                            Spacer()

                            if isGenerating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isGenerating)

                    Button {
                        clearSamplePosts()
                    } label: {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundStyle(.red)
                            Text("Clear Sample Posts")
                                .foregroundStyle(.primary)

                            Spacer()

                            if isClearing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isClearing)
                } header: {
                    Text("Actions")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("5 OpenTable discussions", systemImage: "bubble.left.and.bubble.right")
                        Label("5 Prayer requests", systemImage: "hands.sparkles")
                        Label("5 Testimonies", systemImage: "star.fill")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                } header: {
                    Text("What Gets Generated")
                }
            }
            .navigationTitle("Sample Data")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Sample Data", isPresented: $showMessage) {
                Button("OK") {
                    showMessage = false
                }
            } message: {
                Text(message)
            }
        }
    }

    private func generateSamplePosts() {
        isGenerating = true

        Task {
            do {
                try await SampleDataGenerator.shared.generateAllSamplePosts()

                await MainActor.run {
                    message = "Successfully generated 9 sample posts!\n\nYou can now take screenshots in:\n• OpenTable (3 posts)\n• Prayer View (3 posts)\n• Testimonies (3 posts)"
                    showMessage = true
                    isGenerating = false

                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    message = "Error: \(error.localizedDescription)"
                    showMessage = true
                    isGenerating = false

                    // Error haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }

    private func clearSamplePosts() {
        isClearing = true

        Task {
            do {
                try await SampleDataGenerator.shared.clearSamplePosts()

                await MainActor.run {
                    message = "Sample posts cleared successfully!"
                    showMessage = true
                    isClearing = false

                    // Haptic feedback
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    message = "Error: \(error.localizedDescription)"
                    showMessage = true
                    isClearing = false

                    // Error haptic
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

#Preview {
    SampleDataGeneratorView()
}
