//
//  NotificationUserProfileView.swift
//  AMENAPP
//
//  Navigation destination for viewing user profiles from notifications
//

import SwiftUI
import FirebaseFirestore
import Combine

struct NotificationUserProfileView: View {
    let userId: String
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = NotificationProfileViewModel()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading profile...")
            } else if let profile = viewModel.profile {
                ProfileContentView(profile: profile)
            } else {
                errorView
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile(userId: userId)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
            Button("Retry") {
                Task {
                    await viewModel.loadProfile(userId: userId)
                }
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Unable to load profile")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("This user's profile is unavailable")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                Task {
                    await viewModel.loadProfile(userId: userId)
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
}

// MARK: - Profile Content View

struct ProfileContentView: View {
    let profile: NotificationProfileData
    
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var isProcessing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    // Profile Image
                    if let imageURL = profile.profileImageURL, !imageURL.isEmpty {
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
                                EmptyView()
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
                    
                    // Name and Username
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
                    
                    // Stats
                    HStack(spacing: 32) {
                        ProfileStatView(count: profile.postsCount, label: "Posts")
                        ProfileStatView(count: profile.followersCount, label: "Followers")
                        ProfileStatView(count: profile.followingCount, label: "Following")
                    }
                    
                    // Follow Button
                    Button {
                        toggleFollow()
                    } label: {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(isFollowing ? .primary : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isFollowing ? Color.gray.opacity(0.2) : Color.blue)
                            )
                    }
                    .disabled(isProcessing)
                    .padding(.horizontal)
                }
                .padding(.top)
            }
        }
        .task {
            await checkFollowingStatus()
        }
    }
    
    private func toggleFollow() {
        isProcessing = true
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(userId: profile.id)
                } else {
                    try await followService.followUser(userId: profile.id)
                }
                isFollowing.toggle()
            } catch {
                print("❌ Failed to toggle follow: \(error)")
            }
            isProcessing = false
        }
    }
    
    private func checkFollowingStatus() async {
        isFollowing = await followService.isFollowing(userId: profile.id)
    }
}

struct ProfileStatView: View {
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
class NotificationProfileViewModel: ObservableObject {
    @Published var profile: NotificationProfileData?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let db = Firestore.firestore()
    
    func loadProfile(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else {
                error = NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
                return
            }
            
            profile = NotificationProfileData(
                id: userId,
                displayName: data["displayName"] as? String ?? "Unknown",
                username: data["username"] as? String,
                bio: data["bio"] as? String,
                profileImageURL: data["profileImageURL"] as? String,
                postsCount: data["postsCount"] as? Int ?? 0,
                followersCount: data["followersCount"] as? Int ?? 0,
                followingCount: data["followingCount"] as? Int ?? 0
            )
        } catch {
            self.error = error
            print("❌ Failed to load profile: \(error)")
        }
    }
}

// MARK: - Profile Model

struct NotificationProfileData {
    let id: String
    let displayName: String
    let username: String?
    let bio: String?
    let profileImageURL: String?
    let postsCount: Int
    let followersCount: Int
    let followingCount: Int
    
    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

#Preview {
    NavigationStack {
        NotificationUserProfileView(userId: "sample123")
    }
}
