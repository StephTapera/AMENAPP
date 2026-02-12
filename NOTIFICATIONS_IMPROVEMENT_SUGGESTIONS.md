# Notification System - Top 3 Improvement Suggestions

**Date**: February 11, 2026
**Current Issues**:
1. Profile photos not showing consistently in real-time
2. Duplicate notifications appearing
3. Limited AI/smart features

---

## 🥇 SUGGESTION 1: Real-Time Profile Photo Sync with CDN Caching

### Problem Analysis

**Current Implementation**:
```swift
// NotificationsView.swift - Line 2077-2093
func getProfile(userId: String) async -> CachedProfile? {
    // Check 5-minute cache
    if let cached = cache[userId],
       let timestamp = cacheTimestamps[userId],
       Date().timeIntervalSince(timestamp) < cacheExpirationSeconds {
        return cached  // ❌ Returns stale data
    }

    // Fetch from Firestore
    let doc = try await db.collection("users").document(userId).getDocument()
    let profile = CachedProfile(
        id: userId,
        name: data["displayName"] as? String ?? "Unknown",
        imageURL: data["profileImageURL"] as? String  // ❌ No real-time updates
    )
}
```

**Issues**:
- 5-minute cache can show outdated profile photos
- No real-time listener for profile changes
- Fetches entire user document (wasteful)
- Not using CachedAsyncImage for image caching

---

### ✅ Recommended Solution: Hybrid Cache with Real-Time Sync

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│  Notification Appears                                    │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 1: Check Memory Cache (instant)                   │
│  • In-memory dictionary: userId → CachedProfile          │
│  • Returns immediately if available                      │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼ (if not in cache)
┌─────────────────────────────────────────────────────────┐
│  Step 2: Fetch & Subscribe (async)                      │
│  • Fetch user profile from Firestore                    │
│  • Start real-time listener for THIS user               │
│  • Store in cache with listener reference               │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 3: Real-Time Updates                              │
│  • Listener fires on profile photo change               │
│  • Update cache instantly                                │
│  • Trigger @Published update → UI refreshes             │
└─────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 4: Use CachedAsyncImage                           │
│  • Image URLs cached separately                          │
│  • Faster image loading                                 │
│  • Automatic invalidation on URL change                 │
└─────────────────────────────────────────────────────────┘
```

**Implementation**:

```swift
@MainActor
class EnhancedProfileCache: ObservableObject {
    static let shared = EnhancedProfileCache()

    // Published so SwiftUI views auto-update
    @Published private var profiles: [String: CachedProfile] = [:]

    // Active listeners per user
    private var listeners: [String: ListenerRegistration] = [:]

    private let db = Firestore.firestore()
    private let maxActiveListeners = 50

    // MARK: - Get Profile (with auto-subscription)

    func getProfile(userId: String) -> CachedProfile? {
        // Return cached if available
        if let profile = profiles[userId] {
            return profile
        }

        // Start background fetch & subscribe
        Task {
            await fetchAndSubscribe(userId: userId)
        }

        return nil  // Will update via @Published when ready
    }

    // MARK: - Fetch & Subscribe

    private func fetchAndSubscribe(userId: String) async {
        // Don't subscribe twice
        guard listeners[userId] == nil else { return }

        // Limit active listeners (cleanup old ones)
        if listeners.count >= maxActiveListeners {
            cleanupOldestListener()
        }

        // Real-time listener for THIS user
        let listener = db.collection("users")
            .document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let data = snapshot?.data() else { return }

                let profile = CachedProfile(
                    id: userId,
                    name: data["displayName"] as? String ?? "Unknown",
                    imageURL: data["profileImageURL"] as? String,
                    username: data["username"] as? String
                )

                // ✅ Update triggers @Published → UI updates
                self.profiles[userId] = profile

                print("🔄 Profile updated in real-time: \(profile.name)")
            }

