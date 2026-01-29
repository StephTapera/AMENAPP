# 🚀 Realtime Features Implementation Guide

## ✅ What Was Added to Cloud Functions

I've added these new Cloud Functions that work with Realtime Database:

1. **Unread Counts** - Track unread messages and notifications
2. **Live Prayer Counters** - Show how many people are praying right now
3. **Live Activity Feed** - Global feed of recent activities
4. **Live Community Activity** - Per-community activity tracking

---

## 📱 iOS Implementation

### **1. Unread Counts** 📬

#### **Setup in Swift:**

```swift
import FirebaseDatabase

class UnreadCountsManager: ObservableObject {
    @Published var unreadNotifications: Int = 0
    @Published var unreadMessages: Int = 0
    
    private var rtdb = Database.database().reference()
    private var notificationsHandle: DatabaseHandle?
    private var messagesHandle: DatabaseHandle?
    
    func startObserving(userId: String) {
        // Observe unread notifications
        notificationsHandle = rtdb.child("unreadCounts/\(userId)/notifications")
            .observe(.value) { [weak self] snapshot in
                self?.unreadNotifications = snapshot.value as? Int ?? 0
            }
        
        // Observe unread messages
        messagesHandle = rtdb.child("unreadCounts/\(userId)/messages")
            .observe(.value) { [weak self] snapshot in
                self?.unreadMessages = snapshot.value as? Int ?? 0
            }
    }
    
    func markNotificationsAsRead(userId: String) {
        rtdb.child("unreadCounts/\(userId)/notifications").setValue(0)
    }
    
    func markMessagesAsRead(userId: String, conversationId: String) {
        rtdb.child("unreadCounts/\(userId)/messages").transaction { current in
            return TransactionResult.success(withValue: max(0, (current.value as? Int ?? 0) - 1))
        }
    }
    
    func stopObserving() {
        if let handle = notificationsHandle {
            rtdb.child("unreadCounts").removeObserver(withHandle: handle)
        }
        if let handle = messagesHandle {
            rtdb.child("unreadCounts").removeObserver(withHandle: handle)
        }
    }
    
    deinit {
        stopObserving()
    }
}
```

#### **Usage in SwiftUI:**

```swift
struct ContentView: View {
    @StateObject private var unreadCounts = UnreadCountsManager()
    
    var body: some View {
        TabView {
            // Notifications Tab
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .badge(unreadCounts.unreadNotifications)
            
            // Messages Tab
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .badge(unreadCounts.unreadMessages)
        }
        .onAppear {
            if let userId = Auth.auth().currentUser?.uid {
                unreadCounts.startObserving(userId: userId)
            }
        }
    }
}
```

---

### **2. Live Prayer Counters** 🙏

#### **Swift Implementation:**

```swift
class PrayerActivityManager: ObservableObject {
    @Published var currentlyPraying: Int = 0
    
    private var rtdb = Database.database().reference()
    private var prayingHandle: DatabaseHandle?
    
    func startPraying(prayerId: String, userId: String) async {
        // Mark user as praying
        try? await rtdb.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)")
            .setValue(true)
        
        // Auto-stop after 5 minutes
        Task {
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            await stopPraying(prayerId: prayerId, userId: userId)
        }
    }
    
    func stopPraying(prayerId: String, userId: String) async {
        try? await rtdb.child("prayerActivity/\(prayerId)/prayingUsers/\(userId)")
            .removeValue()
    }
    
    func observePrayingCount(prayerId: String) {
        prayingHandle = rtdb.child("prayerActivity/\(prayerId)/prayingNow")
            .observe(.value) { [weak self] snapshot in
                self?.currentlyPraying = snapshot.value as? Int ?? 0
            }
    }
    
    func stopObserving() {
        if let handle = prayingHandle {
            rtdb.child("prayerActivity").removeObserver(withHandle: handle)
        }
    }
}
```

#### **Usage in Prayer View:**

