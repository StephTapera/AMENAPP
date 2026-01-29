//
//  RealtimeDatabaseManager.swift
//  AMEN App
//
//  Firebase Realtime Database Manager for instant interactions
//  This replaces slow Firestore writes with fast Realtime DB writes
//

import Foundation
import FirebaseDatabase
import FirebaseAuth

class RealtimeDatabaseManager {
    
    static let shared = RealtimeDatabaseManager()
    
    private let database = Database.database().reference()
    private var observers: [String: DatabaseHandle] = [:]
    
    private init() {
        // Enable offline persistence
        Database.database().isPersistenceEnabled = true
    }
    
    // MARK: - Current User
    
    private var currentUserId: String? {
        return Auth.auth().currentUser?.uid
    }
    
    private var currentUserName: String? {
        return Auth.auth().currentUser?.displayName
    }
    
    // MARK: - Post Interactions
    
    // MARK: Like/Unlike Post (Lightbulb)
    
    /// Like a post (instant!)
    func likePost(postId: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId else {
            completion?(false)
            return
        }
        
        database.child("postInteractions/\(postId)/lightbulbs/\(userId)")
            .setValue(true) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Unlike a post
    func unlikePost(postId: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId else {
            completion?(false)
            return
        }
        
        database.child("postInteractions/\(postId)/lightbulbs/\(userId)")
            .removeValue { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Check if post is liked
    func isPostLiked(postId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = currentUserId else {
            completion(false)
            return
        }
        
        database.child("postInteractions/\(postId)/lightbulbs/\(userId)")
            .observeSingleEvent(of: .value) { snapshot in
                completion(snapshot.value as? Bool ?? false)
            }
    }
    
    /// Observe like count changes (real-time)
    func observeLikeCount(postId: String, onChange: @escaping (Int) -> Void) -> String {
        let observerKey = "likeCount_\(postId)"
        
        let handle = database.child("postInteractions/\(postId)/lightbulbCount")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: Say Amen
    
    /// Say Amen to a post
    func sayAmen(postId: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId, let userName = currentUserName else {
            completion?(false)
            return
        }
        
        let amenId = database.child("postInteractions/\(postId)/amens").childByAutoId().key!
        
        database.child("postInteractions/\(postId)/amens/\(amenId)")
            .setValue([
                "userId": userId,
                "userName": userName,
                "timestamp": ServerValue.timestamp()
            ]) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Observe amen count changes
    func observeAmenCount(postId: String, onChange: @escaping (Int) -> Void) -> String {
        let observerKey = "amenCount_\(postId)"
        
        let handle = database.child("postInteractions/\(postId)/amenCount")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: Comments
    
    /// Add a comment to a post
    func addComment(postId: String, text: String, completion: ((String?) -> Void)? = nil) {
        guard let userId = currentUserId, let userName = currentUserName else {
            print("❌ RealtimeDB: Cannot add comment - user not authenticated")
            completion?(nil)
            return
        }
        
        let commentId = database.child("postInteractions/\(postId)/comments").childByAutoId().key!
        
        print("📝 RealtimeDB: Attempting to add comment to post \(postId)")
        
        database.child("postInteractions/\(postId)/comments/\(commentId)")
            .setValue([
                "authorId": userId,
                "authorName": userName,
                "content": text,
                "timestamp": ServerValue.timestamp(),
                "replyCount": 0
            ]) { error, _ in
                if let error = error {
                    print("❌ RealtimeDB: Failed to add comment - \(error.localizedDescription)")
                    completion?(nil)
                } else {
                    print("✅ RealtimeDB: Comment added successfully - \(commentId)")
                    completion?(commentId)
                }
            }
    }
    
    /// Observe comment count
    func observeCommentCount(postId: String, onChange: @escaping (Int) -> Void) -> String {
        let observerKey = "commentCount_\(postId)"
        
        let handle = database.child("postInteractions/\(postId)/commentCount")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Observe new comments
    func observeComments(postId: String, onAdd: @escaping ([String: Any]) -> Void) -> String {
        let observerKey = "comments_\(postId)"
        
        let handle = database.child("postInteractions/\(postId)/comments")
            .queryOrdered(byChild: "timestamp")
            .observe(.childAdded) { snapshot in
                if var comment = snapshot.value as? [String: Any] {
                    comment["id"] = snapshot.key
                    onAdd(comment)
                }
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: Replies
    
    /// Reply to a comment
    func replyToComment(postId: String, commentId: String, text: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId, let userName = currentUserName else {
            completion?(false)
            return
        }
        
        let replyId = database.child("postInteractions/\(postId)/comments/\(commentId)/replies")
            .childByAutoId().key!
        
        database.child("postInteractions/\(postId)/comments/\(commentId)/replies/\(replyId)")
            .setValue([
                "authorId": userId,
                "authorName": userName,
                "content": text,
                "timestamp": ServerValue.timestamp()
            ]) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Observe replies to a comment
    func observeReplies(postId: String, commentId: String, onAdd: @escaping ([String: Any]) -> Void) -> String {
        let observerKey = "replies_\(postId)_\(commentId)"
        
        let handle = database.child("postInteractions/\(postId)/comments/\(commentId)/replies")
            .queryOrdered(byChild: "timestamp")
            .observe(.childAdded) { snapshot in
                if var reply = snapshot.value as? [String: Any] {
                    reply["id"] = snapshot.key
                    onAdd(reply)
                }
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Observe reply count
    func observeReplyCount(postId: String, commentId: String, onChange: @escaping (Int) -> Void) -> String {
        let observerKey = "replyCount_\(postId)_\(commentId)"
        
        let handle = database.child("postInteractions/\(postId)/comments/\(commentId)/replyCount")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: - Follow/Unfollow
    
    /// Follow a user
    func followUser(userId: String, completion: ((Bool) -> Void)? = nil) {
        guard let followerId = currentUserId else {
            completion?(false)
            return
        }
        
        database.child("follows/\(followerId)/following/\(userId)")
            .setValue(true) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Unfollow a user
    func unfollowUser(userId: String, completion: ((Bool) -> Void)? = nil) {
        guard let followerId = currentUserId else {
            completion?(false)
            return
        }
        
        database.child("follows/\(followerId)/following/\(userId)")
            .removeValue { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Check if following a user
    func isFollowing(userId: String, completion: @escaping (Bool) -> Void) {
        guard let followerId = currentUserId else {
            completion(false)
            return
        }
        
        database.child("follows/\(followerId)/following/\(userId)")
            .observeSingleEvent(of: .value) { snapshot in
                completion(snapshot.value as? Bool ?? false)
            }
    }
    
    // MARK: - Messages
    
    /// Send a text message
    func sendMessage(conversationId: String, text: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId, let userName = currentUserName else {
            completion?(false)
            return
        }
        
        let messageId = database.child("conversations/\(conversationId)/messages")
            .childByAutoId().key!
        
        database.child("conversations/\(conversationId)/messages/\(messageId)")
            .setValue([
                "senderId": userId,
                "senderName": userName,
                "text": text,
                "timestamp": ServerValue.timestamp(),
                "read": false
            ]) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Send a photo message
    func sendPhotoMessage(conversationId: String, photoURL: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId, let userName = currentUserName else {
            completion?(false)
            return
        }
        
        let messageId = database.child("conversations/\(conversationId)/messages")
            .childByAutoId().key!
        
        database.child("conversations/\(conversationId)/messages/\(messageId)")
            .setValue([
                "senderId": userId,
                "senderName": userName,
                "photoURL": photoURL,
                "timestamp": ServerValue.timestamp(),
                "read": false
            ]) { error, _ in
                completion?(error == nil)
            }
    }
    
    /// Observe new messages
    func observeMessages(conversationId: String, onAdd: @escaping ([String: Any]) -> Void) -> String {
        let observerKey = "messages_\(conversationId)"
        
        let handle = database.child("conversations/\(conversationId)/messages")
            .queryOrdered(byChild: "timestamp")
            .observe(.childAdded) { snapshot in
                if var message = snapshot.value as? [String: Any] {
                    message["id"] = snapshot.key
                    onAdd(message)
                }
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: - Unread Counts
    
    /// Observe unread messages count
    func observeUnreadMessages(onChange: @escaping (Int) -> Void) -> String {
        guard let userId = currentUserId else { return "" }
        
        let observerKey = "unreadMessages"
        
        let handle = database.child("unreadCounts/\(userId)/messages")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Observe unread notifications count
    func observeUnreadNotifications(onChange: @escaping (Int) -> Void) -> String {
        guard let userId = currentUserId else { return "" }
        
        let observerKey = "unreadNotifications"
        
        let handle = database.child("unreadCounts/\(userId)/notifications")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(count)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Reset unread messages count
    func resetUnreadMessages() {
        guard let userId = currentUserId else { return }
        database.child("unreadCounts/\(userId)/messages").setValue(0)
    }
    
    /// Reset unread notifications count
    func resetUnreadNotifications() {
        guard let userId = currentUserId else { return }
        database.child("unreadCounts/\(userId)/notifications").setValue(0)
    }
    
    // MARK: - Prayer Activity
    
    /// Start praying for a prayer request (with presence tracking)
    func startPraying(postId: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId else {
            completion?(false)
            return
        }
        
        // Add user to praying users list
        database.child("prayerActivity/\(postId)/prayingUsers/\(userId)")
            .setValue([
                "userId": userId,
                "userName": currentUserName ?? "Anonymous",
                "startedAt": ServerValue.timestamp()
            ]) { [weak self] error, _ in
                if error == nil {
                    // Increment live prayer count
                    self?.database.child("prayerActivity/\(postId)/prayingNow")
                        .setValue(ServerValue.increment(1))
                    
                    // Track total times prayed
                    self?.database.child("prayerActivity/\(postId)/totalPrayerSessions")
                        .setValue(ServerValue.increment(1))
                    
                    print("🙏 Started praying for post: \(postId)")
                }
                completion?(error == nil)
            }
    }
    
    /// Stop praying for a prayer request
    func stopPraying(postId: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = currentUserId else {
            completion?(false)
            return
        }
        
        // Calculate prayer duration
        database.child("prayerActivity/\(postId)/prayingUsers/\(userId)")
            .observeSingleEvent(of: .value) { [weak self] snapshot in
                guard let self = self else { return }
                
                if let userData = snapshot.value as? [String: Any],
                   let startedAt = userData["startedAt"] as? TimeInterval {
                    let duration = Int(Date().timeIntervalSince1970 * 1000 - startedAt)
                    
                    // Record completed session with duration
                    let sessionId = self.database.child("prayerActivity/\(postId)/sessions").childByAutoId().key!
                    self.database.child("prayerActivity/\(postId)/sessions/\(sessionId)")
                        .setValue([
                            "userId": userId,
                            "duration": duration, // milliseconds
                            "completedAt": ServerValue.timestamp()
                        ])
                }
                
                // Remove from active users
                self.database.child("prayerActivity/\(postId)/prayingUsers/\(userId)")
                    .removeValue { error, _ in
                        if error == nil {
                            // Decrement live count
                            self.database.child("prayerActivity/\(postId)/prayingNow")
                                .setValue(ServerValue.increment(-1))
                            
                            print("✅ Stopped praying for post: \(postId)")
                        }
                        completion?(error == nil)
                    }
            }
    }
    
    /// Check if user is currently praying
    func isCurrentlyPraying(postId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = currentUserId else {
            completion(false)
            return
        }
        
        database.child("prayerActivity/\(postId)/prayingUsers/\(userId)")
            .observeSingleEvent(of: .value) { snapshot in
                completion(snapshot.exists())
            }
    }
    
    /// Get total prayer sessions count
    func getTotalPrayerSessions(postId: String, completion: @escaping (Int) -> Void) {
        database.child("prayerActivity/\(postId)/totalPrayerSessions")
            .observeSingleEvent(of: .value) { snapshot in
                completion(snapshot.value as? Int ?? 0)
            }
    }
    
    /// Observe live "praying now" count
    func observePrayingNowCount(postId: String, onChange: @escaping (Int) -> Void) -> String {
        let observerKey = "prayingNow_\(postId)"
        
        let handle = database.child("prayerActivity/\(postId)/prayingNow")
            .observe(.value) { snapshot in
                let count = snapshot.value as? Int ?? 0
                onChange(max(0, count)) // Ensure non-negative
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Get list of users currently praying
    func observePrayingUsers(postId: String, onChange: @escaping ([String]) -> Void) -> String {
        let observerKey = "prayingUsers_\(postId)"
        
        let handle = database.child("prayerActivity/\(postId)/prayingUsers")
            .observe(.value) { snapshot in
                var userNames: [String] = []
                
                for child in snapshot.children {
                    if let childSnapshot = child as? DataSnapshot,
                       let userData = childSnapshot.value as? [String: Any],
                       let userName = userData["userName"] as? String {
                        userNames.append(userName)
                    }
                }
                
                onChange(userNames)
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: - Activity Feed
    
    /// Observe global activity feed
    func observeActivityFeed(onAdd: @escaping ([String: Any]) -> Void) -> String {
        let observerKey = "activityFeed"
        
        let handle = database.child("activityFeed/global")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)
            .observe(.childAdded) { snapshot in
                if var activity = snapshot.value as? [String: Any] {
                    activity["id"] = snapshot.key
                    onAdd(activity)
                }
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    /// Observe community-specific activity
    func observeCommunityActivity(communityId: String, onAdd: @escaping ([String: Any]) -> Void) -> String {
        let observerKey = "communityActivity_\(communityId)"
        
        let handle = database.child("communityActivity/\(communityId)")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 50)
            .observe(.childAdded) { snapshot in
                if var activity = snapshot.value as? [String: Any] {
                    activity["id"] = snapshot.key
                    onAdd(activity)
                }
            }
        
        observers[observerKey] = handle
        return observerKey
    }
    
    // MARK: - Observer Management
    
    /// Remove a specific observer
    func removeObserver(key: String) {
        guard let handle = observers[key] else { return }
        
        // Extract path from key
        let path = extractPath(from: key)
        database.child(path).removeObserver(withHandle: handle)
        observers.removeValue(forKey: key)
    }
    
    /// Remove all observers (call in deinit or viewWillDisappear)
    func removeAllObservers() {
        for (key, handle) in observers {
            let path = extractPath(from: key)
            database.child(path).removeObserver(withHandle: handle)
        }
        observers.removeAll()
    }
    
    private func extractPath(from key: String) -> String {
        // Simple path extraction based on observer key naming
        if key.hasPrefix("likeCount_") {
            let postId = key.replacingOccurrences(of: "likeCount_", with: "")
            return "postInteractions/\(postId)/lightbulbCount"
        } else if key.hasPrefix("amenCount_") {
            let postId = key.replacingOccurrences(of: "amenCount_", with: "")
            return "postInteractions/\(postId)/amenCount"
        } else if key.hasPrefix("commentCount_") {
            let postId = key.replacingOccurrences(of: "commentCount_", with: "")
            return "postInteractions/\(postId)/commentCount"
        } else if key == "unreadMessages" {
            return "unreadCounts/\(currentUserId ?? "")/messages"
        } else if key == "unreadNotifications" {
            return "unreadCounts/\(currentUserId ?? "")/notifications"
        }
        return ""
    }
}
