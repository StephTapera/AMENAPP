// ============================================================================
// iOS Quick Reference - Firebase Realtime Database Integration
// ============================================================================
// Copy these code snippets into your iOS app for instant updates!

import FirebaseDatabase
import FirebaseAuth

// ============================================================================
// SETUP
// ============================================================================

let rtdb = Database.database().reference()
let userId = Auth.auth().currentUser!.uid
let userName = Auth.auth().currentUser?.displayName ?? "Anonymous"

// ============================================================================
// 1. LIKE/UNLIKE POST (💡 Lightbulb)
// ============================================================================

func likePost(postId: String) {
    rtdb.child("postInteractions/\(postId)/lightbulbs/\(userId)").setValue(true)
    // Cloud Function automatically updates count and sends notification
}

func unlikePost(postId: String) {
    rtdb.child("postInteractions/\(postId)/lightbulbs/\(userId)").removeValue()
    // Cloud Function automatically updates count
}

func isPostLiked(postId: String, completion: @escaping (Bool) -> Void) {
    rtdb.child("postInteractions/\(postId)/lightbulbs/\(userId)")
        .observeSingleEvent(of: .value) { snapshot in
            completion(snapshot.value as? Bool ?? false)
        }
}

func observeLikeCount(postId: String, onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/lightbulbCount")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

// ============================================================================
// 2. SAY AMEN
// ============================================================================

func sayAmen(postId: String) {
    let amenId = rtdb.child("postInteractions/\(postId)/amens").childByAutoId().key!
    
    rtdb.child("postInteractions/\(postId)/amens/\(amenId)").setValue([
        "userId": userId,
        "userName": userName,
        "timestamp": ServerValue.timestamp()
    ])
    // Cloud Function automatically updates count and sends notification
}

func observeAmenCount(postId: String, onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/amenCount")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

// ============================================================================
// 3. ADD COMMENT
// ============================================================================

func addComment(postId: String, text: String, completion: @escaping (String?) -> Void) {
    let commentId = rtdb.child("postInteractions/\(postId)/comments").childByAutoId().key!
    
    rtdb.child("postInteractions/\(postId)/comments/\(commentId)").setValue([
        "authorId": userId,
        "authorName": userName,
        "content": text,
        "timestamp": ServerValue.timestamp(),
        "replyCount": 0
    ]) { error, _ in
        completion(error == nil ? commentId : nil)
    }
    // Cloud Function automatically updates count and sends notification
}

func observeCommentCount(postId: String, onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/commentCount")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

func observeComments(postId: String, onAdd: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/comments")
        .queryOrdered(byChild: "timestamp")
        .observe(.childAdded) { snapshot in
            if let comment = snapshot.value as? [String: Any] {
                var commentData = comment
                commentData["id"] = snapshot.key
                onAdd(commentData)
            }
        }
}

// ============================================================================
// 4. REPLY TO COMMENT
// ============================================================================

func replyToComment(postId: String, commentId: String, text: String, completion: @escaping (Bool) -> Void) {
    let replyId = rtdb.child("postInteractions/\(postId)/comments/\(commentId)/replies")
        .childByAutoId().key!
    
    rtdb.child("postInteractions/\(postId)/comments/\(commentId)/replies/\(replyId)")
        .setValue([
            "authorId": userId,
            "authorName": userName,
            "content": text,
            "timestamp": ServerValue.timestamp()
        ]) { error, _ in
            completion(error == nil)
        }
    // Cloud Function automatically updates reply count and sends notification
}

func observeReplies(postId: String, commentId: String, onAdd: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/comments/\(commentId)/replies")
        .queryOrdered(byChild: "timestamp")
        .observe(.childAdded) { snapshot in
            if let reply = snapshot.value as? [String: Any] {
                var replyData = reply
                replyData["id"] = snapshot.key
                onAdd(replyData)
            }
        }
}

func observeReplyCount(postId: String, commentId: String, onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("postInteractions/\(postId)/comments/\(commentId)/replyCount")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

// ============================================================================
// 5. FOLLOW/UNFOLLOW USER
// ============================================================================

func followUser(userId: String) {
    let followerId = Auth.auth().currentUser!.uid
    rtdb.child("follows/\(followerId)/following/\(userId)").setValue(true)
    // Cloud Function automatically updates counts and sends notification
}

func unfollowUser(userId: String) {
    let followerId = Auth.auth().currentUser!.uid
    rtdb.child("follows/\(followerId)/following/\(userId)").removeValue()
    // Cloud Function automatically updates counts
}

func isFollowing(userId: String, completion: @escaping (Bool) -> Void) {
    let followerId = Auth.auth().currentUser!.uid
    rtdb.child("follows/\(followerId)/following/\(userId)")
        .observeSingleEvent(of: .value) { snapshot in
            completion(snapshot.value as? Bool ?? false)
        }
}

// ============================================================================
// 6. SEND MESSAGE
// ============================================================================

func sendMessage(conversationId: String, text: String, completion: @escaping (Bool) -> Void) {
    let messageId = rtdb.child("conversations/\(conversationId)/messages").childByAutoId().key!
    
    rtdb.child("conversations/\(conversationId)/messages/\(messageId)").setValue([
        "senderId": userId,
        "senderName": userName,
        "text": text,
        "timestamp": ServerValue.timestamp(),
        "read": false
    ]) { error, _ in
        completion(error == nil)
    }
    // Cloud Function automatically syncs to Firestore and sends notification
}

func sendPhotoMessage(conversationId: String, photoURL: String, completion: @escaping (Bool) -> Void) {
    let messageId = rtdb.child("conversations/\(conversationId)/messages").childByAutoId().key!
    
    rtdb.child("conversations/\(conversationId)/messages/\(messageId)").setValue([
        "senderId": userId,
        "senderName": userName,
        "photoURL": photoURL,
        "timestamp": ServerValue.timestamp(),
        "read": false
    ]) { error, _ in
        completion(error == nil)
    }
}

func observeMessages(conversationId: String, onAdd: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
    return rtdb.child("conversations/\(conversationId)/messages")
        .queryOrdered(byChild: "timestamp")
        .observe(.childAdded) { snapshot in
            if let message = snapshot.value as? [String: Any] {
                var messageData = message
                messageData["id"] = snapshot.key
                onAdd(messageData)
            }
        }
}

// ============================================================================
// 7. UNREAD COUNTS
// ============================================================================

func observeUnreadMessages(onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("unreadCounts/\(userId)/messages")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

func observeUnreadNotifications(onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("unreadCounts/\(userId)/notifications")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

func resetUnreadMessages() {
    rtdb.child("unreadCounts/\(userId)/messages").setValue(0)
}

func resetUnreadNotifications() {
    rtdb.child("unreadCounts/\(userId)/notifications").setValue(0)
}

// ============================================================================
// 8. PRAYER ACTIVITY
// ============================================================================

func startPraying(prayerId: String) {
    rtdb.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)").setValue(true)
    // Cloud Function automatically increments prayingNow counter
}

func stopPraying(prayerId: String) {
    rtdb.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)").removeValue()
    // Cloud Function automatically decrements prayingNow counter
}

func observePrayingNowCount(prayerId: String, onChange: @escaping (Int) -> Void) -> DatabaseHandle {
    return rtdb.child("prayerActivity/\(prayerId)/prayingNow")
        .observe(.value) { snapshot in
            onChange(snapshot.value as? Int ?? 0)
        }
}

// ============================================================================
// 9. ACTIVITY FEED
// ============================================================================

func observeActivityFeed(onAdd: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
    return rtdb.child("activityFeed/global")
        .queryOrdered(byChild: "timestamp")
        .queryLimited(toLast: 50)
        .observe(.childAdded) { snapshot in
            if let activity = snapshot.value as? [String: Any] {
                var activityData = activity
                activityData["id"] = snapshot.key
                onAdd(activityData)
            }
        }
}

func observeCommunityActivity(communityId: String, onAdd: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
    return rtdb.child("communityActivity/\(communityId)")
        .queryOrdered(byChild: "timestamp")
        .queryLimited(toLast: 50)
        .observe(.childAdded) { snapshot in
            if let activity = snapshot.value as? [String: Any] {
                var activityData = activity
                activityData["id"] = snapshot.key
                onAdd(activityData)
            }
        }
}

// ============================================================================
// 10. CLEANUP (Important!)
// ============================================================================

// Store database handles and remove observers when done
var observers: [DatabaseHandle] = []

func removeObserver(handle: DatabaseHandle, path: String) {
    rtdb.child(path).removeObserver(withHandle: handle)
}

func removeAllObservers() {
    // Call this in viewWillDisappear or deinit
    for handle in observers {
        // Remove from appropriate path
        rtdb.removeObserver(withHandle: handle)
    }
    observers.removeAll()
}

// ============================================================================
// EXAMPLE USAGE IN A VIEW CONTROLLER
// ============================================================================
// NOTE: These example classes are commented out to avoid conflicts with
// actual implementations in your project. Refer to this file for code snippets
// but don't use these class declarations directly.

/*
class PostViewController: UIViewController {
    
    var postId: String!
    var likeCountObserver: DatabaseHandle?
    var commentCountObserver: DatabaseHandle?
    var commentsObserver: DatabaseHandle?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupObservers()
    }
    
    func setupObservers() {
        // Observe like count
        likeCountObserver = observeLikeCount(postId: postId) { count in
            self.likeCountLabel.text = "\(count)"
        }
        
        // Observe comment count
        commentCountObserver = observeCommentCount(postId: postId) { count in
            self.commentCountLabel.text = "\(count)"
        }
        
        // Observe new comments
        commentsObserver = observeComments(postId: postId) { commentData in
            self.addCommentToUI(commentData)
        }
    }
    
    @IBAction func likeButtonTapped(_ sender: UIButton) {
        if sender.isSelected {
            unlikePost(postId: postId)
            sender.isSelected = false
        } else {
            likePost(postId: postId)
            sender.isSelected = true
        }
    }
    
    @IBAction func commentButtonTapped(_ sender: UIButton) {
        let text = commentTextField.text ?? ""
        addComment(postId: postId, text: text) { commentId in
            if commentId != nil {
                self.commentTextField.text = ""
                print("Comment added successfully!")
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Clean up observers
        if let handle = likeCountObserver {
            rtdb.child("postInteractions/\(postId!)/lightbulbCount")
                .removeObserver(withHandle: handle)
        }
        if let handle = commentCountObserver {
            rtdb.child("postInteractions/\(postId!)/commentCount")
                .removeObserver(withHandle: handle)
        }
        if let handle = commentsObserver {
            rtdb.child("postInteractions/\(postId!)/comments")
                .removeObserver(withHandle: handle)
        }
    }
    
    func addCommentToUI(_ commentData: [String: Any]) {
        // Add comment to table view or collection view
    }
}
*/

// ============================================================================
// EXAMPLE: UNREAD BADGE
// ============================================================================

/*
class TabBarController: UITabBarController {
    
    var messageObserver: DatabaseHandle?
    var notificationObserver: DatabaseHandle?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUnreadObservers()
    }
    
    func setupUnreadObservers() {
        // Messages tab badge
        messageObserver = observeUnreadMessages { count in
            self.tabBar.items?[1].badgeValue = count > 0 ? "\(count)" : nil
        }
        
        // Notifications tab badge
        notificationObserver = observeUnreadNotifications { count in
            self.tabBar.items?[3].badgeValue = count > 0 ? "\(count)" : nil
        }
    }
    
    deinit {
        if let handle = messageObserver {
            rtdb.removeObserver(withHandle: handle)
        }
        if let handle = notificationObserver {
            rtdb.removeObserver(withHandle: handle)
        }
    }
}
*/

// ============================================================================
// EXAMPLE: PRAYER SCREEN
// ============================================================================

/*
class PrayerViewController: UIViewController {
    
    var prayerId: String!
    var isPraying = false
    var prayingObserver: DatabaseHandle?
    var prayingTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observePrayingCount()
    }
    
    func observePrayingCount() {
        prayingObserver = observePrayingNowCount(prayerId: prayerId) { count in
            self.prayingNowLabel.text = "\(count) praying now"
        }
    }
    
    @IBAction func prayButtonTapped(_ sender: UIButton) {
        if isPraying {
            stopPraying(prayerId: prayerId)
            prayingTimer?.invalidate()
            sender.setTitle("Start Praying", for: .normal)
        } else {
            startPraying(prayerId: prayerId)
            
            // Auto-stop after 5 minutes
            prayingTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { _ in
                self.stopPraying(prayerId: self.prayerId)
                self.isPraying = false
                sender.setTitle("Start Praying", for: .normal)
            }
            
            sender.setTitle("Stop Praying", for: .normal)
        }
        isPraying.toggle()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Always stop praying when leaving screen
        if isPraying {
            stopPraying(prayerId: prayerId)
        }
        
        if let handle = prayingObserver {
            rtdb.child("prayerActivity/\(prayerId!)/prayingNow")
                .removeObserver(withHandle: handle)
        }
    }
}
*/

// ============================================================================
// PERFORMANCE TIPS
// ============================================================================

/*
 1. Always remove observers in viewWillDisappear or deinit
 2. Use .observeSingleEvent for one-time reads (better performance)
 3. Use .queryLimited to limit number of items
 4. Consider pagination for large lists
 5. Cache data locally to reduce database reads
 6. Use .observe(.childAdded) for infinite scrolling feeds
 7. Debounce frequent writes (like typing indicators)
 */

// ============================================================================
// OFFLINE PERSISTENCE
// ============================================================================

// Enable offline persistence (add in AppDelegate)
func enableOfflineMode() {
    Database.database().isPersistenceEnabled = true
}

// Keep data synced even when offline
func keepSynced(path: String) {
    rtdb.child(path).keepSynced(true)
}

// Example: Keep user's feed synced
func setupOfflineSync() {
    keepSynced(path: "postInteractions")
    keepSynced(path: "unreadCounts/\(userId)")
}