```swift
struct PrayerDetailView: View {
    let prayer: Prayer
    @StateObject private var prayerActivity = PrayerActivityManager()
    @State private var isPraying = false
    
    var body: some View {
        VStack {
            Text(prayer.title)
                .font(.title)
            
            // Live counter
            if prayerActivity.currentlyPraying > 0 {
                HStack {
                    Image(systemName: "hands.sparkles.fill")
                    Text("\(prayerActivity.currentlyPraying) people praying now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(action: {
                isPraying.toggle()
                Task {
                    if isPraying {
                        await prayerActivity.startPraying(
                            prayerId: prayer.id,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                    } else {
                        await prayerActivity.stopPraying(
                            prayerId: prayer.id,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )
                    }
                }
            }) {
                Label(
                    isPraying ? "Stop Praying" : "Start Praying",
                    systemImage: "hands.sparkles"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            prayerActivity.observePrayingCount(prayerId: prayer.id)
        }
        .onDisappear {
            prayerActivity.stopObserving()
        }
    }
}
```

---

### **3. Live Activity Feed** 📰

#### **Swift Implementation:**

```swift
struct ActivityItem: Identifiable, Codable {
    let id: String
    let type: String // "post", "amen", "comment"
    let userId: String
    let userName: String
    let timestamp: Double
    let postId: String?
    let content: String?
    let postAuthor: String?
    
    var timeAgo: String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        return date.timeAgo()
    }
}

class ActivityFeedManager: ObservableObject {
    @Published var recentActivities: [ActivityItem] = []
    
    private var rtdb = Database.database().reference()
    private var activitiesHandle: DatabaseHandle?
    
    func startObserving() {
        activitiesHandle = rtdb.child("activityFeed/global")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 20)
            .observe(.value) { [weak self] snapshot in
                var activities: [ActivityItem] = []
                
                for child in snapshot.children {
                    guard let snap = child as? DataSnapshot,
                          let dict = snap.value as? [String: Any],
                          let type = dict["type"] as? String,
                          let userId = dict["userId"] as? String,
                          let userName = dict["userName"] as? String,
                          let timestamp = dict["timestamp"] as? Double else {
                        continue
                    }
                    
                    let activity = ActivityItem(
                        id: snap.key,
                        type: type,
                        userId: userId,
                        userName: userName,
                        timestamp: timestamp,
                        postId: dict["postId"] as? String,
                        content: dict["content"] as? String,
                        postAuthor: dict["postAuthor"] as? String
                    )
                    
                    activities.append(activity)
                }
                
                // Sort by timestamp descending
                self?.recentActivities = activities.sorted { $0.timestamp > $1.timestamp }
            }
    }
    
    func stopObserving() {
        if let handle = activitiesHandle {
            rtdb.child("activityFeed/global").removeObserver(withHandle: handle)
        }
    }
}
```

#### **Usage in Feed View:**

```swift
struct LiveActivityFeedView: View {
    @StateObject private var activityFeed = ActivityFeedManager()
    
    var body: some View {
        List(activityFeed.recentActivities) { activity in
            ActivityRowView(activity: activity)
        }
        .navigationTitle("Live Activity")
        .onAppear {
            activityFeed.startObserving()
        }
        .onDisappear {
            activityFeed.stopObserving()
        }
    }
}

struct ActivityRowView: View {
    let activity: ActivityItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForActivity)
                .foregroundStyle(colorForActivity)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activityText)
                    .font(.subheadline)
                
                Text(activity.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var iconForActivity: String {
        switch activity.type {
        case "post": return "doc.text"
        case "amen": return "hands.sparkles.fill"
        case "comment": return "bubble.left"
        default: return "circle"
        }
    }
    
    private var colorForActivity: Color {
        switch activity.type {
        case "post": return .blue
        case "amen": return .purple
        case "comment": return .green
        default: return .gray
        }
    }
    
    private var activityText: String {
        switch activity.type {
        case "post":
            return "\(activity.userName) posted: \(activity.content ?? "")"
        case "amen":
            return "\(activity.userName) said Amen to \(activity.postAuthor ?? "a post")"
        case "comment":
            return "\(activity.userName) commented on a post"
        default:
            return "\(activity.userName) did something"
        }
    }
}
```

