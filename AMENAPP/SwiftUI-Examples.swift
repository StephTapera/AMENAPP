//
//  RealtimeDatabaseService.swift
//  AMEN App - SwiftUI Version
//
//  Observable service for SwiftUI views
//
//  ⚠️ WARNING: This file contains example code that may conflict with your project ⚠️
//  Some view and model declarations have been commented out to prevent conflicts.
//  Use the code snippets below as reference, but don't uncomment conflicting types.
//

import SwiftUI
import FirebaseDatabase
import Combine

/*
// This RealtimeDatabaseService may conflict if you have your own implementation
// Uncomment only if you need this specific service

@MainActor
class RealtimeDatabaseService: ObservableObject {
    
    static let shared = RealtimeDatabaseService()
    
    private let rtdb = RealtimeDatabaseManager.shared
    
    // Published properties for SwiftUI
    @Published var unreadMessages: Int = 0
    @Published var unreadNotifications: Int = 0
    
    private var observerKeys: [String] = []
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe unread counts
        let messagesKey = rtdb.observeUnreadMessages { [weak self] count in
            Task { @MainActor in
                self?.unreadMessages = count
            }
        }
        observerKeys.append(messagesKey)
        
        let notificationsKey = rtdb.observeUnreadNotifications { [weak self] count in
            Task { @MainActor in
                self?.unreadNotifications = count
            }
        }
        observerKeys.append(notificationsKey)
    }
    
    deinit {
        for key in observerKeys {
            rtdb.removeObserver(key: key)
        }
    }
}
*/

//
//  PostView.swift
//  SwiftUI Example
//

struct PostView: View {
    let post: Post
    
    @State private var likeCount: Int = 0
    @State private var amenCount: Int = 0
    @State private var commentCount: Int = 0
    @State private var isLiked: Bool = false
    @State private var commentText: String = ""
    @State private var comments: [[String: Any]] = []
    
    private let rtdb = RealtimeDatabaseManager.shared
    private var observerKeys: [String] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Post Header
                HStack {
                    // Use initials instead of photo URL
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(post.authorInitials)
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading) {
                        Text(post.authorName)
                            .font(.headline)
                        Text(post.timeAgo)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // Post Content
                Text(post.content)
                    .padding(.horizontal)
                
                // Interaction Buttons
                HStack(spacing: 32) {
                    // Like Button
                    Button(action: handleLikeTap) {
                        HStack {
                            Image(systemName: isLiked ? "lightbulb.fill" : "lightbulb")
                                .foregroundColor(isLiked ? .yellow : .gray)
                            Text("\(likeCount)")
                        }
                    }
                    
                    // Amen Button
                    Button(action: handleAmenTap) {
                        HStack {
                            Image(systemName: "hands.sparkles")
                            Text("\(amenCount)")
                        }
                    }
                    
                    // Comment Button
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "message")
                            Text("\(commentCount)")
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Comments Section
                ForEach(comments.indices, id: \.self) { index in
                    CommentRow(comment: comments[index])
                }
                
                // Add Comment
                HStack {
                    TextField("Add a comment...", text: $commentText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Send") {
                        handleSendComment()
                    }
                    .disabled(commentText.isEmpty)
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            setupObservers()
            checkLikedStatus()
        }
    }
    
    // MARK: - Actions
    
    private func handleLikeTap() {
        isLiked.toggle()
        
        if isLiked {
            rtdb.likePost(postId: post.id.uuidString) { success in
                if !success {
                    isLiked.toggle()  // Revert on failure
                }
            }
        } else {
            rtdb.unlikePost(postId: post.id.uuidString) { success in
                if !success {
                    isLiked.toggle()  // Revert on failure
                }
            }
        }
    }
    
    private func handleAmenTap() {
        rtdb.sayAmen(postId: post.id.uuidString) { success in
            if success {
                // Show animation
                withAnimation {
                    // Add your animation here
                }
            }
        }
    }
    
