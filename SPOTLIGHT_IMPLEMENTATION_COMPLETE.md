# Spotlight Implementation Complete
**Date:** February 23, 2026  
**Status:** ✅ READY FOR INTEGRATION

---

## 🎯 Overview

Spotlight is AMEN's intelligent content discovery feature that surfaces meaningful, high-quality content using multi-dimensional ranking. Built with AMEN's existing design system:
- White background
- Glassmorphic cards
- Spatial animations
- Black text with clear typography
- Clean, minimal UI

---

## 📦 Files Created

### 1. SpotlightView.swift ✅
**Location:** `AMENAPP/SpotlightView.swift`  
**Purpose:** Main Spotlight screen with scroll effects and filter chips

**Features:**
- Clean white background matching AMEN design
- Collapsible header with smooth scroll animations
- Filter chips (For You, Prayer, Testimonies, Discussions, Local)
- Loading skeleton with shimmer effect
- "You're all caught up" end state
- Pull-to-refresh support
- Compact nav bar appears on scroll

**Design Details:**
- Matches PostCard glassmorphic style
- Uses LiquidSpring animations for premium feel
- Filter chips with haptic feedback
- Staggered card entrance animations (0.03s delay)

### 2. SpotlightCard.swift ✅
**Location:** `AMENAPP/SpotlightCard.swift`  
**Purpose:** Individual post card matching AMEN's PostCard design

**Features:**
- Glassmorphic background with white gradient
- Author header with profile image/initials
- Category badges (Prayer, Testimony, etc.)
- Spotlight explanation badge (why this post was selected)
- Interaction bar (lightbulb, comments, share, bookmark)
- Post images with CachedAsyncImage
- Elastic press animation on tap

**Design Details:**
- `.ultraThinMaterial` for glass effect
- Black text on white background
- Subtle shadows (0.04 opacity, 8pt radius)
- 16pt padding, 16pt corner radius
- Matches existing PostCard interaction patterns

### 3. SpotlightViewModel.swift ✅
**Location:** `AMENAPP/SpotlightViewModel.swift`  
**Purpose:** View model with smart ranking algorithm

**Features:**
- Multi-source post fetching (following, community, discovery)
- Intelligent scoring and ranking
- Diversity enforcement (1 post per author per 10 items)
- Safety and quality filtering
- Explanation generation
- Filter support

**Ranking Algorithm:**
```
SpotlightScore = (
    0.30 × QualityScore +      // Content quality, specificity
    0.25 × RelevanceScore +     // Follow graph, interests
    0.20 × SafetyScore +        // Moderation confidence
    0.15 × FreshnessScore +     // Time decay
    0.10 × EngagementScore      // Reactions, comments, reposts
)
```

**Quality Signals:**
- Content length (30-500 chars optimal)
- Specificity (names, dates, details)
- Media presence
- Proper formatting

**Safety Checks:**
- Minimum content length (20 chars)
- Safety score > 0.6 required
- Quality score > 0.4 required
- Basic spam detection

### 4. Supporting Components ✅
- `FilterChipButton` - Animated filter chips
- `InteractionButton` - Reaction buttons with scale effect
- `SpotlightCardSkeleton` - Loading state with shimmer
- `ShareSheet` - Native iOS share functionality
- `ScrollOffsetPreferenceKey` - Scroll tracking

---

## 🔌 Integration Steps

### Step 1: Add Spotlight to ContentView

In `AMENAPP/ContentView.swift`, add Spotlight as a new tab:

```swift
// Around line 200 in selectedTabView switch statement
switch viewModel.selectedTab {
case 0:
    HomeView()
        .id("home")
case 1:
    PeopleDiscoveryView()
        .id("people")
case 2:
    MessagesView()
        .id("messages")
case 3:  // NEW: Add Spotlight tab
    SpotlightView()
        .id("spotlight")
        .task {
            NotificationAggregationService.shared.updateCurrentScreen(.home)
        }
case 4:
    ResourcesView()
        .id("resources")
// ... rest of tabs
```

### Step 2: Add Spotlight Icon to CompactTabBar

In the `CompactTabBar` struct (around line 4850+), add spotlight icon:

```swift
// Add spotlight icon between People and Messages tabs
Button(action: { selectedTab = 3 }) {
    VStack(spacing: 4) {
        Image(systemName: "star.circle.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(selectedTab == 3 ? .amenGold : .secondary)
        
        if selectedTab == 3 {
            Circle()
                .fill(Color.amenGold)
                .frame(width: 4, height: 4)
        }
    }
}
```

### Step 3: Update Tab Indices

If adding Spotlight at position 3, update all subsequent tab indices:
- Messages: 2 → 2 (stays same)
- Spotlight: NEW → 3
- Resources: 4 → 4 (stays same)
- Notifications: 5 → 5 (stays same)
- Profile: 6 → 6 (stays same)