---

### **4. Live Community Activity** 👥

#### **Swift Implementation:**

```swift
class CommunityActivityManager: ObservableObject {
    @Published var recentActivities: [ActivityItem] = []
    
    private var rtdb = Database.database().reference()
    private var activitiesHandle: DatabaseHandle?
    
    func observeCommunity(communityId: String) {
        activitiesHandle = rtdb.child("communityActivity/\(communityId)")
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: 30)
            .observe(.value) { [weak self] snapshot in
                var activities: [ActivityItem] = []
                
                for child in snapshot.children {
                    guard let snap = child as? DataSnapshot,
                          let dict = snap.value as? [String: Any],
                          let type = dict["type"] as? String,
                          let userId = dict["userId"] as? String,
                          let userName = dict["userName"] as? String,
                          let timestamp = dict["timestamp"] as? Double else {
                        continue
                    }
                    
                    let activity = ActivityItem(
                        id: snap.key,
                        type: type,
                        userId: userId,
                        userName: userName,
                        timestamp: timestamp,
                        postId: dict["postId"] as? String,
                        content: dict["content"] as? String,
                        postAuthor: nil
                    )
                    
                    activities.append(activity)
                }
                
                self?.recentActivities = activities.sorted { $0.timestamp > $1.timestamp }
            }
    }
    
    func stopObserving() {
        if let handle = activitiesHandle {
            rtdb.child("communityActivity").removeObserver(withHandle: handle)
        }
    }
}
```

#### **Usage in Community View:**

```swift
struct CommunityDetailView: View {
    let community: Community
    @StateObject private var activity = CommunityActivityManager()
    
    var body: some View {
        List {
            Section("Recent Activity") {
                if activity.recentActivities.isEmpty {
                    Text("No recent activity")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.recentActivities.prefix(5)) { item in
                        CommunityActivityRow(activity: item)
                    }
                }
            }
            
            // Rest of community content...
        }
        .onAppear {
            activity.observeCommunity(communityId: community.id)
        }
        .onDisappear {
            activity.stopObserving()
        }
    }
}
```

---

## 🚀 Deployment Steps

1. **Deploy the updated functions:**
   ```bash
   cd /path/to/your/project
   firebase deploy --only functions
   ```

2. **Add the Swift code** to your iOS app

3. **Test each feature:**
   - Send a message → Check unread count updates
   - Start praying → Check live counter updates
   - Create a post → Check activity feed updates

---

## 📊 Realtime Database Structure

After implementation, your database will look like:

```
/
├─ unreadCounts/
│   └─ {userId}/
│       ├─ notifications: 5
│       └─ messages: 3
│
├─ prayerActivity/
│   └─ {prayerId}/
│       ├─ prayingNow: 12
│       └─ prayingUsers/
│           ├─ {userId1}: true
│           └─ {userId2}: true
│
├─ activityFeed/
│   └─ global/
│       ├─ {activityId1}: {...}
│       └─ {activityId2}: {...}
│
└─ communityActivity/
    └─ {communityId}/
        ├─ {activityId1}: {...}
        └─ {activityId2}: {...}
```

---

## ✅ Benefits

**Unread Counts:**
- ✅ Update instantly
- ✅ No query needed
- ✅ Works across devices

**Live Prayer Counters:**
- ✅ See who's praying in real-time
- ✅ Encourages community participation
- ✅ Automatic cleanup after 5 minutes

**Activity Feeds:**
- ✅ Real-time community engagement
- ✅ See recent activities instantly
- ✅ Automatic cleanup (keeps last 100/50 items)

---

## 🎉 You're All Set!

Your app now has real-time features that update instantly! Deploy the functions and add the Swift code to your iOS app to see them in action! 🚀
