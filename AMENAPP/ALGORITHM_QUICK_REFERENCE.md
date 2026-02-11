# Smart Algorithms - Quick Reference

## 🎯 Algorithm 1: Church Matching
**Purpose**: Personalized church recommendations

```swift
// Usage
let matcher = ChurchMatchingAlgorithm()
let matches = matcher.getTopMatches(
    from: churches,
    for: userPreferences,
    visitHistory: visitHistory
)

// Access in UI
sortMode = .smartMatch // Enables smart sorting
```

**Scoring Breakdown:**
- Distance: 30%
- Denomination: 25%
- Visit History: 20%
- Service Time: 15%
- Preferred Distance: 10%

---

## ⏰ Algorithm 2: Smart Notifications
**Purpose**: Optimal reminder timing

```swift
// Usage
let scheduler = SmartNotificationScheduler()
let time = scheduler.calculateOptimalReminderTime(
    for: church,
    preferences: preferences,
    visitHistory: history,
    userLocation: location
)
```

**Calculation:**
```
Reminder = ServiceTime - (PrepTime + TravelTime + 15min buffer)
```

---

## 📅 Algorithm 3: Service Prediction
**Purpose**: Accurate service times with holiday support

```swift
// Usage
let predictor = ServiceTimePrediction()
let nextService = predictor.predictNextService(
    for: church,
    from: Date()
)
```

**Special Handling:**
- Holidays (Christmas, Easter, Thanksgiving)
- Denomination patterns (Catholic Saturday Mass)
- Time parsing from service strings

---

## 🤝 Algorithm 4: Community Suggestions
**Purpose**: Privacy-safe church recommendations

```swift
// Usage
let matcher = CommunityMatcher()
let suggestions = matcher.findCommunitySuggestions(
    for: preferences,
    from: churches,
    visitHistory: history
)
```

**Similarity Score (0.0 - 1.0):**
- Denomination match: +0.4
- Similar visits: +0.3
- Distance: +0.2
- Diversity: +0.1

---

## 📊 Algorithm 5: Journey Insights
**Purpose**: Meaningful milestones and encouragement

```swift
// Usage
let insights = JourneyInsights()
let milestones = insights.generateInsights(
    for: preferences,
    visitHistory: history,
    savedChurches: saved
)
```

**Insight Types:**
- `milestone`: Major achievements
- `encouragement`: Progress recognition
- `suggestion`: Helpful tips

**Triggers:**
- 5+ visits: Explorer
- 10+ visits: Community Explorer
- 20+ visits: Champion
- 4+ visits/church: Growing Roots
- 3+ saved: Connected
- 2+ this week: Active

---

## 🔧 Integration Points

### When Church is Saved
```swift
func toggleSave(_ church: Church) {
    persistenceManager.saveChurch(church)
    scheduleSmartNotifications(for: church) // ← Uses Algorithm 2
    updateJourneyInsights() // ← Uses Algorithm 5
}
```

### When Church is Checked In
```swift
func checkInToChurch(_ church: Church) {
    let visit = ChurchVisit(
        churchId: church.id,
        date: Date(),
        arrivalTime: Date() // ← Tracked for Algorithm 2
    )
    churchVisitHistory.append(visit)
    userPreferences.preferredDenominations.insert(church.denomination) // ← Feeds Algorithm 1
    updateJourneyInsights() // ← Updates Algorithm 5
}
```

### When Searching Churches
```swift
var filteredChurches: [Church] {
    switch sortMode {
    case .smartMatch:
        // Use Algorithm 1
        let matcher = ChurchMatchingAlgorithm()
        return matcher.getTopMatches(...).map { $0.church }
    case .nearest:
        return churches.sorted { $0.distanceValue < $1.distanceValue }
    // ...
    }
}
```

---

## 📱 UI Integration

### Journey Insights Display
```swift
// In main church list
if !journeyInsights.isEmpty {
    ForEach(journeyInsights) { insight in
        JourneyInsightCard(insight: insight)
    }
}
```

### Smart Match Toggle
```swift
// In filter row
Menu {
    ForEach(ChurchSortMode.allCases, id: \.self) { mode in
        Button(mode.rawValue) {
            sortMode = mode
        }
    }
} label: {
    Text(sortMode.rawValue)
}
```

---

## 💾 Data Persistence

