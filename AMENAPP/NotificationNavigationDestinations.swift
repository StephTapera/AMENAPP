//
//  NotificationNavigationDestinations.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Navigation destination views for notification taps
//

import SwiftUI
import FirebaseFirestore

// MARK: - Navigation Destination Enum

enum NotificationDestination: Hashable {
    case post(postId: String)
    case profile(userId: String)
    
    var id: String {
        switch self {
        case .post(let postId):
            return "post_\(postId)"
        case .profile(let userId):
            return "profile_\(userId)"
        }
    }
}

// MARK: - Post Detail View (Placeholder - Replace with your actual implementation)

struct NotificationPostDetailView: View {
    let postId: String
    @StateObject private var viewModel = PostDetailViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let post = viewModel.post {
                postContentView(post)
            } else {
                notFoundView
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPost(postId: postId)
        }
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading post...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error State
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            Text("Error Loading Post")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(error)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task {
                    await viewModel.loadPost(postId: postId)
                }
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
    }
    
    // MARK: - Not Found State
    
    private var notFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text("Post Not Found")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("This post may have been deleted or is no longer available")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.blue)
            }
        }
        .padding()
    }
    
    // MARK: - Post Content View
    
    private func postContentView(_ post: PostData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Author info
                HStack(spacing: 12) {
                    // Avatar
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(post.authorInitials)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.blue)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        Text(post.timestamp.formatted(.relative(presentation: .named)))
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Post content
                Text(post.content)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.primary)
                
                Divider()
                
                // Post stats
                HStack(spacing: 30) {
                    Label("\(post.amenCount)", systemImage: "hands.sparkles.fill")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                    
                    Label("\(post.commentCount)", systemImage: "bubble.left.fill")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.purple)
                }
                
                // TODO: Add comments section, reactions, etc.
                // For now, this is a placeholder
            }
            .padding()
        }
    }
}

// MARK: - Post Detail View Model

@MainActor
class PostDetailViewModel: ObservableObject {
    @Published var post: PostData?
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    
    func loadPost(postId: String) async {
        isLoading = true
        error = nil
        
        do {
            let doc = try await db.collection("posts").document(postId).getDocument()
            
            guard doc.exists else {
                post = nil
                isLoading = false
                return
            }
            
            guard let data = doc.data() else {
                error = "Unable to parse post data"
                isLoading = false
                return
            }
            
            // Parse post data
            post = PostData(
                id: doc.documentID,
                authorId: data["userId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "Unknown",
                content: data["content"] as? String ?? "",
                timestamp: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                amenCount: data["amenCount"] as? Int ?? 0,
                commentCount: data["commentCount"] as? Int ?? 0
            )
            
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Post Data Model

struct PostData {
    let id: String
    let authorId: String
    let authorName: String
    let content: String
    let timestamp: Date
    let amenCount: Int
    let commentCount: Int
    
    var authorInitials: String {
        let components = authorName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(authorName.prefix(2)).uppercased()
    }
}

// MARK: - User Profile View (Placeholder - Replace with your actual implementation)

struct NotificationUserProfileView: View {
    let userId: String
    @StateObject private var viewModel = UserProfileViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let profile = viewModel.profile {
                profileContentView(profile)
            } else {
                notFoundView
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile(userId: userId)
        }
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading profile...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error State
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            Text("Error Loading Profile")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(error)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task {
                    await viewModel.loadProfile(userId: userId)
                }
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding()
    }
    
    // MARK: - Not Found State
    
    private var notFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text("Profile Not Found")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("This user may have deleted their account or is no longer available")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.blue)
            }
        }
        .padding()
    }
    
    // MARK: - Profile Content View
    
    private func profileContentView(_ profile: UserProfileData) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    // Avatar
                    if let imageURL = profile.imageURL, !imageURL.isEmpty {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            case .failure, .empty:
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Text(profile.initials)
                                            .font(.custom("OpenSans-Bold", size: 36))
                                            .foregroundStyle(.blue)
                                    )
                            @unknown default:
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 100, height: 100)
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(profile.initials)
                                    .font(.custom("OpenSans-Bold", size: 36))
                                    .foregroundStyle(.blue)
                            )
                    }
                    
                    // Name and username
                    VStack(spacing: 4) {
                        Text(profile.displayName)
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        if let username = profile.username {
                            Text("@\(username)")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Bio
                    if let bio = profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // Stats
                HStack(spacing: 40) {
                    VStack(spacing: 4) {
                        Text("\(profile.followersCount)")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Followers")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(profile.followingCount)")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Following")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(profile.postCount)")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Posts")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.08))
                )
                
                // TODO: Add follow button, posts feed, etc.
                // For now, this is a placeholder
            }
            .padding()
        }
    }
}

// MARK: - User Profile View Model

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var profile: UserProfileData?
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    
    func loadProfile(userId: String) async {
        isLoading = true
        error = nil
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            
            guard doc.exists else {
                profile = nil
                isLoading = false
                return
            }
            
            guard let data = doc.data() else {
                error = "Unable to parse profile data"
                isLoading = false
                return
            }
            
            // Parse profile data
            profile = UserProfileData(
                id: doc.documentID,
                displayName: data["displayName"] as? String ?? "Unknown",
                username: data["username"] as? String,
                bio: data["bio"] as? String,
                imageURL: data["profileImageURL"] as? String,
                followersCount: data["followersCount"] as? Int ?? 0,
                followingCount: data["followingCount"] as? Int ?? 0,
                postCount: data["postCount"] as? Int ?? 0
            )
            
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - User Profile Data Model

struct UserProfileData {
    let id: String
    let displayName: String
    let username: String?
    let bio: String?
    let imageURL: String?
    let followersCount: Int
    let followingCount: Int
    let postCount: Int
    
    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}