        listeners[userId] = listener
    }

    // MARK: - Cleanup

    private func cleanupOldestListener() {
        // Remove least recently used listener
        if let oldestUserId = listeners.keys.first {
            listeners[oldestUserId]?.remove()
            listeners.removeValue(forKey: oldestUserId)
            profiles.removeValue(forKey: oldestUserId)
        }
    }

    func cleanup() {
        // Remove all listeners
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        profiles.removeAll()
    }
}

// Enhanced CachedProfile
struct CachedProfile: Equatable {
    let id: String
    let name: String
    let imageURL: String?
    let username: String?
    let lastUpdated: Date = Date()

    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
```

**Update GroupedNotificationRow**:

```swift
struct GroupedNotificationRow: View {
    let group: NotificationGroup

    @ObservedObject private var profileCache = EnhancedProfileCache.shared

    // ✅ Now auto-updates when profile changes
    private var actorProfile: CachedProfile? {
        guard let actorId = group.primaryActorId else { return nil }
        return profileCache.getProfile(userId: actorId)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar with real-time updates
            if let profile = actorProfile {
                if let imageURL = profile.imageURL, !imageURL.isEmpty,
                   let url = URL(string: imageURL) {
                    // ✅ Use CachedAsyncImage for better performance
                    CachedAsyncImage(
                        url: url,
                        content: { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        },
                        placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Text(profile.initials)
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(.secondary)
                                )
                        }
                    )
                } else {
                    // Fallback initials
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(profile.initials)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.blue)
                        )
                }
            } else {
                // Loading placeholder
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(ProgressView())
            }

            // ... rest of notification content
        }
    }
}
```

**Benefits**:
- ✅ **Real-time updates**: Profile photos update instantly when changed
- ✅ **Performance**: Only fetches each user profile once, then subscribes
- ✅ **Memory efficient**: Limits active listeners to 50 users
- ✅ **Image caching**: Uses CachedAsyncImage for faster loading
- ✅ **Automatic cleanup**: Removes old listeners to prevent memory leaks

---

## 🥈 SUGGESTION 2: AI-Powered Duplicate Detection & Intelligent Grouping

### Problem Analysis

**Current Deduplication**:
```swift
// NotificationService.swift - Line 188
let deduplicated = self.deduplicateNotifications(parsedNotifications)
```

**Issues**:
- Simple ID-based deduplication (if implemented)
- Doesn't handle semantic duplicates (e.g., "John liked your post" + "John reacted to your post")
- No intelligent grouping (e.g., "John and 5 others liked your post")
- Duplicate notifications from Firestore can still slip through

---

### ✅ Recommended Solution: AI-Powered Smart Grouping with Firebase Genkit

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│  Raw Notifications from Firestore                       │
│  • John liked your post (10:00 AM)                      │
│  • Sarah commented on your post (10:02 AM)              │
│  • Mike liked your post (10:03 AM)                      │
│  • John reacted to your post (10:00 AM) ← DUPLICATE     │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 1: Local Deduplication (instant)                  │
│  • Remove exact ID duplicates                            │
│  • Group by: postId + type + timeWindow (5 min)         │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 2: AI Semantic Analysis (Genkit + Gemini)        │
│  • Detect semantic duplicates                           │
│  • Group related notifications                          │
│  • Generate smart summaries                             │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Step 3: Intelligent Grouping                           │
│  Output: "John and 2 others liked your post"            │
│          "5 new comments on 'AI in Faith'"              │
└─────────────────────────────────────────────────────────┘
```

**Implementation**:

**1. Enhanced Local Deduplication**:

