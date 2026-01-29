# What Still Needs Backend Integration

## ✅ **Already Complete**
1. ✅ Lightbulb reactions
2. ✅ Amen/Clapping reactions
3. ✅ Comments
4. ✅ Replies
5. ✅ Saves/Bookmarks
6. ✅ Reposts
7. ✅ Profile data loading
8. ✅ Posts on profile
9. ✅ Replies on profile
10. ✅ Saved posts on profile
11. ✅ Reposts on profile

---

## ⚠️ **Still Needs Backend Integration**

### 1. 🚨 **Follow/Unfollow System** (CRITICAL - This is why followers/following are fake!)

**Current Issue:**
- `followersCount` and `followingCount` are stored in Firestore `users` collection
- BUT there's no service to actually follow/unfollow users
- The numbers shown are from user creation (default 0 or sample data)

**What Needs to Be Built:**

#### A. Create `FollowService.swift`
```swift
@MainActor
class FollowService: ObservableObject {
    static let shared = FollowService()
    
    @Published var following: Set<String> = []  // User IDs you're following
    @Published var followers: Set<String> = []   // User IDs following you
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    
    // MARK: - Follow User
    func followUser(userId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Create follow relationship in Firestore
        let followData: [String: Any] = [
            "followerId": currentUserId,
            "followingId": userId,
            "createdAt": Date()
        ]
        
        let batch = db.batch()
        
        // 1. Add to follows collection
        let followRef = db.collection("follows").document()
        batch.setData(followData, forDocument: followRef)
        
        // 2. Increment follower count on target user
        let targetUserRef = db.collection("users").document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(1))
        ], forDocument: targetUserRef)
        
        // 3. Increment following count on current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(1))
        ], forDocument: currentUserRef)
        
        try await batch.commit()
        
        // Update local state
        following.insert(userId)
        
        // Create notification for followed user
        try? await createFollowNotification(userId: userId)
    }
    
    // MARK: - Unfollow User
    func unfollowUser(userId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find and delete the follow relationship
        let followQuery = db.collection("follows")
            .whereField("followerId", isEqualTo: currentUserId)
            .whereField("followingId", isEqualTo: userId)
            .limit(to: 1)
        
        let snapshot = try await followQuery.getDocuments()
        
        guard let followDoc = snapshot.documents.first else {
            return  // Not following
        }
        
        let batch = db.batch()
        
        // 1. Delete follow relationship
        batch.deleteDocument(followDoc.reference)
        
        // 2. Decrement follower count on target user
        let targetUserRef = db.collection("users").document(userId)
        batch.updateData([
            "followersCount": FieldValue.increment(Int64(-1))
        ], forDocument: targetUserRef)
        
        // 3. Decrement following count on current user
        let currentUserRef = db.collection("users").document(currentUserId)
        batch.updateData([
            "followingCount": FieldValue.increment(Int64(-1))
        ], forDocument: currentUserRef)
        
        try await batch.commit()
        
        // Update local state
        following.remove(userId)
    }
    
    // MARK: - Check if Following
    func isFollowing(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Check local cache first
        if following.contains(userId) {
            return true
        }
        
        // Check Firestore
        do {
            let snapshot = try await db.collection("follows")
                .whereField("followerId", isEqualTo: currentUserId)
                .whereField("followingId", isEqualTo: userId)
                .limit(to: 1)
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }
    
    // MARK: - Fetch Followers/Following
    func fetchFollowers(userId: String) async throws -> [String] {
        let snapshot = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        
        return snapshot.documents.compactMap { $0.data()["followerId"] as? String }
    }
    
    func fetchFollowing(userId: String) async throws -> [String] {
        let snapshot = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        return snapshot.documents.compactMap { $0.data()["followingId"] as? String }
    }
}
```

#### B. Update PostCard to use FollowService
In `PostCard.swift`, the follow button needs to be connected:
```swift
// Replace current follow button logic
if !isUserPost {
    Button {
        Task {
            if isFollowing {
                try? await FollowService.shared.unfollowUser(userId: post.authorId)
            } else {
                try? await FollowService.shared.followUser(userId: post.authorId)
            }
            isFollowing.toggle()
        }
    } label: {
        // ...existing button UI...
    }
}
```

---

### 2. 📷 **Profile Photo Upload**

**Current Issue:**
- Profile photo edit shows placeholder
- No actual upload to Firebase Storage

**What Needs to Be Built:**

#### Create `ProfilePhotoEditView.swift`
```swift
import SwiftUI
import PhotosUI

struct ProfilePhotoEditView: View {
    @Environment(\.dismiss) var dismiss
    let currentImageURL: String?
    let onPhotoUpdated: (String?) -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isUploading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                if let imageData = selectedImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                } else if let urlString = currentImageURL,
                          let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                }
                
                // Photo Picker
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Choose Photo")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                        }
                    }
                }
                
                if selectedImageData != nil {
                    Button {
                        uploadPhoto()
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Upload Photo")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(isUploading)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Profile Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func uploadPhoto() {
        guard let imageData = selectedImageData else { return }
        
        isUploading = true
        
        Task {
            do {
                // Upload to Firebase Storage
                let storage = Storage.storage()
                let userId = FirebaseManager.shared.currentUser?.uid ?? UUID().uuidString
                let storageRef = storage.reference().child("profile_photos/\(userId).jpg")
                
                _ = try await storageRef.putDataAsync(imageData)
                let downloadURL = try await storageRef.downloadURL()
                
                // Update user profile
                try await FirebaseManager.shared.db
                    .collection("users")
                    .document(userId)
                    .updateData(["profileImageURL": downloadURL.absoluteString])
                
                onPhotoUpdated(downloadURL.absoluteString)
                dismiss()
                
            } catch {
                print("❌ Upload failed: \(error)")
            }
            
            isUploading = false
        }
    }
}
```