### User Preferences
```swift
struct UserChurchPreferences: Codable {
    var preferredDenominations: Set<String>
    var typicalAttendanceDay: Int?
    var prepTimeMinutes: Int
    var visitedChurches: Set<UUID>
}
```

### Visit History
```swift
struct ChurchVisit: Codable {
    let churchId: UUID
    let date: Date
    let arrivalTime: Date?
    let wasOnTime: Bool?
}
```

### Saving/Loading
```swift
// Save
func saveUserPreferences() {
    let encoder = JSONEncoder()
    let data = try encoder.encode(userPreferences)
    UserDefaults.standard.set(data, forKey: "userChurchPreferences")
    updateJourneyInsights() // ← Refresh insights
}

// Load
func loadUserPreferences() {
    if let data = UserDefaults.standard.data(forKey: "userChurchPreferences") {
        userPreferences = try JSONDecoder().decode(UserChurchPreferences.self, from: data)
        updateJourneyInsights() // ← Initialize insights
    }
}
```

---

## 🔍 Debugging

### Logging
```swift
// Enable detailed logging
print("🎯 Match score for \(church.name): \(score)")
print("⏰ Optimal reminder time: \(reminderTime)")
print("📅 Next service predicted: \(nextService)")
print("📊 Generated \(insights.count) insights")
```

### Testing Scenarios

**Test Matching:**
```swift
// Create test user with preferences
var testPrefs = UserChurchPreferences()
testPrefs.preferredDenominations = ["Baptist", "Methodist"]
testPrefs.maxPreferredDistance = 10.0

// Test scoring
let score = matcher.scoreChurch(church, for: testPrefs, visitHistory: [])
// Score should be 0-100
```

**Test Notifications:**
```swift
// Mock user with history
var testHistory: [ChurchVisit] = [
    ChurchVisit(churchId: church.id, date: Date(), arrivalTime: Date())
]

// Calculate reminder
let reminderTime = scheduler.calculateOptimalReminderTime(...)
// Should be before service time
```

**Test Insights:**
```swift
// Simulate 10 church visits
var testPrefs = UserChurchPreferences()
testPrefs.visitedChurches = Set((0..<10).map { _ in UUID() })

// Generate insights
let insights = JourneyInsights().generateInsights(...)
// Should include "Community Explorer" milestone
```

---

## ⚡ Performance Tips

### Optimization
```swift
// ✅ Cache scores for current search
let scoredChurches = churches.map { church in
    (church: church, score: matcher.scoreChurch(...))
}
.sorted { $0.score > $1.score }

// ❌ Don't recalculate on every access
var filteredChurches: [Church] {
    // This gets called multiple times!
}
```

### Memory
```swift
// ✅ Limit history to recent 100 visits
churchVisitHistory = churchVisitHistory
    .sorted { $0.date > $1.date }
    .prefix(100)
    .map { $0 }

// ✅ Clean up old preferences
userPreferences.visitedChurches = userPreferences.visitedChurches
    .filter { id in churches.contains { $0.id == id } }
```

---

## 🛡️ Privacy Checklist

- [x] All computation on device
- [x] No server-side analytics
- [x] No personal data sharing
- [x] User owns all data
- [x] Can clear history anytime
- [x] Transparent scoring
- [x] Anonymous suggestions only

---

## 🚀 Quick Start

### Enable All Algorithms
```swift
// 1. Set default sort to Smart Match
@State private var sortMode: ChurchSortMode = .smartMatch

// 2. Load preferences on appear
.onAppear {
    loadUserPreferences()
}

// 3. Update insights on changes
.onChange(of: persistenceManager.savedChurches) {
    updateJourneyInsights()
}

// 4. Use smart notifications
func toggleSave(_ church: Church) {
    persistenceManager.saveChurch(church)
    scheduleSmartNotifications(for: church)
}
```

---

## 📞 Support

### Common Issues

**Q: Smart Match not working?**
A: User needs at least 1 visit or saved church for personalization

**Q: No journey insights?**
A: Need 3+ saved churches or 5+ visits to unlock first insights

**Q: Notifications at wrong time?**
A: Check user's prepTimeMinutes preference (default: 30 min)

**Q: Service predictions inaccurate?**
A: Verify church.serviceTime format matches expected patterns

---

**Last Updated**: February 2, 2026
