//
//  PostInteractionsDebugView.swift
//  AMENAPP
//
//  Debug view for monitoring post interactions in real-time
//  Displays lightbulbs, amens, comments, reposts, and saved posts
//

import SwiftUI
import FirebaseAuth

/// Debug view for monitoring all post interactions
struct PostInteractionsDebugView: View {
    @StateObject private var interactionsService = PostInteractionsService.shared
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
    @State private var selectedTab: DebugTab = .lightbulbs
    @State private var isRefreshing = false
    
    enum DebugTab: String, CaseIterable {
        case lightbulbs = "💡 Lightbulbs"
        case amens = "🙏 Amens"
        case comments = "💬 Comments"
        case reposts = "🔄 Reposts"
        case saved = "🔖 Saved"
        case userState = "👤 User State"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .lightbulbs:
                            lightbulbsSection
                        case .amens:
                            amensSection
                        case .comments:
                            commentsSection
                        case .reposts:
                            repostsSection
                        case .saved:
                            savedPostsSection
                        case .userState:
                            userStateSection
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await refresh()
                }
            }
            .navigationTitle("Post Interactions Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DebugTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .bold : .regular))
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.blue : Color(.systemGray6))
                            )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Lightbulbs Section
    
    private var lightbulbsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Lightbulbs (💡)",
                count: interactionsService.postLightbulbs.count
            )
            
            if interactionsService.postLightbulbs.isEmpty {
                emptyState(message: "No lightbulb data tracked yet")
            } else {
                ForEach(Array(interactionsService.postLightbulbs.sorted(by: { $0.value > $1.value })), id: \.key) { postId, count in
                    interactionRow(
                        postId: postId,
                        count: count,
                        icon: "lightbulb.fill",
                        color: .yellow,
                        isUserInteracted: interactionsService.userLightbulbedPosts.contains(postId)
                    )
                }
            }
        }
    }
    
    // MARK: - Amens Section
    
    private var amensSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Amens (🙏)",
                count: interactionsService.postAmens.count
            )
            
            if interactionsService.postAmens.isEmpty {
                emptyState(message: "No amen data tracked yet")
            } else {
                ForEach(Array(interactionsService.postAmens.sorted(by: { $0.value > $1.value })), id: \.key) { postId, count in
                    interactionRow(
                        postId: postId,
                        count: count,
                        icon: "hands.sparkles.fill",
                        color: .purple,
                        isUserInteracted: interactionsService.userAmenedPosts.contains(postId)
                    )
                }
            }
        }
    }
    
    // MARK: - Comments Section
    
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Comments (💬)",
                count: interactionsService.postComments.count
            )
            
            if interactionsService.postComments.isEmpty {
                emptyState(message: "No comment data tracked yet")
            } else {
                commentsListView
            }
        }
    }
    
    private var commentsListView: some View {
        ForEach(Array(interactionsService.postComments.sorted(by: { $0.value > $1.value })), id: \.key) { postId, count in
            commentRowView(postId: postId, count: count)
        }
    }
    
    private func commentRowView(postId: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            interactionRow(
                postId: postId,
                count: count,
                icon: "bubble.left.fill",
                color: .blue,
                isUserInteracted: false
            )
            
            if let comments = interactionsService.postCommentsData[postId], !comments.isEmpty {
                commentPreviewsView(comments: comments)
            }
        }
    }
    
    @ViewBuilder
    private func commentPreviewsView(comments: [RealtimeComment]) -> some View {
        let limitedComments = comments.prefix(3)
        
        VStack(alignment: .leading, spacing: 4) {
            ForEach(limitedComments.indices, id: \.self) { index in
                let comment = limitedComments[limitedComments.index(limitedComments.startIndex, offsetBy: index)]
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.authorName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text(comment.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 20)
            }
            
            if comments.count > 3 {
                Text("+ \(comments.count - 3) more comments")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }
        }
    }
    
    // MARK: - Reposts Section
    
    private var repostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Reposts (🔄)",
                count: interactionsService.postReposts.count
            )
            
            if interactionsService.postReposts.isEmpty {
                emptyState(message: "No repost data tracked yet")
            } else {
                ForEach(Array(interactionsService.postReposts.sorted(by: { $0.value > $1.value })), id: \.key) { postId, count in
                    interactionRow(
                        postId: postId,
                        count: count,
                        icon: "arrow.2.squarepath",
                        color: .green,
                        isUserInteracted: interactionsService.userRepostedPosts.contains(postId)
                    )
                }
            }
        }
    }
    
    // MARK: - Saved Posts Section
    
    private var savedPostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Saved Posts (🔖)",
                count: savedPostsService.savedPostIds.count
            )
            
            if savedPostsService.savedPostIds.isEmpty {
                emptyState(message: "No saved posts yet")
            } else {
                ForEach(Array(savedPostsService.savedPostIds).sorted(), id: \.self) { postId in
                    savedPostRow(postId: postId)
                }
            }
        }
    }
    
    // MARK: - User State Section
    
    private var userStateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "User Interaction State", count: nil)
            
            // Current User Info
            infoCard(
                title: "Current User",
                items: [
                    ("User ID", Auth.auth().currentUser?.uid ?? "Anonymous"),
                    ("Display Name", interactionsService.cachedUserDisplayName ?? "Not loaded"),
                    ("Email", Auth.auth().currentUser?.email ?? "Not set")
                ]
            )
            
            // User Lightbulbs
            infoCard(
                title: "💡 Lightbulbed Posts",
                items: [
                    ("Total", "\(interactionsService.userLightbulbedPosts.count)"),
                    ("Post IDs", interactionsService.userLightbulbedPosts.isEmpty ? "None" : Array(interactionsService.userLightbulbedPosts).prefix(3).joined(separator: ", "))
                ]
            )
            
            // User Amens
            infoCard(
                title: "🙏 Amened Posts",
                items: [
                    ("Total", "\(interactionsService.userAmenedPosts.count)"),
                    ("Post IDs", interactionsService.userAmenedPosts.isEmpty ? "None" : Array(interactionsService.userAmenedPosts).prefix(3).joined(separator: ", "))
                ]
            )
            
            // User Reposts
            infoCard(
                title: "🔄 Reposted Posts",
                items: [
                    ("Total", "\(interactionsService.userRepostedPosts.count)"),
                    ("Post IDs", interactionsService.userRepostedPosts.isEmpty ? "None" : Array(interactionsService.userRepostedPosts).prefix(3).joined(separator: ", "))
                ]
            )
            
            // Saved Posts
            infoCard(
                title: "🔖 Saved Posts",
                items: [
                    ("Total", "\(savedPostsService.savedPostIds.count)"),
                    ("Post IDs", savedPostsService.savedPostIds.isEmpty ? "None" : Array(savedPostsService.savedPostIds).prefix(3).joined(separator: ", "))
                ]
            )
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, count: Int?) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            
            if let count = count {
                Spacer()
                Text("\(count) posts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
    }
    
    private func interactionRow(
        postId: String,
        count: Int,
        icon: String,
        color: Color,
        isUserInteracted: Bool
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(postId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                
                Text("\(count) total")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isUserInteracted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func emptyState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    private func infoCard(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top) {
                        Text(item.0 + ":")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        
                        Text(item.1)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func savedPostRow(postId: String) -> some View {
        HStack {
            Image(systemName: "bookmark.fill")
                .foregroundColor(.orange)
            
            Text(postId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func refresh() async {
        isRefreshing = true
        
        // Small delay to show animation
        try? await Task.sleep(for: .milliseconds(500))
        
        isRefreshing = false
        
        print("🔄 Debug view refreshed")
        print("   - Lightbulbs: \(interactionsService.postLightbulbs.count)")
        print("   - Amens: \(interactionsService.postAmens.count)")
        print("   - Comments: \(interactionsService.postComments.count)")
        print("   - Reposts: \(interactionsService.postReposts.count)")
        print("   - Saved: \(savedPostsService.savedPostIds.count)")
    }
}

// MARK: - Preview

#Preview {
    PostInteractionsDebugView()
}