```swift
class SmartNotificationDeduplicator {

    // MARK: - Deduplication

    func deduplicate(_ notifications: [AppNotification]) -> [AppNotification] {
        var seen = Set<String>()
        var deduped: [AppNotification] = []

        for notification in notifications {
            // Generate fingerprint for this notification
            let fingerprint = generateFingerprint(notification)

            if !seen.contains(fingerprint) {
                seen.insert(fingerprint)
                deduped.append(notification)
            } else {
                print("🔍 Removed duplicate: \(notification.type.rawValue) from \(notification.fromUsername ?? "Unknown")")
            }
        }

        return deduped
    }

    // MARK: - Fingerprint Generation

    private func generateFingerprint(_ notification: AppNotification) -> String {
        // Create unique fingerprint based on key attributes
        var components: [String] = []

        // Include ID if available
        if let id = notification.id {
            components.append("id:\(id)")
        }

        // Include type + fromUserId + postId + timestamp (rounded to 5 min)
        components.append("type:\(notification.type.rawValue)")
        components.append("from:\(notification.fromUserId)")

        if let postId = notification.postId {
            components.append("post:\(postId)")
        }

        // Round timestamp to 5-minute window
        let rounded = roundToFiveMinutes(notification.timestamp)
        components.append("time:\(rounded)")

        return components.joined(separator:"|")
    }

    private func roundToFiveMinutes(_ date: Date) -> Int {
        let interval = date.timeIntervalSince1970
        return Int(interval / 300) * 300  // 300 seconds = 5 minutes
    }

    // MARK: - Intelligent Grouping

    func group(_ notifications: [AppNotification]) -> [NotificationGroup] {
        var groups: [String: [AppNotification]] = [:]

        for notification in notifications {
            let groupKey = generateGroupKey(notification)
            groups[groupKey, default: []].append(notification)
        }

        return groups.values.compactMap { notifs in
            NotificationGroup(notifications: notifs)
        }
    }

    private func generateGroupKey(_ notification: AppNotification) -> String {
        // Group by: postId + type + time window (30 min)
        var key = notification.type.rawValue

        if let postId = notification.postId {
            key += "_\(postId)"
        }

        let timeWindow = roundToThirtyMinutes(notification.timestamp)
        key += "_\(timeWindow)"

        return key
    }

    private func roundToThirtyMinutes(_ date: Date) -> Int {
        let interval = date.timeIntervalSince1970
        return Int(interval / 1800) * 1800  // 1800 seconds = 30 minutes
    }
}
```

**2. AI-Powered Semantic Analysis with Firebase Genkit**:

Create `genkit/src/notificationAI.ts`:

```typescript
import { genkit } from 'genkit';
import { gemini15Flash } from '@genkit-ai/googleai';

// AI-powered notification grouping
export const analyzeNotifications = genkit({
  name: 'analyzeNotifications',
  model: gemini15Flash,

  inputSchema: {
    notifications: [{
      type: String,
      fromUser: String,
      postTitle: String,
      timestamp: Number,
      message: String
    }]
  },

  outputSchema: {
    groups: [{
      summary: String,
      notificationIds: [String],
      priority: Number
    }],
    duplicates: [String]
  },

  prompt: `
    Analyze these notifications and:
    1. Detect semantic duplicates (same action, different wording)
    2. Group related notifications intelligently
    3. Generate concise summaries
    4. Assign priority scores (0-100)

    Notifications:
    {{notifications}}

    Rules:
    - Group reactions by post within 1 hour
    - Detect duplicate actions (e.g., "liked" and "reacted to")
    - Prioritize: mentions (90), comments (80), reactions (60), follows (50)
    - Create summaries like: "John and 5 others liked your post"
  `
});

// Real-time duplicate detection
export const detectDuplicates = genkit({
  name: 'detectDuplicates',
  model: gemini15Flash,

  inputSchema: {
    newNotification: {
      type: String,
      fromUser: String,
      message: String
    },
    existingNotifications: [{
      type: String,
      fromUser: String,
      message: String
    }]
  },

  outputSchema: {
    isDuplicate: Boolean,
    duplicateOfId: String,
    confidence: Number
  },

  prompt: `
    Determine if this new notification is a duplicate of any existing ones.

    New notification:
    Type: {{newNotification.type}}
    From: {{newNotification.fromUser}}
    Message: {{newNotification.message}}

    Existing notifications:
    {{existingNotifications}}

    Return true if it's semantically the same as any existing notification.
  `
});
```

