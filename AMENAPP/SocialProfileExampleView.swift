//
//  SocialProfileExampleView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

/// Example view demonstrating how to use the new social features
struct SocialProfileExampleView: View {
    @StateObject private var userService = UserService()
    @StateObject private var socialService = SocialService.shared
    
    @State private var showProfilePicker = false
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.08),
                        Color(red: 0.12, green: 0.10, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Profile Picture Section
                        VStack(spacing: 20) {
                            // Profile Image
                            ZStack(alignment: .bottomTrailing) {
                                if let imageURL = userService.currentUser?.profileImageURL,
                                   let url = URL(string: imageURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                            )
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 3
                                            )
                                    )
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.orange.opacity(0.6), Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 140, height: 140)
                                        .overlay(
                                            Text(userService.currentUser?.initials ?? "??")
                                                .font(.custom("OpenSans-Bold", size: 48))
                                                .foregroundStyle(.white)
                                        )
                                }
                                
                                // Edit button
                                Button {
                                    showProfilePicker = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                            .shadow(color: .orange.opacity(0.5), radius: 8, y: 4)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            
                            // User Info
                            VStack(spacing: 8) {
                                Text(userService.currentUser?.displayName ?? "Loading...")
                                    .font(.custom("OpenSans-Bold", size: 28))
                                    .foregroundStyle(.white)
                                
                                Text("@\(userService.currentUser?.username ?? "")")
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                if let bio = userService.currentUser?.bio {
                                    Text(bio)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.top, 20)
                        
                        // Follower/Following Stats
                        HStack(spacing: 40) {
                            Button {
                                showFollowersList = true
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(userService.currentUser?.followersCount ?? 0)")
                                        .font(.custom("OpenSans-Bold", size: 24))
                                        .foregroundStyle(.white)
                                    
                                    Text("Followers")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 4, height: 4)
                            
                            Button {
                                showFollowingList = true
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(userService.currentUser?.followingCount ?? 0)")
                                        .font(.custom("OpenSans-Bold", size: 24))
                                        .foregroundStyle(.white)
                                    
                                    Text("Following")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 4, height: 4)
                            
                            VStack(spacing: 4) {
                                Text("\(userService.currentUser?.postsCount ?? 0)")
                                    .font(.custom("OpenSans-Bold", size: 24))
                                    .foregroundStyle(.white)
                                
                                Text("Posts")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.horizontal, 20)
                        
                        // Example: Follow Another User
                        VStack(spacing: 16) {
                            Text("Example: Follow Other Users")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white)
                            
                            // Sample users to follow
                            ForEach(sampleUsers) { user in
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Text(user.initials)
                                                .font(.custom("OpenSans-Bold", size: 18))
                                                .foregroundStyle(.white)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.displayName)
                                            .font(.custom("OpenSans-Bold", size: 16))
                                            .foregroundStyle(.white)
                                        
                                        Text("@\(user.username)")
                                            .font(.custom("OpenSans-Regular", size: 13))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                    
                                    if let userId = user.id {
                                        SocialFollowButton(userId: userId, username: user.username)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProfilePicker) {
                ProfilePicturePicker { imageURL in
                    print("✅ Profile picture uploaded: \(imageURL)")
                    // Refresh user data
                    Task {
                        await userService.fetchCurrentUser()
                    }
                }
            }
            .sheet(isPresented: $showFollowersList) {
                if let userId = userService.currentUser?.id {
                    SocialFollowersListView(userId: userId, listType: .followers)
                }
            }
            .sheet(isPresented: $showFollowingList) {
                if let userId = userService.currentUser?.id {
                    SocialFollowersListView(userId: userId, listType: .following)
                }
            }
            .task {
                await userService.fetchCurrentUser()
            }
        }
    }
    
    // Sample users for demonstration
    private var sampleUsers: [UserModel] {
        [
            UserModel(
                id: "user1",
                email: "john@example.com",
                displayName: "John Disciple",
                username: "johndisciple"
            ),
            UserModel(
                id: "user2",
                email: "sarah@example.com",
                displayName: "Sarah Grace",
                username: "sarahgrace"
            ),
            UserModel(
                id: "user3",
                email: "david@example.com",
                displayName: "David Pastor",
                username: "davidpastor"
            )
        ]
    }
}

#Preview {
    SocialProfileExampleView()
}