    private func handleSendComment() {
        let text = commentText
        commentText = ""
        
        rtdb.addComment(postId: post.id.uuidString, text: text) { commentId in
            if commentId == nil {
                // Show error
                commentText = text  // Restore text
            }
        }
    }
    
    // MARK: - Setup
    
    private func checkLikedStatus() {
        rtdb.isPostLiked(postId: post.id.uuidString) { liked in
            isLiked = liked
        }
    }
    
    private func setupObservers() {
        // Observe like count
        _ = rtdb.observeLikeCount(postId: post.id.uuidString) { count in
            likeCount = count
        }
        
        // Observe amen count
        _ = rtdb.observeAmenCount(postId: post.id.uuidString) { count in
            amenCount = count
        }
        
        // Observe comment count
        _ = rtdb.observeCommentCount(postId: post.id.uuidString) { count in
            commentCount = count
        }
        
        // Observe comments
        _ = rtdb.observeComments(postId: post.id.uuidString) { comment in
            comments.append(comment)
        }
    }
}

struct CommentRow: View {
    let comment: [String: Any]
    
    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(Color.gray)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(comment["authorName"] as? String ?? "")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(comment["content"] as? String ?? "")
                    .font(.body)
            }
        }
        .padding(.horizontal)
    }
}

//
//  MessagesView.swift
//  SwiftUI Messaging Example
//
//  ⚠️ COMMENTED OUT: This example conflicts with the actual MessagesView implementation
//  See MessagesView.swift for the production implementation

/*
struct MessagesView: View {
    let conversationId: String
    
    @State private var messages: [[String: Any]] = []
    @State private var messageText: String = ""
    
    private let rtdb = RealtimeDatabaseManager.shared
    
    var body: some View {
        VStack {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        ForEach(messages.indices, id: \.self) { index in
                            MessageBubble(message: messages[index])
                                .id(index)
                        }
                    }
                }
                .onChange(of: messages.count) { _ in
                    // Scroll to bottom on new message
                    if let lastIndex = messages.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Message Input
            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .onAppear {
            setupObserver()
            resetUnreadCount()
        }
    }
    
    private func sendMessage() {
        let text = messageText
        messageText = ""
        
        rtdb.sendMessage(conversationId: conversationId, text: text) { success in
            if !success {
                messageText = text  // Restore on failure
            }
        }
    }
    
    private func setupObserver() {
        _ = rtdb.observeMessages(conversationId: conversationId) { message in
            messages.append(message)
        }
    }
    
    private func resetUnreadCount() {
        rtdb.resetUnreadMessages()
    }
}

struct MessageBubble: View {
    let message: [String: Any]
    
    private var isMe: Bool {
        message["senderId"] as? String == Auth.auth().currentUser?.uid
    }
    
    var body: some View {
        HStack {
            if isMe {
                Spacer()
            }
            
            Text(message["text"] as? String ?? "")
                .padding(12)
                .background(isMe ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(isMe ? .white : .primary)
                .cornerRadius(16)
            
            if !isMe {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}
*/

//
//  MainTabView.swift
//  SwiftUI Tab View with Badges
//
//  ⚠️ COMMENTED OUT: This example conflicts with actual implementations
//  Uncomment and modify if you need this specific tab view structure

/*
struct MainTabView: View {
    @StateObject private var rtdbService = RealtimeDatabaseService.shared
    
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "house")
                }
            
            MessagesListView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .badge(rtdbService.unreadMessages > 0 ? "\(rtdbService.unreadMessages)" : nil)
            
            PrayersView()
                .tabItem {
                    Label("Prayers", systemImage: "hands.sparkles")
                }
            
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .badge(rtdbService.unreadNotifications > 0 ? "\(rtdbService.unreadNotifications)" : nil)
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
    }
}
*/

//
//  PrayerView.swift
//  Live Prayer Counter Example
//
//  ⚠️ COMMENTED OUT: This example uses the Prayer model which may conflict
//  Uncomment and modify if you need this specific prayer detail view

