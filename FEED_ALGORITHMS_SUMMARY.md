# Feed Algorithms Summary

## Overview
This document outlines the algorithms used for content ranking and display in OpenTable, PrayerView, and TestimoniesView.

---

## 1. OpenTable Algorithm ✅ FULLY IMPLEMENTED

**File:** `HomeFeedAlgorithm.swift` (Lines 1-303)
**Implementation Status:** Production-ready with intelligent personalization

### Algorithm Components

#### A. Post Scoring System (0-100 points)
Each post receives a personalized relevance score based on 5 weighted factors:

1. **Recency Score (25%)** - Time-based ranking
   - Brand new (< 1 hour): 100 points
   - Very recent (< 6 hours): 90 points
   - Recent (< 1 day): 70 points
   - Somewhat old (< 3 days): 40 points
   - Older: Gradual decay (minimum 10 points)

2. **Topic Relevance (30%)** - User's interests
   - Matches engaged topics: Variable (0-100)
   - Content keyword matching: Averaged score
   - Baseline neutral: 50 points

3. **Author Affinity (15%)** - Relationship with author
   - New author: 30 points (neutral)
   - Frequent engagement: Logarithmic scaling
   - Formula: `30 + (log(engagementCount + 1) * 20)`
   - Maximum: 100 points

4. **Engagement Quality (20%)** - Community validation
   - Weighted formula: `(commentCount × 3.0) + (amenCount × 1.5)`
   - Low engagement (< 5): 30 points
   - Moderate (< 20): 50 points
   - Good (< 50): 70 points
   - High (< 100): 85 points
   - Viral (100+): `85 + log(total - 100) × 3` (max 100)

5. **Diversity Bonus (10%)** - Prevent echo chamber
   - Unexplored categories: 70 points
   - Moderately engaged: 50 points
   - Heavily engaged: 20 points

#### B. User Interest Tracking
**File:** `HomeFeedAlgorithm.swift` (Lines 25-36)

```swift
struct UserInterests {
    var engagedTopics: [String: Double]       // Topic → Score (0-100)
    var engagedAuthors: [String: Int]         // AuthorID → Engagement count
    var interactionHistory: [String: Int]     // PostID → Interactions
    var preferredCategories: [String: Double] // Category → Preference (0-100)
    var lastUpdate: Date
}
```

#### C. Interaction Types & Score Boosts
**File:** `HomeFeedAlgorithm.swift` (Lines 206-232)

| Interaction | Score Boost | Weight |
|------------|-------------|---------|
| View | +1 | 1 |
| Reaction | +5 | 2 |
| Comment | +10 | 3 |
| Share | +15 | 4 |
| Long Read (>10s) | +8 | 2 |

#### D. Personalization Implementation
**File:** `ContentView.swift` (Lines 3247-3264)

```swift
private func personalizeFeeds() {
    Task.detached(priority: .userInitiated) {
        let ranked = await feedAlgorithm.rankPosts(
            postsManager.openTablePosts,
            for: feedAlgorithm.userInterests
        )
        personalizedPosts = ranked
    }
}
```

**Features:**
- ✅ Runs off main thread for performance
- ✅ Real-time updates on new posts
- ✅ Persistent user interests (saved to UserDefaults)
- ✅ Automatic learning from interactions
- ✅ 24-hour staleness check for refresh

### OpenTable Display Logic
**File:** `ContentView.swift` (Lines 3156-3167)

```swift
let displayPosts = hasPersonalized && !personalizedPosts.isEmpty
    ? personalizedPosts
    : postsManager.openTablePosts

ForEach(displayPosts) { post in
    PostCard(post: post, isUserPost: isCurrentUserPost(post))
        .onAppear {
            feedAlgorithm.recordInteraction(with: post, type: .view)
        }
}
```

**Behavior:**
- Shows personalized feed when available
- Falls back to chronological feed if personalization hasn't run
- Tracks views automatically for continuous learning

---

## 2. TestimoniesView Algorithm ⚠️ BASIC SORTING

**File:** `TestimoniesView.swift` (Lines 40-64)
**Implementation Status:** Client-side filtering with basic sorting

### Current Algorithm

#### A. Filtering Options
**File:** `TestimoniesView.swift` (Lines 32-37)