---

## 🎨 Design System Compliance

### ✅ Colors Used
- Background: `Color.white`
- Text Primary: `Color.black`
- Text Secondary: `Color.secondary`
- Accent: `Color.amenGold`
- Glass: `.ultraThinMaterial`

### ✅ Typography
- Headers: `.system(size: 34, weight: .bold, design: .rounded)`
- Subheaders: `.system(size: 18, weight: .semibold)`
- Body: `.system(size: 16, weight: .regular)`
- Captions: `.system(size: 13-15, weight: .medium)`

### ✅ Spacing
- Card padding: 16pt
- Card spacing: 16pt vertical
- Edge padding: 20pt horizontal
- Corner radius: 16pt (cards), 12pt (images)

### ✅ Animations
- Spring animations: `LiquidSpring.quick` (0.25s response, 0.7 damping)
- Press effects: 0.98 scale with 0.3s spring
- Staggered entrances: 0.03s delay between cards
- Scroll-based: easeOut with 0.25-0.4s duration

---

## 📊 Ranking Algorithm Details

### Quality Score (0.0-1.0)
**Weight: 30%**

Measures content quality through:
- **Content length:** 100-300 chars = optimal (0.8-1.0)
- **Specificity:** Presence of names, dates, details (+0.25 each signal)
- **Media:** Has image = +0.2 bonus
- **Formula:** `0.5×length + 0.3×specificity + 0.2×media`

### Relevance Score (0.0-1.0)
**Weight: 25%**

Measures personal relevance through:
- **Follow graph:** Direct follow = 1.0, community = 0.5
- **Recency:** <24h = 1.0, <72h = 0.7, older = 0.5
- **Formula:** `0.6×followScore + 0.4×recencyScore`

### Safety Score (0.0-1.0)
**Weight: 20%**

Measures content safety through:
- **Minimum threshold:** 0.6 required for eligibility
- **Content length:** <20 chars = penalty
- **Formatting:** Proper capitalization = +0.1
- **Base:** 1.0 with penalties applied

### Freshness Score (0.0-1.0)
**Weight: 15%**

Time-based decay:
- **Formula:** `exp(-ageHours / 24.0)`
- **Half-life:** 24 hours
- **Result:** Posts decay exponentially over time

### Engagement Score (0.0-1.0)
**Weight: 10%**

Weighted engagement rate:
- **Lightbulbs:** 1× weight
- **Comments:** 2× weight (more valuable)
- **Reposts:** 3× weight (highest value)
- **Time-adjusted:** Divided by age in hours
- **Target:** 5 engagements/hour = 1.0 score

---

## 🛡️ Safety & Quality Gates

### Eligibility Criteria

**Posts must pass ALL checks:**
- ✅ Safety score > 0.6
- ✅ Quality score > 0.4
- ✅ Content length ≥ 20 characters
- ✅ Total score > 0.3

**Ineligible posts are filtered out before display**

### Diversity Enforcement

To prevent repetition and promote variety:
- **Author diversity:** Max 1 post per author per 10 items
- **Reset window:** Tracking resets every 10 posts
- **Result:** More diverse voices in Spotlight

---

## 🔄 Data Flow

### 1. Candidate Fetching
```
User opens Spotlight
    ↓
Fetch from 3 sources (parallel):
    - Following posts (last 7 days)
    - Community posts (church/local)
    - Discovery posts (high-quality)
    ↓
Combine & deduplicate
```

### 2. Scoring & Ranking
```
For each candidate post:
    ↓
Calculate 5 scores:
    - Quality (content analysis)
    - Relevance (user context)
    - Safety (moderation)
    - Freshness (time decay)
    - Engagement (interactions)
    ↓
Weighted total score
    ↓
Check eligibility gates
```

### 3. Display
```
Filter eligible posts (score > threshold)
    ↓
Enforce diversity (1 per author/10)
    ↓
Take top 30 posts
    ↓
Display with explanations
```

---

## 📱 User Experience

### Loading States
1. **Initial load:** Shimmer skeleton (3 cards)
2. **Empty state:** "No Spotlight content yet" with icon
3. **End state:** "You're all caught up" with checkmark

### Interactions
1. **Tap card:** Opens PostDetailView
2. **Tap filter:** Reloads with category filter
3. **Pull down:** Refresh content
4. **Scroll down:** Header collapses, compact nav appears
5. **Tap reaction:** Bounces with haptic feedback

### Explanations
Each card shows why it was selected:
- "High-quality post with low visibility"
- "Popular in your community"
- "Prayer request needing support"
- "Testimony from your community"
- "Recommended for you"

---

## 🔧 Configuration Options