/*
struct PrayerDetailView: View {
    let prayer: Prayer
    
    @State private var prayingNowCount: Int = 0
    @State private var isPraying: Bool = false
    @State private var prayingTimer: Timer?
    
    private let rtdb = RealtimeDatabaseManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(prayer.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(prayer.content)
                    .font(.body)
                
                // Live Counter
                HStack {
                    Image(systemName: "person.3.fill")
                    Text("\(prayingNowCount) praying now")
                        .font(.headline)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Pray Button
                Button(action: togglePraying) {
                    HStack {
                        Image(systemName: isPraying ? "hand.raised.fill" : "hands.sparkles")
                        Text(isPraying ? "Stop Praying" : "🙏 Pray")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isPraying ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .onAppear {
            setupObserver()
        }
        .onDisappear {
            if isPraying {
                stopPraying()
            }
        }
    }
    
    private func togglePraying() {
        if isPraying {
            stopPraying()
        } else {
            startPraying()
        }
    }
    
    private func startPraying() {
        isPraying = true
        
        rtdb.startPraying(prayerId: prayer.id.uuidString) { success in
            if !success {
                isPraying = false
            }
        }
        
        // Auto-stop after 5 minutes
        prayingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
            stopPraying()
        }
    }
    
    private func stopPraying() {
        isPraying = false
        prayingTimer?.invalidate()
        prayingTimer = nil
        
        rtdb.stopPraying(prayerId: prayer.id.uuidString)
    }
    
    private func setupObserver() {
        _ = rtdb.observePrayingNowCount(prayerId: prayer.id.uuidString) { count in
            withAnimation {
                prayingNowCount = count
            }
        }
    }
}
*/

//
//  ProfileView.swift
//  SwiftUI Follow Example
//
//  ⚠️ COMMENTED OUT: This example conflicts with the actual UserProfileView implementation
//  See UserProfileView.swift for the production implementation

/*
struct ExampleUserProfileView: View {
    let user: User
    
    @State private var isFollowing: Bool = false
    
    private let rtdb = RealtimeDatabaseManager.shared
    
    var body: some View {
        VStack {
            // Profile Header
            AsyncImage(url: URL(string: user.photoURL ?? "")) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(Color.gray)
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            
            Text(user.displayName)
                .font(.title)
            
            Text("@\(user.username)")
                .font(.caption)
                .foregroundColor(.gray)
            
            // Follow Button
            Button(action: toggleFollow) {
                Text(isFollowing ? "Following" : "Follow")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFollowing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
        .onAppear {
            checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() {
        rtdb.isFollowing(userId: user.id) { following in
            isFollowing = following
        }
    }
    
    private func toggleFollow() {
        isFollowing.toggle()
        
        if isFollowing {
            rtdb.followUser(userId: user.id) { success in
                if !success {
                    isFollowing.toggle()
                }
            }
        } else {
            rtdb.unfollowUser(userId: user.id) { success in
                if !success {
                    isFollowing.toggle()
                }
            }
        }
    }
}
*/

// MARK: - Placeholder Views
// These are commented out to avoid conflicts with actual implementations

struct FeedView: View {
    var body: some View {
        Text("Feed")
    }
}

struct MessagesListView: View {
    var body: some View {
        Text("Messages")
    }
}

struct PrayersView: View {
    var body: some View {
        Text("Prayers")
    }
}

/*
struct NotificationsView: View {
    var body: some View {
        Text("Notifications")
    }
}

struct ProfileView: View {
    var body: some View {
        Text("Profile")
    }
}
*/

// MARK: - Models
// Note: These example models are commented out to avoid conflicts with the actual models in your project.
// Uncomment them only if you're using this file in isolation for testing.

/*
struct Post: Identifiable {
    let id: String
    let authorName: String
    let authorUsername: String
    let authorPhotoURL: String?
    let content: String
}

struct Prayer: Identifiable {
    let id: String
    let title: String
    let content: String
}

struct User: Identifiable {
    let id: String
    let displayName: String
    let username: String
    let photoURL: String?
}
*/