```swift
enum TestimonyFilter {
    case all      // No sorting
    case recent   // Chronological (default from Firestore)
    case popular  // Engagement-based sorting
    case following // Not implemented (TODO)
}
```

#### B. Sorting Logic
**File:** `TestimoniesView.swift` (Lines 50-61)

```swift
var filteredPosts: [Post] {
    var posts = postsManager.testimoniesPosts

    // Category filter
    if let category = selectedCategory {
        posts = posts.filter {
            post.topicTag?.lowercased() == category.title.lowercased()
        }
    }

    // Sorting
    switch selectedFilter {
    case .all, .recent:
        // Already sorted by timestamp in RealtimePostService
        break
    case .popular:
        posts.sort {
            $0.amenCount + $0.commentCount > $1.amenCount + $1.commentCount
        }
    case .following:
        // TODO: Not implemented
        break
    }

    return posts
}
```

### What's Missing
- ❌ No personalized ranking
- ❌ No user interest tracking
- ❌ No author affinity scoring
- ❌ Following filter not implemented
- ⚠️ Simple engagement count sorting (not weighted)

### Recommendations for Improvement

**Option 1: Apply HomeFeedAlgorithm to Testimonies**
```swift
// In TestimoniesView
@StateObject private var feedAlgorithm = HomeFeedAlgorithm.shared

var filteredPosts: [Post] {
    var posts = postsManager.testimoniesPosts

    // Apply category filter
    if let category = selectedCategory {
        posts = posts.filter { ... }
    }

    // Apply intelligent sorting
    switch selectedFilter {
    case .popular:
        posts = feedAlgorithm.rankPosts(posts, for: feedAlgorithm.userInterests)
    case .following:
        // Implement following filter
        posts = posts.filter { isFollowing($0.authorId) }
    default:
        break // Keep chronological
    }

    return posts
}
```

**Option 2: Create TestimoniesAlgorithm (faith-specific)**
- Weight inspirational content higher
- Prioritize answered prayers
- Boost recent testimonies from same church/community
- Surface diverse testimony types (healing, provision, answered prayer)

---

## 3. PrayerView Algorithm ⚠️ SIMPLE TAG FILTERING

**File:** `PrayerView.swift` (Lines 210-221)
**Implementation Status:** Basic tab-based filtering only

### Current Algorithm

#### A. Tab Filtering
**File:** `PrayerView.swift` (Lines 30-34)

```swift
enum PrayerTab {
    case requests  // "Prayer Request" tag
    case praises   // "Praise Report" tag
    case answered  // "Answered Prayer" tag
}
```

#### B. Filtering Logic
**File:** `PrayerView.swift` (Lines 210-221)

```swift
let filteredPrayerPosts = postsManager.prayerPosts.filter { post in
    guard let topicTag = post.topicTag else { return false }

    switch selectedTab {
    case .requests:
        return topicTag == "Prayer Request"
    case .praises:
        return topicTag == "Praise Report"
    case .answered:
        return topicTag == "Answered Prayer"
    }
}

ForEach(filteredPrayerPosts) { post in
    PrayerPostCard(post: post)
}
```

### What's Missing
- ❌ No sorting algorithm at all
- ❌ No urgency prioritization
- ❌ No personalization
- ❌ No community relevance scoring
- ⚠️ Posts appear in Firestore timestamp order only

### Recommendations for Improvement

**Prayer-Specific Algorithm Features:**

1. **Urgency Scoring**
   - Recent requests (< 24h): Higher priority
   - Unanswered requests (> 7 days): Resurface periodically
   - Emergency tags: Immediate top priority

2. **Community Relevance**
   - Same church/group: +20 points
   - Mutual followers: +15 points
   - Same location: +10 points
   - Similar prayer topics: +10 points

3. **Engagement Boost**
   - Few prayers (< 3): Boost visibility
   - Many prayers (> 20): Reduce frequency
   - Prevent "prayer rich get richer" effect

4. **Answered Prayer Celebration**
   - Surface answered prayers to encourage faith
   - Show "Before & After" for updates
   - Celebrate testimony connections