**3. Swift Integration**:

```swift
class AINotificationService {
    static let shared = AINotificationService()

    private let genkitURL = "https://your-genkit-server.com"

    func analyzeAndGroup(_ notifications: [AppNotification]) async throws -> [NotificationGroup] {
        // Step 1: Local deduplication (instant)
        let deduplicator = SmartNotificationDeduplicator()
        let localDeduped = deduplicator.deduplicate(notifications)

        // Step 2: Send to Genkit for AI analysis (async)
        let request = NotificationAnalysisRequest(
            notifications: localDeduped.map { notification in
                NotificationDTO(
                    id: notification.id ?? UUID().uuidString,
                    type: notification.type.rawValue,
                    fromUser: notification.fromUsername ?? "Unknown",
                    postTitle: notification.postTitle ?? "",
                    timestamp: notification.timestamp.timeIntervalSince1970,
                    message: notification.title
                )
            }
        )

        guard let url = URL(string: "\(genkitURL)/analyzeNotifications") else {
            throw NSError(domain: "AINotificationService", code: 0)
        }

        let (data, _) = try await URLSession.shared.upload(
            for: URLRequest(url: url),
            from: try JSONEncoder().encode(request)
        )

        let response = try JSONDecoder().decode(NotificationAnalysisResponse.self, from: data)

        // Step 3: Create smart groups
        return response.groups.map { group in
            let groupNotifications = localDeduped.filter {
                group.notificationIds.contains($0.id ?? "")
            }

            return NotificationGroup(
                notifications: groupNotifications,
                aiSummary: group.summary,
                priority: group.priority
            )
        }
    }
}
```

**Benefits**:
- ✅ **Eliminates duplicates**: Both exact and semantic duplicates
- ✅ **Smart grouping**: "5 people liked your post" instead of 5 separate notifications
- ✅ **AI-generated summaries**: Natural language summaries
- ✅ **Priority scoring**: Most important notifications first
- ✅ **Low cost**: Gemini 1.5 Flash is very cheap (~$0.01 per 1000 notifications)

---

## 🥉 SUGGESTION 3: Smart Notification Digest with AI Summarization

### Problem Analysis

**Current State**:
- User gets bombarded with individual notifications
- No way to see "what happened while I was away"
- Important notifications get lost in noise

---

### ✅ Recommended Solution: AI-Powered Daily/Hourly Digest

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│  User Opens App After Being Away                        │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Check: Have unread notifications?                      │
│  • If < 10: Show normal list                            │
│  • If >= 10: Trigger AI digest                          │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  AI Digest Generation (Genkit + Gemini Pro)            │
│  • Analyze all unread notifications                     │
│  • Extract key insights                                 │
│  • Generate personalized summary                        │
└─────────────┬───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  Show Smart Digest Card                                 │
│                                                          │
│  ┌────────────────────────────────────────────────┐   │
│  │ 📊 While you were away...                      │   │
│  │                                                 │   │
│  │ • 12 people reacted to your post on AI         │   │
│  │ • Sarah mentioned you in a comment             │   │
│  │ • 5 new followers joined AMEN                  │   │
│  │ • Trending: #PrayerWarrior is active           │   │
│  │                                                 │   │
│  │ [View All 47 Notifications →]                  │   │
│  └────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Implementation**:

**1. Genkit AI Digest Generator** (`genkit/src/notificationDigest.ts`):

