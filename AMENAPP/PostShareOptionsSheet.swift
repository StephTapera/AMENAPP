//
//  PostShareOptionsSheet.swift
//  AMENAPP
//
//  Share options for posts - supports sending in messages and external sharing
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Glass Dialog Button
private struct GlassDialogButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.6))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.black)
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.black.opacity(0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post Share Options Sheet
struct PostShareOptionsSheet: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @State private var showShareCardSheet = false
    @State private var showMessageCompose = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("Share Post")
                        .font(AMENFont.semiBold(18))
                        .foregroundStyle(.black)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Choose how you want to share this post.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    GlassDialogButton(title: "Send in Message", subtitle: "Share with a friend", systemImage: "paperplane") {
                        showMessageCompose = true
                    }

                    GlassDialogButton(title: "Instagram Story", subtitle: "Share as a Story card", systemImage: "camera.fill") {
                        showShareCardSheet = true
                    }

                    GlassDialogButton(title: "Share Externally", subtitle: "Share outside the app", systemImage: "square.and.arrow.up") {
                        showShareCardSheet = true
                    }
                }

                Button("Cancel") {
                    dismiss()
                }
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.black)
                .padding(.top, 4)
            }
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.7),
                                    Color.white.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 12)
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showMessageCompose) {
            MessageComposeView(post: post)
        }
        .fullScreenCover(isPresented: $showShareCardSheet) {
            AMENShareSheet(payload: makeSharePayload(), isPresented: $showShareCardSheet)
        }
    }
    
    private func makeSharePayload() -> AMENSharePayload {
        let isCarousel = (post.imageURLs?.count ?? 0) > 1
        let hasPhoto = (post.imageURLs?.first?.isEmpty == false)
        let postType: AMENSharePostType
        switch post.category {
        case .testimonies:
            postType = .testimony
        case .prayer:
            postType = .prayer
        case .openTable, .tip, .funFact:
            if let verseRef = post.verseReference, !verseRef.isEmpty {
                postType = .verse
            } else if isCarousel {
                postType = .carousel
            } else if hasPhoto {
                postType = .photo
            } else {
                postType = .text
            }
        }
        return AMENSharePayload(
            postType: postType,
            authorName: post.authorName,
            authorInitials: post.authorInitials,
            captionText: post.content,
            verseReference: post.verseReference,
            categoryLabel: post.category.displayName,
            imageData: nil,
            thumbnailData: nil,
            churchName: post.taggedChurchName ?? post.sharedChurchName,
            timestamp: post.createdAt,
            deepLinkURL: "amenapp://post/\(post.firestoreId)",
            carouselCount: max(post.imageURLs?.count ?? 1, 1),
            videoDuration: nil
        )
    }
}

