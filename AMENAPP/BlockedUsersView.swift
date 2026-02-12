//
//  BlockedUsersView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI

struct BlockedUsersView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var blockService = BlockService.shared
    @State private var showUnblockConfirmation = false
    @State private var userToUnblock: BlockedUserProfile?
    
    var body: some View {
        NavigationStack {
            ZStack {
                if blockService.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if blockService.blockedUsersList.isEmpty {
                    emptyStateView
                } else {
                    blockedUsersList
                }
            }
            .navigationTitle("Blocked Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .confirmationDialog(
                "Unblock @\(userToUnblock?.username ?? "")?",
                isPresented: $showUnblockConfirmation,
                titleVisibility: .visible
            ) {
                Button("Unblock", role: .destructive) {
                    if let user = userToUnblock {
                        unblockUser(user)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They will be able to follow you and view your posts again.")
            }
            .onAppear {
                Task {
                    await blockService.loadBlockedUsers()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Blocked Users")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("Users you block will appear here.\nBlocked users can't follow you or see your posts.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }
    
    private var blockedUsersList: some View {
        List {
            ForEach(blockService.blockedUsersList) { user in
                HStack(spacing: 12) {
                    // Avatar
                    if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                        AsyncImage(url: URL(string: profileImageURL)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            default:
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(user.initials)
                                            .font(.custom("OpenSans-Bold", size: 16))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(user.initials)
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                            )
                    }
                    
                    // User info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("@\(user.username)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Unblock button
                    Button("Unblock") {
                        userToUnblock = user
                        showUnblockConfirmation = true
                    }
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.blue)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
    
    private func unblockUser(_ user: BlockedUserProfile) {
        Task {
            do {
                try await blockService.unblockUser(userId: user.id)
                print("✅ Unblocked @\(user.username)")
            } catch {
                print("❌ Failed to unblock user: \(error)")
            }
        }
    }
}

#Preview("Blocked Users") {
    NavigationStack {
        BlockedUsersView()
    }
}
