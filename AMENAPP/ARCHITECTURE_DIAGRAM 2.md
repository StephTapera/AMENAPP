# 🏗️ Architecture Overview - Search Features

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      SearchView (Main)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Search Bar   │  │ Filter Chips │  │ Menu Button  │       │
│  │ with         │  │              │  │ (Save/View)  │       │
│  │ Autocomplete │  │              │  │              │       │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘       │
│         │                                    │               │
└─────────┼────────────────────────────────────┼───────────────┘
          │                                    │
          ▼                                    ▼
┌─────────────────────┐            ┌─────────────────────┐
│ SearchSuggestions   │            │  SavedSearch        │
│ Service             │            │  Service            │
│                     │            │                     │
│ • Real-time queries │            │ • Save searches     │
│ • Category detect   │            │ • Alert management  │
│ • Recent cache      │            │ • Background check  │
│ • Debouncing        │            │ • Notifications     │
└──────────┬──────────┘            └──────────┬──────────┘
           │                                  │
           ▼                                  ▼
┌──────────────────────────────────────────────────────────┐
│                     Firestore Database                     │
│  ┌───────────┐  ┌───────────┐  ┌──────────┐              │
│  │   users   │  │  groups   │  │ saved    │              │
│  │           │  │           │  │ Searches │              │
│  │ search    │  │ search    │  └────┬─────┘              │
│  │ Keywords  │  │ Keywords  │       │                    │
│  └───────────┘  └───────────┘       ▼                    │
│                              ┌──────────┐                 │
│                              │ search   │                 │
│                              │ Alerts   │                 │
│                              └──────────┘                 │
└──────────────────────────────────────────────────────────┘
```

---

## Component Interaction Flow

### 🔍 Search Suggestions Flow

```
User Types Query
       │
       ▼
┌─────────────────┐
│ Debounce 300ms  │
└────────┬────────┘
         │
         ▼
┌──────────────────────┐
│ SearchSuggestions    │
│ Service.getSuggestions│
└────────┬─────────────┘
         │
         ├─► Check if starts with "@" → User suggestions
         │
         ├─► Check if starts with "#" → Topic suggestions
         │
         ├─► General query → All categories
         │
         └─► Load recent searches
                │
                ▼
        ┌──────────────┐
        │ Firebase     │
        │ Queries      │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │ Filter &     │
        │ Sort Results │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │ Display      │
        │ Dropdown     │
        └──────────────┘
```

### 💾 Saved Search Flow

```
User Searches Query
       │
       ▼
Tap "Save Search"
       │
       ▼
┌─────────────────┐
│ SaveSearchSheet │
│ Appears         │
└────────┬────────┘
         │
         ▼
Enable Notifications?
         │
    ┌────┴────┐
    │   Yes   │   No
    ▼         ▼
┌─────────────────┐
│ SavedSearch     │
│ Service.save()  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Save to         │
│ Firestore       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Trigger Initial │
│ Check           │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Create Alert    │
│ if results found│
└─────────────────┘
```

### 🔔 Alert System Flow

```
Background Timer (15 min)
       │
       ▼
┌──────────────────────┐
│ For each saved       │
│ search with          │
│ notifications ON     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Perform search query │
│ against live data    │
└──────────┬───────────┘
           │
           ▼
    New results?
    ┌────┴────┐
    │   Yes   │   No
    ▼         ▼
┌─────────────┐  Do nothing
│ Create      │
│ Alert       │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Send Push   │
│ Notification│
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Save to     │
│ searchAlerts│
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Update      │
│ trigger     │
│ count       │
└─────────────┘
```

---

## Data Flow Diagram

```
┌────────────────────────────────────────────────────────┐
│                     User Actions                        │
└───────────────┬────────────────────────────────────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌────────┐ ┌────────┐ ┌─────────┐
│ Type   │ │ Save   │ │ View    │
│ Search │ │ Search │ │ Alerts  │
└───┬────┘ └───┬────┘ └────┬────┘
    │          │           │
    │          │           │
    ▼          ▼           ▼
┌──────────────────────────────────┐
│      Service Layer               │
│                                  │
│  SearchSuggestions  SavedSearch │
│       Service        Service     │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│     Data Layer (Firestore)       │
│                                  │
│  users, groups, savedSearches,  │
│  searchAlerts                    │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────┐
│      Cache & State               │
│                                  │
│  @Published properties           │
│  UserDefaults (recent searches)  │
└──────────────────────────────────┘
```

---

## State Management

### SearchSuggestionsService
```swift
@Published var suggestions: [SearchSuggestion] = []
@Published var isLoading: Bool = false