// MARK: - Message Compose View
/// Lets the user search existing conversations OR followed users and send a post.
struct MessageComposeView: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @ObservedObject private var followService = FollowService.shared

    @State private var searchText = ""
    @State private var sendingId: String? = nil         // in-flight guard (conv id or user id)
    @State private var sentIds: Set<String> = []        // disable after send
    @State private var errorMessage: String? = nil
    @State private var followingUsers: [FollowUserProfile] = []
    @State private var isLoadingUsers = false
    @State private var searchResults: [FollowUserProfile] = []  // live Firestore search
    @State private var isSearching = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Existing accepted conversations matching search
    private var filteredConversations: [ChatConversation] {
        let accepted = messagingService.conversations.filter { $0.status == "accepted" }
        guard !searchText.isEmpty else { return accepted }
        let query = searchText.lowercased()
        return accepted.filter { $0.name.lowercased().contains(query) }
    }

    // People to show: merge Firestore search results + following list (client-filtered), deduplicated
    private var suggestedUsers: [FollowUserProfile] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let conversationUserIds = Set(messagingService.conversations.compactMap { $0.otherParticipantId })
        let currentUserId = Auth.auth().currentUser?.uid ?? ""

        var seen = Set<String>()
        var merged: [FollowUserProfile] = []

        // Firestore results first (already filtered server-side)
        for user in searchResults {
            guard user.id != currentUserId, !conversationUserIds.contains(user.id) else { continue }
            seen.insert(user.id)
            merged.append(user)
        }
        // Followed users (client-side prefix filter) — fills in if Firestore hasn't returned yet
        for user in followingUsers {
            guard !seen.contains(user.id),
                  user.id != currentUserId,
                  !conversationUserIds.contains(user.id),
                  user.displayName.lowercased().contains(query) || user.username.lowercased().contains(query)
            else { continue }
            seen.insert(user.id)
            merged.append(user)
        }
        return merged
    }

    private var hasResults: Bool {
        !filteredConversations.isEmpty || !suggestedUsers.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Post preview banner
                postPreviewBanner

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search people", text: $searchText)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                if messagingService.isLoading || isLoadingUsers || isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if !hasResults && searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.systemScaled(32))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No conversations yet")
                            .foregroundStyle(.secondary)
                        Text("Search by name or username to find someone to send this post to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else if !hasResults {
                    Spacer()
                    Text("No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Existing conversations
                            if !filteredConversations.isEmpty {
                                if !suggestedUsers.isEmpty {
                                    Text("CONVERSATIONS")
                                        .font(AMENFont.bold(11))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 16)
                                        .padding(.bottom, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                VStack(spacing: 0) {
                                    ForEach(Array(filteredConversations.enumerated()), id: \.element.id) { index, conversation in
                                        conversationRow(conversation)
                                        if index < filteredConversations.count - 1 {
                                            Divider().padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                                .padding(.horizontal, 16)
                            }

                            // People (following + search results)
                            if !suggestedUsers.isEmpty {
                                Text("PEOPLE")
                                    .font(AMENFont.bold(11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(spacing: 0) {
                                    ForEach(Array(suggestedUsers.enumerated()), id: \.element.id) { index, user in
                                        userRow(user)
                                        if index < suggestedUsers.count - 1 {
                                            Divider().padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                                .padding(.horizontal, 16)
                            }

                            Spacer(minLength: 32)
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Send Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if messagingService.conversations.isEmpty {
                messagingService.startListeningToConversations()
            }
            loadFollowingUsers()
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchResults = []
            guard newValue.count >= 2 else { return }
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else { return }
                await performSearch(query: newValue)
            }
        }
    }

    // MARK: - Firestore user search
    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        await MainActor.run { isSearching = true }
        let db = Firestore.firestore()
        async let byDisplayName = db.collection("users")
            .whereField("displayNameLowercase", isGreaterThanOrEqualTo: trimmed)
            .whereField("displayNameLowercase", isLessThan: trimmed + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        async let byUsername = db.collection("users")
            .whereField("usernameLowercase", isGreaterThanOrEqualTo: trimmed)
            .whereField("usernameLowercase", isLessThan: trimmed + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        var profiles: [FollowUserProfile] = []
        var seen = Set<String>()
        for snapshot in [(try? await byDisplayName), (try? await byUsername)].compactMap({ $0 }) {
            for doc in snapshot.documents {
                let data = doc.data()
                let uid = doc.documentID
                guard !seen.contains(uid) else { continue }
                seen.insert(uid)
                let displayName = (data["displayName"] as? String) ?? (data["username"] as? String) ?? "User"
                let username = (data["username"] as? String) ?? ""
                let bio = data["bio"] as? String
                let profileImageURL = (data["profileImageURL"] as? String) ?? (data["photoURL"] as? String)
                profiles.append(FollowUserProfile(
                    id: uid,
                    displayName: displayName,
                    username: username,
                    bio: bio,
                    profileImageURL: profileImageURL,
                    followersCount: (data["followersCount"] as? Int) ?? 0,
                    followingCount: (data["followingCount"] as? Int) ?? 0
                ))
            }
        }
        await MainActor.run {
            searchResults = profiles
            isSearching = false
        }
    }

    // MARK: - Load following list
    private func loadFollowingUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        // Use cached list from FollowService if available
        if !followService.followingList.isEmpty {
            followingUsers = followService.followingList
            return
        }
        isLoadingUsers = true
        Task {
            do {
                let users = try await FollowService.shared.fetchFollowing(userId: currentUserId)
                await MainActor.run {
                    followingUsers = users
                    isLoadingUsers = false
                }
            } catch {
                await MainActor.run { isLoadingUsers = false }
            }
        }
    }

    // MARK: - Post preview banner
    private var postPreviewBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(post.content.prefix(80) + (post.content.count > 80 ? "…" : ""))
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Existing conversation row
    @ViewBuilder
    private func conversationRow(_ conversation: ChatConversation) -> some View {
        let isSending = sendingId == conversation.id
        let alreadySent = sentIds.contains(conversation.id)

        HStack(spacing: 12) {
            Circle()
                .fill(conversation.avatarColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(conversation.initials)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.name)
                    .font(.systemScaled(15, weight: .semibold))
                Text(conversation.lastMessage)
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            sendButton(id: conversation.id, isSending: isSending, alreadySent: alreadySent) {
                sendPostToConversation(conversation)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Followed user row (start new conversation)
    @ViewBuilder
    private func userRow(_ user: FollowUserProfile) -> some View {
        let isSending = sendingId == user.id
        let alreadySent = sentIds.contains(user.id)

        HStack(spacing: 12) {
            // Avatar
            if let imageURL = user.profileImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.accentColor.opacity(0.3))
                        .overlay(Text(user.initials).font(.systemScaled(14, weight: .semibold)).foregroundStyle(.white))
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(Text(user.initials).font(.systemScaled(14, weight: .semibold)).foregroundStyle(.white))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.systemScaled(15, weight: .semibold))
                Text("@\(user.username)")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            sendButton(id: user.id, isSending: isSending, alreadySent: alreadySent) {
                sendPostToUser(user)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Shared send button
    @ViewBuilder
    private func sendButton(id: String, isSending: Bool, alreadySent: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !isSending, !alreadySent else { return }
            action()
        } label: {
            if isSending {
                ProgressView().frame(width: 64, height: 32)
            } else if alreadySent {
                Label("Sent", systemImage: "checkmark")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 64, height: 32)
            } else {
                Text("Send")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 32)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
        .disabled(isSending || alreadySent)
    }

    // MARK: - Send to existing conversation
    private func sendPostToConversation(_ conversation: ChatConversation) {
        guard sendingId == nil else { return }
        errorMessage = nil
        sendingId = conversation.id

        let messageId = UUID().uuidString
        let snippet = String(post.content.prefix(200))
        let messageText = "📌 \(post.authorName): \"\(snippet)\"\n\nView post in AMEN →"

        Task {
            do {
                try await messagingService.sendMessage(
                    conversationId: conversation.id,
                    text: messageText,
                    clientMessageId: messageId
                )
                // Tag message as a post share for deep-link
                let db = Firestore.firestore()
                try? await db.collection("conversations").document(conversation.id)
                    .collection("messages").document(messageId)
                    .updateData(["postId": post.firestoreId, "messageType": "postShare"])

                await MainActor.run {
                    sentIds.insert(conversation.id)
                    sendingId = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    sendingId = nil
                    errorMessage = "Failed to send. Please try again."
                }
            }
        }
    }

    // MARK: - Send to a user (get-or-create conversation first)
    private func sendPostToUser(_ user: FollowUserProfile) {
        guard sendingId == nil else { return }
        errorMessage = nil
        sendingId = user.id

        let snippet = String(post.content.prefix(200))
        let messageText = "📌 \(post.authorName): \"\(snippet)\"\n\nView post in AMEN →"

        Task {
            do {
                let conversationId = try await messagingService.getOrCreateConversation(
                    with: user.id,
                    participantName: user.displayName
                )
                let messageId = UUID().uuidString
                try await messagingService.sendMessage(
                    conversationId: conversationId,
                    text: messageText,
                    clientMessageId: messageId
                )
                let db = Firestore.firestore()
                try? await db.collection("conversations").document(conversationId)
                    .collection("messages").document(messageId)
                    .updateData(["postId": post.firestoreId, "messageType": "postShare"])

                await MainActor.run {
                    sentIds.insert(user.id)
                    sendingId = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    sendingId = nil
                    errorMessage = "Failed to send. Please try again."
                }
            }
        }
    }
}
