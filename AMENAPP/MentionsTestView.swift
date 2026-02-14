//
//  MentionsTestView.swift
//  AMENAPP
//
//  Test view for demonstrating @mention functionality
//

import SwiftUI

struct MentionsTestView: View {
    @State private var testPosts: [TestPost] = [
        TestPost(
            id: "1",
            authorName: "Sarah Johnson",
            authorUsername: "sarah_j",
            content: "Hey @john_doe and @alex_smith, check out this new feature! Thanks @david_chen for the help building it.",
            mentions: [
                MentionedUser(userId: "u1", username: "john_doe", displayName: "John Doe"),
                MentionedUser(userId: "u2", username: "alex_smith", displayName: "Alex Smith"),
                MentionedUser(userId: "u3", username: "david_chen", displayName: "David Chen")
            ],
            timestamp: "2m ago"
        ),
        TestPost(
            id: "2",
            authorName: "Michael Brown",
            authorUsername: "mike_b",
            content: "Just launched our new app! Shoutout to @sarah_j for the amazing design work.",
            mentions: [
                MentionedUser(userId: "u4", username: "sarah_j", displayName: "Sarah Johnson")
            ],
            timestamp: "15m ago"
        ),
        TestPost(
            id: "3",
            authorName: "Emily Davis",
            authorUsername: "emily_d",
            content: "This is a regular post without any mentions. Just sharing my thoughts on the latest updates.",
            mentions: nil,
            timestamp: "1h ago"
        )
    ]
    
    @State private var selectedMention: MentionedUser?
    @State private var showMentionAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "at.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        Text("@Mentions Test")
                            .font(.title.bold())
                        
                        Text("Tap on any @mention to see it work")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Test Posts
                    ForEach(testPosts) { post in
                        testPostCard(post)
                    }
                    
                    // Feature List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("✅ Implemented Features")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Live Autocomplete",
                            description: "Type @ in CreatePostView to see suggestions",
                            color: .green
                        )
                        
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Clickable Mentions",
                            description: "Mentions are styled in blue and tappable",
                            color: .green
                        )
                        
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Structured Storage",
                            description: "Mentions stored with userId, username, displayName",
                            color: .green
                        )
                        
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Push Notifications",
                            description: "Cloud Function sends notifications to mentioned users",
                            color: .green
                        )
                        
                        featureRow(
                            icon: "checkmark.circle.fill",
                            title: "Deduplication",
                            description: "Deterministic IDs prevent duplicate notifications",
                            color: .green
                        )
                    }
                    .padding(.vertical)
                }
                .padding()
            }
            .navigationTitle("Mentions Demo")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Mention Tapped", isPresented: $showMentionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if let mention = selectedMention {
                    Text("You tapped @\(mention.username)\n\nUser ID: \(mention.userId)\nDisplay Name: \(mention.displayName)\n\nIn a real app, this would navigate to their profile.")
                }
            }
        }
    }
    
    // MARK: - Test Post Card
    
    private func testPostCard(_ post: TestPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(post.authorInitials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: 15, weight: .semibold))
                    
                    Text("@\(post.authorUsername)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(post.timestamp)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            // Content with mentions
            MentionTextView(
                text: post.content,
                mentions: post.mentions,
                font: .system(size: 15),
                lineSpacing: 4
            ) { mention in
                selectedMention = mention
                showMentionAlert = true
            }
            
            // Mention count badge
            if let mentions = post.mentions, !mentions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "at")
                        .font(.system(size: 10))
                    Text("\(mentions.count) mention\(mentions.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Feature Row
    
    private func featureRow(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }
}

// MARK: - Test Post Model

struct TestPost: Identifiable {
    let id: String
    let authorName: String
    let authorUsername: String
    let content: String
    let mentions: [MentionedUser]?
    let timestamp: String
    
    var authorInitials: String {
        String(authorName.prefix(1))
    }
}

// MARK: - Preview

#Preview {
    MentionsTestView()
}