```typescript
import { genkit } from 'genkit';
import { gemini15Pro } from '@genkit-ai/googleai';

export const generateNotificationDigest = genkit({
  name: 'generateNotificationDigest',
  model: gemini15Pro,

  inputSchema: {
    notifications: [{
      type: String,
      fromUser: String,
      postTitle: String,
      message: String,
      timestamp: Number
    }],
    userContext: {
      interests: [String],
      followingCount: Number,
      postsCount: Number
    }
  },

  outputSchema: {
    summary: {
      headline: String,
      keyInsights: [String],
      topActions: [{
        action: String,
        count: Number,
        description: String
      }],
      trendingTopics: [String],
      urgentItems: [{
        notification: String,
        reason: String
      }]
    }
  },

  prompt: `
    You are analyzing a user's notifications to create a personalized digest.

    Notifications ({{notifications.length}} total):
    {{notifications}}

    User Context:
    Interests: {{userContext.interests}}
    Following: {{userContext.followingCount}} people
    Posts: {{userContext.postsCount}}

    Generate a concise, personalized summary with:
    1. Headline: One sentence overview
    2. Key Insights: 3-5 bullet points of what happened
    3. Top Actions: Group similar notifications (e.g., "12 reactions", "5 new followers")
    4. Trending Topics: Hashtags or themes that appeared frequently
    5. Urgent Items: Mentions, direct messages, or important notifications

    Keep it friendly, concise, and actionable.
    Use emojis where appropriate.
  `
});
```

**2. Swift Digest View**:

```swift
struct NotificationDigestCard: View {
    let digest: NotificationDigest
    let notificationCount: Int
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)

                Text("While you were away...")
                    .font(.custom("OpenSans-Bold", size: 18))

                Spacer()

                Text("\(notificationCount) updates")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.1))
                    )
            }

            // Headline
            Text(digest.headline)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.secondary)

            Divider()

            // Key Insights
            VStack(alignment: .leading, spacing: 10) {
                ForEach(digest.keyInsights, id: \.self) { insight in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)

                        Text(insight)
                            .font(.custom("OpenSans-Regular", size: 14))
                    }
                }
            }

            // Urgent Items (if any)
            if !digest.urgentItems.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Needs Attention")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.orange)
                    }

                    ForEach(digest.urgentItems, id: \.notification) { item in
                        Text(item.notification)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.primary)
                    }
                }
            }

            // View All Button
            Button {
                onViewAll()
            } label: {
                HStack {
                    Text("View All \(notificationCount) Notifications")
                        .font(.custom("OpenSans-Bold", size: 14))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.1))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.3),
                                    Color.purple.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .purple.opacity(0.1), radius: 20, y: 10)
    }
}

// Model
struct NotificationDigest: Codable {
    let headline: String
    let keyInsights: [String]
    let topActions: [TopAction]
    let trendingTopics: [String]
    let urgentItems: [UrgentItem]

    struct TopAction: Codable {
        let action: String
        let count: Int
        let description: String
    }

    struct UrgentItem: Codable {
        let notification: String
        let reason: String
    }
}
```

**3. Integration in NotificationsView**:

```swift
struct NotificationsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @State private var showDigest = false
    @State private var digest: NotificationDigest?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Show digest if > 10 unread notifications
                if let digest = digest {
                    NotificationDigestCard(
                        digest: digest,
                        notificationCount: notificationService.unreadCount,
                        onViewAll: {
                            withAnimation {
                                showDigest = false
                            }
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                // Regular notifications
                if !showDigest {
                    ForEach(groupedNotifications) { group in
                        GroupedNotificationRow(group: group)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await checkForDigest()
            }
        }
    }

    private func checkForDigest() async {
        guard notificationService.unreadCount >= 10 else { return }

        do {
            // Generate digest via Genkit
            let digest = try await AINotificationService.shared.generateDigest(
                notifications: notificationService.notifications.filter { !$0.read },
                userContext: UserContext(
                    interests: ["AI", "Faith", "Technology"],
                    followingCount: 150,
                    postsCount: 42
                )
            )

            await MainActor.run {
                self.digest = digest
                self.showDigest = true
            }
        } catch {
            print("❌ Error generating digest: \(error)")
        }
    }
}
```