---

### 3. 🔔 **Notifications System**

**Current Issue:**
- Notifications are created but not displayed
- No `NotificationsView` implementation
- No push notification setup

**What Needs to Be Built:**

#### A. Complete `NotificationsView.swift`
Already exists but needs real data loading from:
- Comments on your posts
- Replies to your comments
- Follows
- Reposts of your posts
- Mentions

#### B. Push Notifications
Needs:
- APNs setup
- FCM token handling
- Notification permissions

---

### 4. 🔍 **Search Functionality**

**Current Issue:**
- Search bar exists but doesn't search
- No backend search service

**What Needs to Be Built:**

#### Create `SearchService.swift`
```swift
@MainActor
class SearchService: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    
    func search(query: String, filters: [SearchFilter]) async throws {
        // Search users
        let users = try await searchUsers(query: query)
        
        // Search posts
        let posts = try await searchPosts(query: query, filters: filters)
        
        // Combine results
        searchResults = users + posts
    }
    
    private func searchUsers(query: String) async throws -> [SearchResult] {
        // Query Firestore users collection
        let snapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: query)
            .whereField("displayName", isLessThan: query + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            // Convert to SearchResult
        }
    }
    
    private func searchPosts(query: String, filters: [SearchFilter]) async throws -> [SearchResult] {
        var query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        // Apply filters
        for filter in filters {
            switch filter {
            case .category(let category):
                query = query.whereField("category", isEqualTo: category)
            case .author(let userId):
                query = query.whereField("authorId", isEqualTo: userId)
            }
        }
        
        let snapshot = try await query.getDocuments()
        
        // Filter results by text search (since Firestore doesn't support full-text search)
        return snapshot.documents
            .compactMap { /* Convert and filter by query text */ }
    }
}
```

---

### 5. 💬 **Direct Messages**

**Current Issue:**
- `MessagesView` shows sample data
- No real messaging backend

**What Needs to Be Built:**

#### Create `MessageService.swift`
```swift
@MainActor
class MessageService: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [String: [Message]] = [:]
    
    func sendMessage(to userId: String, content: String) async throws {
        // Create message in Firestore
        // Update conversation
        // Send push notification
    }
    
    func fetchConversations() async throws {
        // Load user's conversations
    }
    
    func fetchMessages(conversationId: String) async throws {
        // Load messages for conversation
    }
    
    func markAsRead(conversationId: String) async throws {
        // Mark all messages as read
    }
}
```

---

### 6. 📊 **Analytics & Engagement**

**What Needs to Be Built:**

- Track post views
- Track profile views
- Track link clicks
- Engagement analytics for users

---

### 7. 🛡️ **Moderation & Safety**

**Current Issue:**
- Report functionality creates UI but doesn't submit
- Block/mute features don't work

**What Needs to Be Built:**

#### A. `ModerationService.swift`
```swift
func reportPost(postId: String, reason: ReportReason, details: String?) async throws
func blockUser(userId: String) async throws
func muteUser(userId: String) async throws
func fetchBlockedUsers() async throws -> [String]
func fetchMutedUsers() async throws -> [String]
```

---

### 8. 📱 **Social Links**

**Current Issue:**
- Can add social links in edit profile
- But they're not saved to Firestore

**What Needs to Be Added:**

Update `UserModel` to include:
```swift
var socialLinks: [SocialLinkData]?

struct SocialLinkData: Codable {
    var platform: String
    var username: String
}
```

---

## 🎯 **Priority Order**

### HIGH PRIORITY (Core Features):
1. **Follow/Unfollow System** ← THIS IS WHY FOLLOWERS/FOLLOWING ARE FAKE!
2. **Profile Photo Upload**
3. **Real Notifications**
4. **Direct Messages**

### MEDIUM PRIORITY (Enhanced Features):
5. **Search**
6. **Moderation/Safety**
7. **Social Links Storage**

### LOW PRIORITY (Analytics):
8. **Analytics & Tracking**

---

## 📝 **Answer to Your Question:**

### Why are followers/following fake?

The `followersCount` and `followingCount` fields exist in your `users` collection in Firestore, but **there's no `FollowService` to actually increment/decrement them**. 

When a user is created, these are set to 0 (or sample data like 1247/842). They never change because there's no follow system!

**To fix this, you need:**
1. Create `FollowService.swift` (shown above)
2. Create `follows` collection in Firestore
3. Connect the follow button in `PostCard.swift`
4. Add followers/following list views

---

## 🚀 **Quick Win: Follow System**

Want me to implement the complete follow/unfollow system for you? It's the missing piece for real follower counts!
