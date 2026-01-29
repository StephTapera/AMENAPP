# 🎯 Integrate 4 Core Features with Cloud Functions

You have all the UI built! Now let's connect everything to work with your Cloud Functions.

---

## ✅ **What You Already Have**

### 1. **Notifications Center** 
- ✅ `NotificationsView.swift` - Beautiful UI with filters, swipe actions, grouping
- ✅ Sample data structure
- ❌ **Needs:** Connect to Firestore `notifications` collection

### 2. **Comments System**
- ✅ `CommentsView.swift` - Full comments UI with replies
- ✅ `CommentService` - Service layer
- ✅ Cloud Functions - Auto-update counts & send notifications
- ❌ **Needs:** Wire up to actual posts

### 3. **User Profiles**
- ✅ `ProfileView.swift` - Massive profile view (2876 lines!)
- ✅ Follow/Unfollow buttons
- ✅ Cloud Functions - Auto-update follower counts
- ❌ **Needs:** View other users' profiles

### 4. **Direct Messaging**
- ✅ `MessagesView.swift` - Chat list UI
- ✅ `FirebaseMessagingService.swift` - Backend service
- ✅ Sample conversations
- ❌ **Needs:** Real-time messaging with Firestore

---

## 🔌 **Integration Steps**

### **STEP 1: Connect Notifications to Firestore**

Your Cloud Functions already CREATE notifications in the `notifications` collection!

#### **Create NotificationService.swift:**

```swift
//
//  NotificationService.swift
//  AMENAPP
//
//  Real-time notifications from Firestore
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Listen to Notifications
    
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("📡 Starting notifications listener for user: \(userId)")
        
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to notifications: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.notifications = documents.compactMap { doc in
                    try? doc.data(as: AppNotification.self)
                }
                
                self.unreadCount = self.notifications.filter { !$0.read }.count
                
                print("✅ Loaded \(self.notifications.count) notifications (\(self.unreadCount) unread)")
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .updateData(["read": true])
            
            print("✅ Marked notification as read: \(notificationId)")
        } catch {
            print("❌ Error marking notification as read: \(error.localizedDescription)")
        }
    }
    
    func markAllAsRead() async {
        let batch = db.batch()
        
        for notification in notifications where !notification.read {
            let ref = db.collection("notifications").document(notification.id ?? "")
            batch.updateData(["read": true], forDocument: ref)
        }
        
        do {
            try await batch.commit()
            print("✅ Marked all notifications as read")
        } catch {
            print("❌ Error marking all as read: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete Notification
    
    func deleteNotification(_ notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .delete()
            
            print("✅ Deleted notification: \(notificationId)")
        } catch {
            print("❌ Error deleting notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Notification Model

struct AppNotification: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let type: String // "follow", "amen", "comment", "prayer_reminder"
    let actorId: String?
    let actorName: String?
    let actorUsername: String?
    let postId: String?
    let commentText: String?
    let read: Bool
    let createdAt: Timestamp
    
    var timeAgo: String {
        createdAt.dateValue().timeAgoDisplay()
    }
    
    var notificationType: NotificationItem.NotificationType {
        switch type {
        case "follow":
            return .follow
        case "amen":
            return .reaction
        case "comment":
            return .comment
        case "mention":
            return .mention
        default:
            return .reaction
        }
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
```

#### **Update NotificationsView.swift:**

Replace the sample data with real Firestore data:

```swift
struct NotificationsView: View {
    @StateObject private var notificationService = NotificationService.shared
    // ... rest of your code
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ... your header code
                
                // Use real notifications instead of sample
                if notificationService.notifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(notificationService.notifications) { notification in
                                RealNotificationRow(notification: notification)
                            }
                        }
                        .padding()
                    }
                }
            }
            .onAppear {
                notificationService.startListening()
            }
            .onDisappear {
                notificationService.stopListening()
            }
        }
    }
}
```

---

### **STEP 2: Add Comments to Posts**

Your `CommentsView` already exists - just need to show it from posts!

#### **Update your Post view:**

```swift
struct PostView: View {
    let post: Post
    @State private var showComments = false
    
    var body: some View {
        VStack {
            // ... your post content
            
            // Comments button
            Button {
                showComments = true
            } label: {
                HStack {
                    Image(systemName: "bubble.left")
                    Text("\(post.commentCount) Comments")
                }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(post: post)
        }
    }
}
```

