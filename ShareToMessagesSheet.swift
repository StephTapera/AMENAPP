//
//  ShareToMessagesSheet.swift
//  AMENAPP
//
//  Share post to other users through messages
//

import SwiftUI
import FirebaseAuth

struct ShareToMessagesSheet: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var userService = UserService.shared
    @ObservedObject private var messageService = MessageService.shared
    
    @State private var searchText = ""
    @State private var selectedUserIds: Set<String> = []
    @State private var isLoading = false
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var followingUsers: [UserModel] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Selected users chips
                if !selectedUserIds.isEmpty {
                    selectedUsersChips
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                }
                
                // Users list
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredUsers.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredUsers) { user in
                                userRow(user)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleUser(user.id)
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                    }
                                
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendToSelectedUsers()
                    }
                    .disabled(selectedUserIds.isEmpty || isSending)
                    .fontWeight(.semibold)
                }
            }
            .alert("Sent!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Post shared with \(selectedUserIds.count) \(selectedUserIds.count == 1 ? "person" : "people")")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
        .task {
            await loadFollowingUsers()
        }
    }
    
    // MARK: - Views
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search people", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var selectedUsersChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedUserIds), id: \.self) { userId in
                    if let user = followingUsers.first(where: { $0.id == userId }) {
                        selectedUserChip(user: user)
                    }
                }
            }
        }
    }
    
    private func selectedUserChip(user: UserModel) -> some View {
        HStack(spacing: 6) {
            Text(user.displayName)
                .font(.custom("OpenSans-SemiBold", size: 14))
            
            Button {
                toggleUser(user.id)
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black)
        )
    }
    
    private func userRow(_ user: UserModel) -> some View {
        HStack(spacing: 12) {
            // Profile image or initials
            if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } placeholder: {
                    initialsCircle(user: user)
                }
            } else {
                initialsCircle(user: user)
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Checkbox
            Image(systemName: selectedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(selectedUserIds.contains(user.id) ? .black : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func initialsCircle(user: UserModel) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.white, Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 44, height: 44)
            
            Text(user.initials)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.black)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(searchText.isEmpty ? "No followers yet" : "No results")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text(searchText.isEmpty ? "Follow people to share posts with them" : "Try a different search")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Data
    
    private var filteredUsers: [UserModel] {
        if searchText.isEmpty {
            return followingUsers
        } else {
            let lowercased = searchText.lowercased()
            return followingUsers.filter { user in
                user.displayName.lowercased().contains(lowercased) ||
                user.username.lowercased().contains(lowercased)
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleUser(_ userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
    
    private func loadFollowingUsers() async {
        isLoading = true
        
        // Get following IDs from FollowService
        let followingIds = Array(followService.following)
        
        // Fetch user profiles
        var users: [UserModel] = []
        for userId in followingIds {
            do {
                if let user = try await userService.fetchUserProfile(userId: userId) {
                    users.append(user)
                }
            } catch {
                dlog("⚠️ Failed to fetch user \(userId): \(error)")
            }
        }
        
        await MainActor.run {
            followingUsers = users.sorted { $0.displayName < $1.displayName }
            isLoading = false
        }
    }
    
    private func sendToSelectedUsers() {
        guard !selectedUserIds.isEmpty else { return }
        
        isSending = true
        
        Task {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                await MainActor.run {
                    errorMessage = "Not authenticated"
                    isSending = false
                }
                return
            }
            
            // Generate share message
            let shareMessage = generateShareMessage()
            
            // Send to each selected user
            var successCount = 0
            for recipientId in selectedUserIds {
                do {
                    try await messageService.sendMessage(
                        recipientId: recipientId,
                        content: shareMessage,
                        images: nil
                    )
                    successCount += 1
                } catch {
                    dlog("❌ Failed to send to \(recipientId): \(error)")
                }
            }
            
            await MainActor.run {
                isSending = false
                if successCount > 0 {
                    showSuccess = true
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                } else {
                    errorMessage = "Failed to send messages"
                }
            }
        }
    }
    
    private func generateShareMessage() -> String {
        let postLink = "amenapp://post/\(post.id.uuidString)"
        
        return """
        Shared a post with you:
        
        \(post.content)
        
        — @\(post.authorUsername)
        
        View in AMEN: \(postLink)
        """
    }
}

// MARK: - Preview

#Preview {
    ShareToMessagesSheet(post: Post(
        authorId: "test",
        authorName: "John Doe",
        authorUsername: "johndoe",
        authorInitials: "JD",
        content: "This is a test post",
        category: .openTable,
        timestamp: Date(),
        commentPermissions: .everyone
    ))
}