**Benefits**:
- ✅ **Reduces notification fatigue**: One summary instead of 50 individual items
- ✅ **Personalized insights**: AI understands user's interests
- ✅ **Highlights urgent items**: Mentions and DMs surfaced
- ✅ **Trending topics**: Shows what's popular
- ✅ **Beautiful UI**: Glassmorphic design with purple accents
- ✅ **Optional**: User can still view all individual notifications

---

## 📊 Comparison Matrix

| Feature | Current | Suggestion 1 | Suggestion 2 | Suggestion 3 |
|---------|---------|-------------|-------------|-------------|
| **Profile Photos** | 5-min cache, outdated | ✅ Real-time sync | N/A | N/A |
| **Duplicates** | Basic ID check | ✅ Fingerprinting | ✅ AI semantic detection | N/A |
| **Grouping** | Manual, limited | N/A | ✅ AI-powered smart groups | ✅ AI digest |
| **Performance** | Medium | ✅ Fast (cached) | Medium (AI call) | Medium (AI call) |
| **Cost** | Free | Free | ~$0.01/1000 notifs | ~$0.05/digest |
| **User Experience** | OK | ✅ Excellent | ✅ Excellent | ✅ Excellent |
| **Implementation Effort** | - | 2-3 hours | 4-6 hours | 3-4 hours |

---

## 🎯 Recommended Priority

**Phase 1 (Week 1)**: Implement Suggestion 1
- Fixes profile photo sync immediately
- Low effort, high impact
- No AI required (can add later)

**Phase 2 (Week 2)**: Implement Suggestion 2
- Eliminates duplicates with AI
- Smart grouping improves UX
- Moderate effort, high value

**Phase 3 (Week 3)**: Implement Suggestion 3
- Cherry on top for power users
- Reduces notification fatigue
- Great for engagement

---

## 💡 Quick Wins (No AI Required)

If you want to fix issues NOW without AI:

### 1. Fix Profile Photos (15 min)
```swift
// Use CachedAsyncImage instead of regular AsyncImage
CachedAsyncImage(
    url: URL(string: profilePhotoURL),
    content: { image in image.resizable() },
    placeholder: { ProgressView() }
)
```

### 2. Fix Duplicates (30 min)
```swift
// Add to NotificationService.swift
private func deduplicateNotifications(_ notifs: [AppNotification]) -> [AppNotification] {
    var seen = Set<String>()
    return notifs.filter { notif in
        let key = "\(notif.fromUserId)_\(notif.type.rawValue)_\(notif.postId ?? "")_\(roundToMinute(notif.timestamp))"
        return seen.insert(key).inserted
    }
}

private func roundToMinute(_ date: Date) -> Int {
    return Int(date.timeIntervalSince1970 / 60)
}
```

### 3. Better Grouping (1 hour)
```swift
// Group notifications by postId within 30-minute windows
private func groupNotifications(_ notifs: [AppNotification]) -> [NotificationGroup] {
    let grouped = Dictionary(grouping: notifs) { notif -> String in
        let timeWindow = Int(notif.timestamp.timeIntervalSince1970 / 1800)
        return "\(notif.postId ?? "standalone")_\(notif.type.rawValue)_\(timeWindow)"
    }

    return grouped.values.compactMap { NotificationGroup(notifications: $0) }
}
```

---

## 🚀 Next Steps

1. **Choose your approach**: AI-powered or quick wins?
2. **Start with Suggestion 1**: Fix profile photos first (biggest pain point)
3. **Add AI gradually**: Start with Suggestion 2 (duplicate detection)
4. **Polish with Suggestion 3**: Add digest feature for power users

Would you like me to implement any of these suggestions? I can start with the real-time profile photo sync (Suggestion 1) since it's the quickest to implement and has the biggest impact!