**That's it!** Cloud Functions will:
- ✅ Auto-increment `commentCount` when someone comments
- ✅ Send push notification to post author
- ✅ Create in-app notification

---

### **STEP 3: View Other Users' Profiles**

You have a massive `ProfileView.swift` - let's make it work for any user!

#### **Create UserProfileView.swift:**

```swift
//
//  UserProfileView.swift
//  AMENAPP
//
//  View any user's profile
//

import SwiftUI
import FirebaseFirestore

struct UserProfileView: View {
    let userId: String
    
    @State private var user: UserProfile?
    @State private var isFollowing = false
    @State private var isLoading = true
    
    private let db = Firestore.firestore()
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 100)
            } else if let user = user {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 12) {
                        // Avatar
                        Circle()
                            .fill(.blue.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(user.initials)
                                    .font(.custom("OpenSans-Bold", size: 36))
                                    .foregroundStyle(.blue)
                            )
                        
                        // Name
                        Text(user.displayName)
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("@\(user.username)")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                        
                        // Bio
                        if !user.bio.isEmpty {
                            Text(user.bio)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        // Stats
                        HStack(spacing: 40) {
                            StatView(count: user.postsCount, label: "Posts")
                            StatView(count: user.followersCount, label: "Followers")
                            StatView(count: user.followingCount, label: "Following")
                        }
                        .padding(.top, 16)
                        
                        // Follow Button
                        Button {
                            Task {
                                await toggleFollow()
                            }
                        } label: {
                            Text(isFollowing ? "Following" : "Follow")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isFollowing ? Color.gray : Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.top, 40)
                    
                    // User's Posts
                    // TODO: Add grid of user's posts
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadUser()
            await checkIfFollowing()
        }
    }
    
    private func loadUser() async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            user = try doc.data(as: UserProfile.self)
            isLoading = false
        } catch {
            print("❌ Error loading user: \(error.localizedDescription)")
            isLoading = false
        }
    }
    
    private func checkIfFollowing() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("follows")
                .whereField("followerId", isEqualTo: currentUserId)
                .whereField("followingId", isEqualTo: userId)
                .getDocuments()
            
            isFollowing = !snapshot.documents.isEmpty
        } catch {
            print("❌ Error checking follow status: \(error.localizedDescription)")
        }
    }
    
    private func toggleFollow() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            if isFollowing {
                // Unfollow
                let snapshot = try await db.collection("follows")
                    .whereField("followerId", isEqualTo: currentUserId)
                    .whereField("followingId", isEqualTo: userId)
                    .getDocuments()
                
                for doc in snapshot.documents {
                    try await doc.reference.delete()
                }
                
                isFollowing = false
                print("✅ Unfollowed user")
            } else {
                // Follow
                try await db.collection("follows").addDocument(data: [
                    "followerId": currentUserId,
                    "followingId": userId,
                    "createdAt": FieldValue.serverTimestamp()
                ])
                
                isFollowing = true
                print("✅ Followed user")
            }
            
            // Cloud Functions will automatically:
            // - Update follower counts ✅
            // - Send notification to followed user ✅
            
        } catch {
            print("❌ Error toggling follow: \(error.localizedDescription)")
        }
    }
}

struct StatView: View {
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

struct UserProfile: Codable {
    let displayName: String
    let username: String
    let initials: String
    let bio: String
    let postsCount: Int
    let followersCount: Int
    let followingCount: Int
}
```

#### **Navigate to profiles from anywhere:**

```swift
// In your feed, search results, notifications, etc:
NavigationLink(destination: UserProfileView(userId: userId)) {
    Text("@\(username)")
}
```

---

### **STEP 4: Real-Time Direct Messaging**

Your `MessagesView.swift` has the UI - let's add real Firestore messaging!

#### **Create RealTimeMessagingService.swift:**