### Adjust Ranking Weights
In `SpotlightRankingEngine.calculateSpotlightScore()`:
```swift
let totalScore = (
    0.30 × quality +      // Increase to prioritize quality
    0.25 × relevance +    // Increase for more personalization
    0.20 × safety +       // Increase for stricter safety
    0.15 × freshness +    // Increase for newer posts
    0.10 × engagement     // Increase for viral content
)
```

### Adjust Content Limits
In `SpotlightViewModel.loadSpotlight()`:
```swift
spotlightPosts = Array(diverse.prefix(30))  // Change to show more/less
```

### Adjust Time Windows
In `SpotlightViewModel.fetchFollowingPosts()`:
```swift
let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)  // Change lookback period
```

---

## 🧪 Testing Checklist

### Visual Testing
- [ ] White background renders correctly
- [ ] Cards have glassmorphic effect
- [ ] Filter chips animate smoothly
- [ ] Loading skeletons shimmer
- [ ] Scroll animations are smooth (60fps)
- [ ] Compact nav appears on scroll
- [ ] Empty state displays correctly
- [ ] End state displays correctly

### Functional Testing
- [ ] Posts load from Firestore
- [ ] Ranking algorithm scores posts
- [ ] Safety gates filter unsafe content
- [ ] Diversity prevents author repetition
- [ ] Filters reload with correct category
- [ ] Pull-to-refresh works
- [ ] Tap opens PostDetailView
- [ ] Reactions have haptic feedback

### Performance Testing
- [ ] Initial load < 2 seconds
- [ ] Scroll maintains 60fps
- [ ] Memory usage stable
- [ ] No layout jumpiness
- [ ] Card animations don't lag

---

## 🚀 Launch Recommendations

### Phase 1: Soft Launch (Week 1)
- Enable for 10% of users
- Monitor engagement metrics
- Collect user feedback
- Track performance

### Phase 2: Refinement (Week 2-3)
- Adjust ranking weights based on data
- Fine-tune safety thresholds
- Optimize diversity algorithm
- Fix any performance issues

### Phase 3: Full Launch (Week 4)
- Roll out to 100% of users
- Add Spotlight to onboarding
- Track quality metrics
- Iterate based on usage

---

## 📊 Metrics to Track

### Quality Metrics
- Average quality score of shown posts
- User feedback ratio (positive/negative)
- Content diversity (unique authors per 50 posts)

### Engagement Metrics
- Session time in Spotlight (target: 5-10 min)
- Tap-through rate to post detail
- Reaction rate on Spotlight posts

### Safety Metrics
- Report rate for Spotlight posts (target: <0.5%)
- Average safety score (target: >0.8)
- Eligibility filter rate

### Health Metrics
- Return rate (target: 60% daily)
- Completion rate (reach "caught up")
- Time to "caught up" (healthy engagement)

---

## 🎯 Success Criteria

**Spotlight is successful if:**
- ✅ Users discover 5+ new creators per session
- ✅ Session time is 5-15 min (not 30+)
- ✅ 40%+ of users reach "You're all caught up"
- ✅ Report rate < 0.5%
- ✅ 60%+ daily return rate
- ✅ Quality score average > 0.7

---

## 🔮 Future Enhancements

### V2 Features (Optional)
1. **Sections:** "Community Pulse", "Quiet Gems", "Trending"
2. **Personalization:** Machine learning for user preferences
3. **Real-time updates:** New posts appear at top
4. **Saved spotlights:** Bookmark spotlight moments
5. **Share spotlight:** "Check out this post I found"

### Algorithm Improvements
1. **Collaborative filtering:** "People like you also enjoyed"
2. **Topic modeling:** Better category detection
3. **Quality prediction:** Pre-score posts on creation
4. **Abuse detection:** Engagement manipulation detection

---

## 📝 Notes

### Why These Design Choices

**White background:**
- Matches AMEN's existing light mode design
- Better for reading text-heavy posts
- Premium, clean aesthetic

**Glassmorphic cards:**
- Consistent with PostCard design
- Modern iOS feel
- Spatial depth

**Quality over virality:**
- Prioritizes meaningful content
- Reduces doom-scrolling
- Aligns with AMEN's mission

**Diversity enforcement:**
- Prevents repetitive content
- Amplifies smaller voices
- Better discovery experience

---

## ✅ Implementation Complete

**All files created and ready for integration!**

**Next steps:**
1. Add Spotlight tab to ContentView (1 line)
2. Add Spotlight icon to CompactTabBar (5 lines)
3. Update tab indices if needed
4. Test in simulator
5. Deploy to TestFlight

**Estimated integration time:** 15 minutes  
**Files to modify:** 1 (ContentView.swift)

---

**Built with AMEN's design system. Ready to ship.** 🎉
