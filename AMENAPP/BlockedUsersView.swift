//
//  BlockedUsersView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI

struct BlockedUsersView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var blockService = BlockService.shared
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
                    .font(AMENFont.semiBold(16))
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
                .font(.systemScaled(60))
                .foregroundStyle(.secondary)

            Text("No Blocked Users")
                .font(AMENFont.bold(20))

            Text("Users you block will appear here.\nBlocked users can't follow you or see your posts.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 60)
    }

    private var blockedUsersList: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("BLOCKED ACCOUNTS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(blockService.blockedUsersList.enumerated()), id: \.element.id) { index, user in
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
                                                    .font(AMENFont.bold(16))
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
                                            .font(AMENFont.bold(16))
                                            .foregroundStyle(.white)
                                    )
                            }

                            // User info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(AMENFont.semiBold(15))
                                Text("@\(user.username)")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Unblock button
                            Button("Unblock") {
                                userToUnblock = user
                                showUnblockConfirmation = true
                            }
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < blockService.blockedUsersList.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Blocked users cannot see your posts, follow you, or send you messages.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func unblockUser(_ user: BlockedUserProfile) {
        Task {
            do {
                try await blockService.unblockUser(userId: user.id)
                dlog("✅ Unblocked @\(user.username)")
            } catch {
                dlog("❌ Failed to unblock user: \(error)")
            }
        }
    }
}

#Preview("Blocked Users") {
    NavigationStack {
        BlockedUsersView()
    }
}
