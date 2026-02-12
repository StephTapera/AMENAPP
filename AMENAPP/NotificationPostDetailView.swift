//
//  NotificationPostDetailView.swift
//  AMENAPP
//
//  Navigation destination for viewing posts from notifications
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

struct NotificationPostDetailView: View {
    let postId: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = NotificationPostViewModel()
    @StateObject private var interactionsService = PostInteractionsService.shared
    @State private var showComments = false
    @State private var commentText = ""
    @FocusState private var isCommentFocused: Bool
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading post...")
            } else if let post = viewModel.post {
                ScrollView {
                    VStack(spacing: 20) {
                        // Post Content
                        PostContentCard(post: post)
                        
                        // Interaction Stats
                        InteractionStatsView(
                            amenCount: interactionsService.postAmens[postId] ?? 0,
                            commentCount: interactionsService.postComments[postId] ?? 0,
                            repostCount: interactionsService.postReposts[postId] ?? 0,
                            lightbulbCount: interactionsService.postLightbulbs[postId] ?? 0
                        )
                        .padding(.horizontal)
                        
                        // Quick Actions
                        QuickInteractionButtons(
                            postId: postId,
                            hasAmened: interactionsService.userAmenedPosts.contains(postId),
                            hasLightbulbed: interactionsService.userLightbulbedPosts.contains(postId),
                            onAmen: {
                                Task {
                                    try? await interactionsService.toggleAmen(postId: postId)
                                }
                            },
                            onComment: {
                                showComments.toggle()
                                isCommentFocused = true
                            },
                            onLightbulb: {
                                Task {
                                    try? await interactionsService.toggleLightbulb(postId: postId)
                                }
                            }
                        )
                        .padding(.horizontal)
                        
                        // Comments Section
                        CommentsSection(postId: postId)
                    }
                    .padding(.vertical)
                }
            } else {
                errorView
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showComments {
                commentInputView
            }
        }
        .task {
            await viewModel.loadPost(postId: postId)
            interactionsService.observePostInteractions(postId: postId)
        }
        .onDisappear {
            interactionsService.stopObservingPost(postId: postId)
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Post Unavailable")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("This post may have been deleted")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                Task {
                    await viewModel.loadPost(postId: postId)
                }
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
    }
    
    private var commentInputView: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $commentText)
                .textFieldStyle(.roundedBorder)
                .focused($isCommentFocused)
            
            Button(action: sendComment) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(commentText.isEmpty ? Color.gray : Color.blue)
                    )
            }
            .disabled(commentText.isEmpty)
        }
        .padding()
        .background(
            Rectangle()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        )
    }
    
    private func sendComment() {
        guard !commentText.isEmpty else { return }
        
        Task {
            do {
                // Get current user info
                guard let currentUser = await getCurrentUserInfo() else { return }
                
                _ = try await interactionsService.addComment(
                    postId: postId,
                    content: commentText,
                    authorInitials: currentUser.initials,
                    authorUsername: currentUser.username,
                    authorProfileImageURL: currentUser.profileImageURL
                )
                
                // Clear input
                commentText = ""
                isCommentFocused = false
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                print("❌ Failed to send comment: \(error)")
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func getCurrentUserInfo() async -> (initials: String, username: String, profileImageURL: String?)? {
        guard let userId = FirebaseAuth.Auth.auth().currentUser?.uid else { return nil }
        
        do {
            let doc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return nil }
            
            let displayName = data["displayName"] as? String ?? "User"
            let username = data["username"] as? String ?? displayName
            let profileImageURL = data["profileImageURL"] as? String
            
            let components = displayName.split(separator: " ")
            let initials: String
            if components.count >= 2 {
                initials = "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            } else {
                initials = String(displayName.prefix(2)).uppercased()
            }
            
            return (initials, username, profileImageURL)
        } catch {
            print("❌ Failed to get user info: \(error)")
            return nil
        }
    }
}

// MARK: - Post Content Card

struct PostContentCard: View {
    let post: NotificationPost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Author info
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(post.authorInitials)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    Text(post.timeAgo())
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
            
            // Category badge
            Text(post.category.capitalized)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Interaction Stats View

struct InteractionStatsView: View {
    let amenCount: Int
    let commentCount: Int
    let repostCount: Int
    let lightbulbCount: Int
    
    var body: some View {
        HStack(spacing: 24) {
            StatItem(icon: "hands.sparkles.fill", count: amenCount, color: .blue)
            StatItem(icon: "bubble.left.fill", count: commentCount, color: .purple)
            StatItem(icon: "lightbulb.fill", count: lightbulbCount, color: .yellow)
            StatItem(icon: "arrow.2.squarepath", count: repostCount, color: .green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
    
    struct StatItem: View {
        let icon: String
        let count: Int
        let color: Color
        
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                
                Text("\(count)")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Quick Interaction Buttons

struct QuickInteractionButtons: View {
    let postId: String
    let hasAmened: Bool
    let hasLightbulbed: Bool
    let onAmen: () -> Void
    let onComment: () -> Void
    let onLightbulb: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            InteractionButton(
                icon: "hands.sparkles.fill",
                label: "Amen",
                isActive: hasAmened,
                activeColor: .blue,
                action: onAmen
            )
            
            InteractionButton(
                icon: "bubble.left.fill",
                label: "Comment",
                isActive: false,
                activeColor: .purple,
                action: onComment
            )
            
            InteractionButton(
                icon: "lightbulb.fill",
                label: "Light",
                isActive: hasLightbulbed,
                activeColor: .yellow,
                action: onLightbulb
            )
        }
    }
    
    struct InteractionButton: View {
        let icon: String
        let label: String
        let isActive: Bool
        let activeColor: Color
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text(label)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? activeColor.opacity(0.1) : Color.gray.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Comments Section

struct CommentsSection: View {
    let postId: String
    @StateObject private var interactionsService = PostInteractionsService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal)
            
            if let comments = interactionsService.postCommentsData[postId], !comments.isEmpty {
                ForEach(comments) { comment in
                    NotificationCommentRow(comment: comment)
                }
            } else {
                Text("No comments yet")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
    }
}

struct NotificationCommentRow: View {
    let comment: RealtimeComment
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            if let imageURL = comment.authorProfileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .overlay(
                            Text(comment.authorInitials)
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(.blue)
                        )
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(.blue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.custom("OpenSans-Bold", size: 14))
                    
                    Text(comment.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - View Model

@MainActor
class NotificationPostViewModel: ObservableObject {
    @Published var post: NotificationPost?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let db = Firestore.firestore()
    
    func loadPost(postId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let doc = try await db.collection("posts").document(postId).getDocument()
            guard let data = doc.data() else {
                error = NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Post not found"])
                return
            }
            
            post = NotificationPost(
                id: postId,
                content: data["content"] as? String ?? "",
                authorId: data["authorId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "Unknown",
                category: data["category"] as? String ?? "general",
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        } catch {
            self.error = error
            print("❌ Failed to load post: \(error)")
        }
    }
}

// MARK: - Post Model

struct NotificationPost {
    let id: String
    let content: String
    let authorId: String
    let authorName: String
    let category: String
    let createdAt: Date
    
    var authorInitials: String {
        let components = authorName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(authorName.prefix(2)).uppercased()
    }
    
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}



#Preview("Notification Post Detail") {
    NavigationStack {
        NotificationPostDetailView(postId: "sample123")
    }
}