private var searchTask: Task<Void, Never>?
private var recentSearches: [String] = []
```

### SavedSearchService
```swift
@Published var savedSearches: [SavedSearch] = []
@Published var searchAlerts: [SearchAlert] = []
@Published var isLoading: Bool = false
@Published var error: String?
```

---

## Background Processing

```
┌──────────────────────────────────────┐
│        App Lifecycle                 │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  BGTaskScheduler                     │
│  Identifier: com.amenapp.searchcheck │
└──────────────┬───────────────────────┘
               │
               │ Every 15 minutes
               ▼
┌──────────────────────────────────────┐
│  SavedSearchService                  │
│  .checkAllSavedSearches()            │
└──────────────┬───────────────────────┘
               │
               │ For each saved search
               ▼
┌──────────────────────────────────────┐
│  SearchService                       │
│  .search(query: _, filter: _)        │
└──────────────┬───────────────────────┘
               │
               │ If new results
               ▼
┌──────────────────────────────────────┐
│  Create Alert                        │
│  Send Notification                   │
└──────────────────────────────────────┘
```

---

## Database Schema

### savedSearches Collection
```
{
  id: "uuid",
  userId: "user123",
  query: "prayer",
  filters: ["Posts", "Groups"],
  notificationsEnabled: true,
  createdAt: Timestamp,
  lastTriggered: Timestamp,
  triggerCount: 5
}
```

### searchAlerts Collection
```
{
  id: "uuid",
  userId: "user123",
  savedSearchId: "search_uuid",
  query: "prayer",
  resultCount: 3,
  newResults: ["post1", "post2", "post3"],
  createdAt: Timestamp,
  isRead: false
}
```

### users Collection (Updated)
```
{
  id: "user123",
  displayName: "John Doe",
  username: "johndoe",
  searchKeywords: [
    "john", "doe", "johndoe",
    "j", "jo", "joh", "john",
    "d", "do", "doe"
  ],
  ... other fields
}
```

---

## UI Component Hierarchy

```
SearchView
  │
  ├─ NeumorphicSearchBar
  │    │
  │    ├─ TextField (with @FocusState)
  │    │
  │    └─ SearchSuggestionsDropdown
  │         │
  │         └─ SearchSuggestionRow (x8)
  │              └─ Icon + Text + Context
  │
  ├─ FilterChips (x5)
  │
  ├─ SearchResultsView
  │    └─ SearchResultCard (forEach)
  │
  └─ EmptyStateView
       └─ DiscoverPeopleSection

SavedSearchesView
  │
  ├─ AlertBanner (if unread alerts)
  │
  ├─ SavedSearchCard (forEach)
  │    │
  │    ├─ Stats Row
  │    │
  │    └─ Actions Row
  │         ├─ Mute Button
  │         ├─ Check Now Button
  │         └─ Delete Button
  │
  └─ EmptyStateView

SearchAlertsView
  │
  └─ SearchAlertCard (forEach)
       └─ Mark as Read Button
```

---

## Key Design Patterns

### Singleton Services
```swift
class SavedSearchService: ObservableObject {
    static let shared = SavedSearchService()
    private init() {}
}
```

### Async/Await
```swift
func loadSavedSearches() async {
    do {
        let snapshot = try await db.collection("savedSearches")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        ...
    } catch {
        self.error = error.localizedDescription
    }
}
```

### Debouncing
```swift
searchTask?.cancel()
searchTask = Task {
    try? await Task.sleep(nanoseconds: 300_000_000)
    if !Task.isCancelled {
        await performSearch()
    }
}
```

### State Management
```swift
@StateObject private var service = Service.shared
@Published var items: [Item] = []
```

---

## Performance Optimizations

1. **Debouncing** - 300ms delay on typing
2. **Cancellation** - Cancel previous searches
3. **Indexing** - Firestore composite indexes
4. **Caching** - UserDefaults for recent searches
5. **Limiting** - Max 8 suggestions shown
6. **Lazy Loading** - LazyVStack for lists
7. **Prefixing** - Keyword prefixes for fast lookup
8. **Background** - BGTaskScheduler for checks

---

Built with ❤️ for production deployment 🚀