```swift
//
//  RealTimeMessagingService.swift
//  AMENAPP
//
//  Real-time chat with Firestore
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class RealTimeMessagingService: ObservableObject {
    static let shared = RealTimeMessagingService()
    
    @Published var conversations: [Conversation] = []
    @Published var currentMessages: [Message] = []
    
    private let db = Firestore.firestore()
    private var conversationsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Conversations
    
    func startListeningToConversations() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .order(by: "lastMessageAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to conversations: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.conversations = documents.compactMap { doc in
                    try? doc.data(as: Conversation.self)
                }
                
                print("✅ Loaded \(self.conversations.count) conversations")
            }
    }
    
    func stopListeningToConversations() {
        conversationsListener?.remove()
    }
    
    // MARK: - Messages
    
    func startListeningToMessages(conversationId: String) {
        messagesListener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to messages: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.currentMessages = documents.compactMap { doc in
                    try? doc.data(as: Message.self)
                }
                
                print("✅ Loaded \(self.currentMessages.count) messages")
            }
    }
    
    func stopListeningToMessages() {
        messagesListener?.remove()
    }
    
    // MARK: - Send Message
    
    func sendMessage(conversationId: String, text: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let messageData: [String: Any] = [
            "senderId": userId,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "read": false
        ]
        
        // Add message to conversation
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .addDocument(data: messageData)
        
        // Update conversation's last message
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "lastMessage": text,
                "lastMessageAt": FieldValue.serverTimestamp()
            ])
        
        print("✅ Message sent")
    }
    
    // MARK: - Create Conversation
    
    func createConversation(with userId: String) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check if conversation already exists
        let existing = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isGroup", isEqualTo: false)
            .getDocuments()
        
        for doc in existing.documents {
            let participants = doc.data()["participantIds"] as? [String] ?? []
            if participants.contains(userId) && participants.count == 2 {
                return doc.documentID
            }
        }
        
        // Create new conversation
        let conversationData: [String: Any] = [
            "participantIds": [currentUserId, userId],
            "isGroup": false,
            "createdAt": FieldValue.serverTimestamp(),
            "lastMessage": "",
            "lastMessageAt": FieldValue.serverTimestamp()
        ]
        
        let docRef = try await db.collection("conversations").addDocument(data: conversationData)
        
        print("✅ Created conversation: \(docRef.documentID)")
        return docRef.documentID
    }
}

// MARK: - Models

struct Conversation: Identifiable, Codable {
    @DocumentID var id: String?
    let participantIds: [String]
    let isGroup: Bool
    let lastMessage: String
    let lastMessageAt: Timestamp
    let createdAt: Timestamp
}

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    let senderId: String
    let text: String
    let createdAt: Timestamp
    let read: Bool
}
```

#### **Update MessagesView.swift:**

Connect to real conversations:

```swift
struct MessagesView: View {
    @StateObject private var messagingService = RealTimeMessagingService.shared
    
    var body: some View {
        NavigationStack {
            List(messagingService.conversations) { conversation in
                NavigationLink(destination: ChatView(conversationId: conversation.id ?? "")) {
                    ConversationRow(conversation: conversation)
                }
            }
            .onAppear {
                messagingService.startListeningToConversations()
            }
            .onDisappear {
                messagingService.stopListeningToConversations()
            }
        }
    }
}
```

---

## 🎯 **Summary: What Cloud Functions Do Automatically**

### **When User Follows Someone:**
1. ✅ Cloud Function `updateFollowerCount` triggers
2. ✅ Updates both users' follower/following counts
3. ✅ Sends push notification
4. ✅ Creates in-app notification in `notifications` collection

### **When User Amens a Post:**
1. ✅ Cloud Function `updateAmenCount` triggers
2. ✅ Increments `amenCount` on post
3. ✅ Sends push notification to post author
4. ✅ Creates in-app notification

### **When User Comments:**
1. ✅ Cloud Function `updateCommentCount` triggers
2. ✅ Increments `commentCount` on post
3. ✅ Sends push notification with comment preview
4. ✅ Creates in-app notification

### **Daily at 9 AM:**
1. ✅ Cloud Function `sendPrayerReminders` runs
2. ✅ Sends notifications to users who committed to pray

---

## 📋 **Quick Integration Checklist**

- [ ] Create `NotificationService.swift`
- [ ] Update `NotificationsView` to use real data
- [ ] Add comments button to posts → opens `CommentsView`
- [ ] Create `UserProfileView.swift` for viewing others
- [ ] Add navigation to profiles from @mentions
- [ ] Create `RealTimeMessagingService.swift`
- [ ] Update `MessagesView` to use real conversations
- [ ] Create `ChatView.swift` for individual chats

---

## 🚀 **Next Steps**

1. **Copy the service files above** into your project
2. **Test each feature** one by one
3. **Watch Cloud Functions logs** to see them working:
   ```bash
   firebase functions:log
   ```
4. **See notifications created automatically** in Firestore Console

---

**Everything is ready! Just wire it up and it all works together!** 🎉

Need help with any specific part? Let me know!