**Sample Implementation:**
```swift
struct PrayerAlgorithm {
    func scorePrayerRequest(_ post: Post) -> Double {
        var score: Double = 0.0

        // 1. Urgency (30%)
        score += calculateUrgencyScore(post) * 0.30

        // 2. Community Relevance (25%)
        score += calculateCommunityScore(post) * 0.25

        // 3. Prayer Gap (20%) - Needs more prayers
        score += calculatePrayerGapScore(post) * 0.20

        // 4. Recency (15%)
        score += calculateRecencyScore(post) * 0.15

        // 5. Topic Relevance (10%)
        score += calculateTopicScore(post) * 0.10

        return score
    }

    private func calculatePrayerGapScore(_ post: Post) -> Double {
        let prayerCount = post.amenCount // "Amen" = prayer

        if prayerCount < 3 {
            return 100 // Urgent: needs prayers
        } else if prayerCount < 10 {
            return 70 // Moderate need
        } else if prayerCount < 20 {
            return 40 // Good coverage
        } else {
            return 20 // Well-prayed-for
        }
    }
}
```

---

## Algorithm Comparison Table

| Feature | OpenTable | Testimonies | Prayer |
|---------|-----------|-------------|--------|
| **Personalization** | ✅ Full | ❌ None | ❌ None |
| **Interest Tracking** | ✅ Yes | ❌ No | ❌ No |
| **Engagement Scoring** | ✅ Weighted | ⚠️ Simple sum | ❌ No scoring |
| **Author Affinity** | ✅ Yes | ❌ No | ❌ No |
| **Recency Boost** | ✅ Exponential decay | ⚠️ Firestore order | ⚠️ Firestore order |
| **Diversity Bonus** | ✅ Yes | ❌ No | ❌ No |
| **Off-thread Processing** | ✅ Yes | ❌ No | ❌ No |
| **Persistent Learning** | ✅ UserDefaults | ❌ No | ❌ No |
| **Category Filtering** | ✅ Via interests | ✅ Manual | ✅ Tabs only |
| **Following Filter** | ❌ No | ❌ TODO | ❌ No |

---

## Performance Characteristics

### OpenTable
- **Complexity:** O(n log n) for sorting
- **Processing:** Background thread (`.userInitiated` priority)
- **Memory:** Stores user interests in UserDefaults (~1-5KB)
- **Updates:** Real-time with optimistic UI
- **Staleness:** 24-hour automatic refresh

### Testimonies
- **Complexity:** O(n) for filtering, O(n log n) for popular sort
- **Processing:** Main thread (synchronous)
- **Memory:** No persistent state
- **Updates:** Real-time via PostsManager
- **Staleness:** Always fresh (no caching)

### Prayer
- **Complexity:** O(n) for tag filtering only
- **Processing:** Main thread (synchronous)
- **Memory:** No persistent state
- **Updates:** Real-time via PostsManager
- **Staleness:** Always fresh (no caching)

---

## Real-Time Updates

All three feeds use **FirebasePostService.shared.startListening()** for real-time updates:

**OpenTable:**
```swift
.task {
    FirebasePostService.shared.startListening(category: .openTable)
}
```

**Testimonies:**
```swift
.onAppear {
    FirebasePostService.shared.startListening(category: .testimonies)
}
```

**Prayer:**
```swift
// Uses PostsManager.shared.prayerPosts
// Listener started in PostsManager initialization
```

---

## Next Steps for Enhancement

### Priority 1: Enhance Testimonies Algorithm
- [ ] Apply HomeFeedAlgorithm for personalization
- [ ] Implement following filter
- [ ] Add weighted engagement scoring
- [ ] Track testimony interactions for learning

### Priority 2: Build Prayer-Specific Algorithm
- [ ] Create PrayerAlgorithm class
- [ ] Implement urgency scoring
- [ ] Add community relevance
- [ ] Surface unanswered prayers
- [ ] Celebrate answered prayers

### Priority 3: Advanced Features (All Feeds)
- [ ] Implement following filter across all feeds
- [ ] Add location-based relevance
- [ ] Build church/group affinity
- [ ] Create cross-feed learning (prayer → testimony connections)
- [ ] Add A/B testing framework for algorithm tuning

---

## Summary

✅ **OpenTable**: Production-ready intelligent algorithm with full personalization
⚠️ **Testimonies**: Basic sorting, needs personalization enhancement
⚠️ **Prayer**: Simple filtering only, needs custom algorithm

**Recommendation**: Extend HomeFeedAlgorithm to Testimonies with minor tweaks, and create a specialized PrayerAlgorithm with urgency and community relevance scoring.
