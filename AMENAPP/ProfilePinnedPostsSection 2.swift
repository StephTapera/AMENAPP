//
//  ProfilePinnedPostsSection.swift
//  AMENAPP
//
//  Pinned posts section for user profiles
//  Displays up to 3 pinned posts at top of profile
//

import SwiftUI
import FirebaseFirestore

struct ProfilePinnedPostsSection: View {
    @EnvironmentObject private var services: PostCardServices
    @State private var pinnedPosts: [Post] = []
    @State private var isExpanded = true
    @State private var isLoading = true
    
    let userId: String
    let isCurrentUser: Bool
    
    var body: some View {
        if !pinnedPosts.isEmpty || isLoading {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                Button {
                    withAnimation(AppAnimation.stateChange) {
                        isExpanded.toggle()
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text("Pinned")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        if pinnedPosts.count > 0 {
                            Text("\(pinnedPosts.count)")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(.tertiary)
                                )
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                // Posts
                if isExpanded {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        ForEach(pinnedPosts, id: \.firestoreId) { post in
                            PostCard(
                                post: post,
                                isUserPost: post.authorId == userId
                            )
                            .padding(.horizontal)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
            .task {
                await loadPinnedPosts()
            }
        }
    }
    
    // MARK: - Loading
    
    private func loadPinnedPosts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let posts = try await ProfilePinnedPostService.shared.getPinnedPosts(for: userId)
            
            await MainActor.run {
                withAnimation(AppAnimation.fade) {
                    pinnedPosts = posts
                }
            }
            
            print("✅ Loaded \(posts.count) pinned posts for user: \(userId)")
        } catch {
            print("❌ Failed to load pinned posts: \(error)")
            pinnedPosts = []
        }
    }
}

// MARK: - Pinned Post Service

actor ProfilePinnedPostService {
    static let shared = ProfilePinnedPostService()
    
    private var pinnedPostsCache: [String: [Post]] = [:]
    private let maxPinnedPosts = 3
    
    private init() {}
    
    /// Get pinned posts for a user
    func getPinnedPosts(for userId: String) async throws -> [Post] {
        // Check cache first
        if let cached = pinnedPostsCache[userId] {
            return cached
        }
        
        // Fetch from Firestore
        let posts = try await fetchPinnedPostsFromFirestore(userId: userId)
        pinnedPostsCache[userId] = posts
        return posts
    }
    
    /// Pin a post for a user
    func pinPost(_ postId: String, for userId: String) async throws {
        let pinnedPosts = try await getPinnedPosts(for: userId)
        
        guard pinnedPosts.count < maxPinnedPosts else {
            throw PinnedPostError.maxPinnedReached
        }
        
        guard !pinnedPosts.contains(where: { $0.firestoreId == postId }) else {
            throw PinnedPostError.alreadyPinned
        }
        
        // Update Firestore
        try await savePinnedPostToFirestore(postId: postId, userId: userId)
        
        // Clear cache to force refresh
        pinnedPostsCache[userId] = nil
    }
    
    /// Unpin a post for a user
    func unpinPost(_ postId: String, for userId: String) async throws {
        // Remove from Firestore
        try await removePinnedPostFromFirestore(postId: postId, userId: userId)
        
        // Clear cache to force refresh
        pinnedPostsCache[userId] = nil
    }
    
    /// Check if a post is pinned
    func isPostPinned(_ postId: String, for userId: String) async -> Bool {
        guard let posts = try? await getPinnedPosts(for: userId) else {
            return false
        }
        return posts.contains(where: { $0.firestoreId == postId })
    }
    
    // MARK: - Firestore Operations
    
    private func fetchPinnedPostsFromFirestore(userId: String) async throws -> [Post] {
        let db = Firestore.firestore()
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("pinnedPosts")
            .order(by: "pinnedAt", descending: true)
            .limit(to: maxPinnedPosts)
            .getDocuments()
        
        var posts: [Post] = []
        
        for doc in snapshot.documents {
            if let postId = doc.data()["postId"] as? String {
                // Fetch the actual post
                if let post = try? await fetchPost(postId: postId) {
                    posts.append(post)
                }
            }
        }
        
        return posts
    }
    
    private func savePinnedPostToFirestore(postId: String, userId: String) async throws {
        let db = Firestore.firestore()
        
        try await db.collection("users")
            .document(userId)
            .collection("pinnedPosts")
            .document(postId)
            .setData([
                "postId": postId,
                "pinnedAt": FieldValue.serverTimestamp()
            ])
    }
    
    private func removePinnedPostFromFirestore(postId: String, userId: String) async throws {
        let db = Firestore.firestore()
        
        try await db.collection("users")
            .document(userId)
            .collection("pinnedPosts")
            .document(postId)
            .delete()
    }
    
    private func fetchPost(postId: String) async throws -> Post? {
        let db = Firestore.firestore()
        
        let snapshot = try await db.collection("posts")
            .document(postId)
            .getDocument()
        
        guard snapshot.exists else { return nil }
        
        return try? await MainActor.run { try snapshot.data(as: Post.self) }
    }
}

// MARK: - Errors

enum PinnedPostError: LocalizedError {
    case maxPinnedReached
    case alreadyPinned
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .maxPinnedReached:
            return "You can only pin up to 3 posts"
        case .alreadyPinned:
            return "This post is already pinned"
        case .notFound:
            return "Post not found"
        }
    }
}

// MARK: - Usage

/*
 ADD TO PROFILEVIEW:
 
 ```swift
 VStack {
     // Profile header
     ProfileHeader(...)
     
     // Pinned posts section
     ProfilePinnedPostsSection(
         userId: user.id,
         isCurrentUser: user.id == currentUserId
     )
     .environmentObject(PostCardServices.shared)
     
     // Rest of profile content
 }
 ```
 
 ADD PIN/UNPIN TO POSTCARD MENU:
 
 ```swift
 if isCurrentUser {
     Button {
         Task {
             if isPinned {
                 try? await services.pinned.unpinPost(post.firestoreId, for: currentUserId)
             } else {
                 try? await services.pinned.pinPost(post.firestoreId, for: currentUserId)
             }
         }
     } label: {
         Label(isPinned ? "Unpin from Profile" : "Pin to Profile", 
               systemImage: isPinned ? "pin.slash" : "pin")
     }
 }
 ```
 */
