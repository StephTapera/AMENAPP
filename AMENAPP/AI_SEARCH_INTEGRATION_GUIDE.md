# AI-Powered Search Integration Guide

## 🎯 What You Get

Your search now has **4 powerful AI features**:

1. **Smart Suggestions** - AI understands your query and suggests better searches
2. **Biblical Context** - Search for people/places and get rich biblical information
3. **Smart Filters** - AI recommends which filters to use
4. **Related Topics** - Discover connections you didn't think of

---

## 🚀 How to Integrate

### Step 1: Restart Genkit Server

In Terminal where your server is running:
```bash
Ctrl + C
npm run dev
```

### Step 2: Add AI State to SearchView

Update your `SearchView` (in SearchViewComponents.swift around line 960):

```swift
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var searchText = ""
    @State private var selectedFilter: SearchViewTypes.SearchFilter = .all
    @State private var selectedSort: SearchViewTypes.SortOption = .relevance
    @State private var showSortOptions = false
    @FocusState private var isSearchFieldFocused: Bool
    
    // Existing results
    @State private var searchResults: [AppSearchResult] = []
    
    // NEW: AI-powered search state
    @State private var aiSuggestions: SearchSuggestions?
    @State private var biblicalResult: BiblicalSearchResult?
    @State private var filterSuggestion: FilterSuggestion?
    @State private var isLoadingAI = false
    private let genkitService = BereanGenkitService.shared
    
    // ... rest of your view
}
```

### Step 3: Add AI Search Function

Add this method to your `SearchView`:

```swift
private func performAISearch() {
    guard searchText.count >= 3 else { return }
    
    isLoadingAI = true
    
    Task {
        do {
            // Get smart suggestions
            let suggestions = try await genkitService.generateSearchSuggestions(
                query: searchText,
                context: selectedFilter.rawValue.lowercased()
            )
            
            // Get smart filter suggestions
            let filters = try await genkitService.suggestSearchFilters(query: searchText)
            
            // If query looks biblical, get enhanced context
            var biblical: BiblicalSearchResult?
            if searchText.contains(["david", "paul", "peter", "jesus", "jerusalem", "bethlehem"]) {
                biblical = try await genkitService.enhanceBiblicalSearch(
                    query: searchText,
                    type: .person // or .place, .event based on detection
                )
            }
            
            await MainActor.run {
                aiSuggestions = suggestions
                filterSuggestion = filters
                biblicalResult = biblical
                isLoadingAI = false
            }
            
        } catch {
            print("AI search error: \(error)")
            await MainActor.run {
                isLoadingAI = false
            }
        }
    }
}
```

### Step 4: Trigger AI Search

Update your search field's `onChange`:

```swift
TextField("Search people, groups, events...", text: $searchText)
    .onChange(of: searchText) { oldValue, newValue in
        // Existing search logic
        performSearch()
        
        // NEW: AI-powered suggestions
        if newValue.count >= 3 {
            // Debounce AI calls
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                if searchText == newValue { // Still the same query
                    performAISearch()
                }
            }
        }
    }
```

### Step 5: Display AI Results

Add these to your search results view (after your existing results):

```swift
// In your ScrollView content:
VStack(spacing: 16) {
    // Show smart filter banner
    if let filterSuggestion = filterSuggestion {
        SmartFilterBanner(
            suggestion: filterSuggestion,
            onApplyFilters: { filters in
                // Apply suggested filters
                if let firstFilter = filters.first,
                   let filter = SearchViewTypes.SearchFilter.allCases.first(where: { $0.rawValue.lowercased() == firstFilter }) {
                    withAnimation {
                        selectedFilter = filter
                    }
                }
            }
        )
    }
    
    // Show biblical context
    if let biblical = biblicalResult {
        BiblicalSearchCard(result: biblical)
    }
    
    // Show AI suggestions
    if let suggestions = aiSuggestions {
        AISearchSuggestionsPanel(
            query: searchText,
            suggestions: suggestions.suggestions,
            relatedTopics: suggestions.relatedTopics,
            onSuggestionTap: { suggestion in
                searchText = suggestion
                performSearch()
                performAISearch()
            }
        )
    }
    
    // Your existing search results below
    SearchResultsView(
        query: searchText,
        filter: selectedFilter,
        results: filteredResults,
        sortOption: selectedSort
    )
}
```

---

## 🎨 Example Use Cases

### Example 1: Searching for "David"

**User types:** `david`

**AI Response:**
```
┌─────────────────────────────────────────┐
│ 🪄 Smart Filters                        │
│                                         │
│ This query appears to be about a       │
│ biblical person. Try: People, Bible    │
│                                         │
│ [People] [Bible]        [Apply Filters]│
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 📖 Biblical Context                     │
│                                         │
│ David was the second king of Israel,   │
│ known as "a man after God's own heart."│
│                                         │
│ Key Verses:                             │
│ [1 Samuel 16:7] [Psalm 23:1]          │
│                                         │
│ Related People:                         │
│ [Saul] [Jonathan] [Solomon]           │
│                                         │
│ 💡 Did You Know?                       │
│ • David wrote 73 of the 150 Psalms    │
│ • He defeated Goliath as a teenager   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ ✨ AI Suggestions                       │
│                                         │
│ Try searching for:                      │
│ 🔍 King David of Israel                │
│ 🔍 David and Goliath story             │
│ 🔍 Psalms written by David             │
│ 🔍 David's family tree                 │
│                                         │
│ Related topics:                         │
│ [Israel Kings] [Psalms] [Warriors]    │
└─────────────────────────────────────────┘
```

### Example 2: Searching for "prayer group"

**User types:** `prayer group`

**AI Response:**
```
┌─────────────────────────────────────────┐
│ 🪄 Smart Filters                        │
│                                         │
│ Looking for prayer communities?         │
│ Try: Groups, Events                    │
│                                         │
│ [Groups] [Events]       [Apply Filters]│
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ ✨ AI Suggestions                       │
│                                         │
│ Try searching for:                      │
│ 🔍 Local prayer groups near me         │
│ 🔍 Weekly prayer meetings              │
│ 🔍 Intercession prayer teams           │
│ 🔍 Youth prayer groups                 │
│                                         │
│ Related topics:                         │
│ [Prayer Partners] [Bible Study]       │
│ [Fellowship] [Intercessory Prayer]    │
└─────────────────────────────────────────┘
```

### Example 3: Searching for "Jerusalem"

**User types:** `jerusalem`

**AI Response:**
```
┌─────────────────────────────────────────┐
│ 📖 Biblical Context                     │
│                                         │
│ Jerusalem, the "City of David," is     │
│ considered holy in Judaism,             │
│ Christianity, and Islam. It was        │
│ Israel's capital and site of Solomon's│
│ Temple.                                 │
│                                         │
│ Key Verses:                             │
│ [Psalm 122:6] [Isaiah 62:1]          │
│ [Matthew 23:37]                        │
│                                         │
│ Related People:                         │
│ [David] [Solomon] [Jesus]             │
│                                         │
│ 💡 Did You Know?                       │
│ • Jerusalem is mentioned 800+ times    │
│ • It has been destroyed twice         │
│ • Built on 7 hills like Rome          │
└─────────────────────────────────────────┘
```

---

## 🎯 Features You Get

### 1. Smart Suggestions ✨
- AI rewrites queries for better results
- Suggests related searches
- Learns from context (people vs. events vs. bible)

### 2. Biblical Intelligence 📖
- Detects biblical names and places
- Provides instant context
- Lists related verses and people
- Includes fun facts

### 3. Smart Filters 🎯
- AI analyzes your query
- Recommends best filters
- Explains why
- One-tap to apply

### 4. Related Topics 🔗
- Discovers connections
- Helps exploration
- Expands search scope

---

## 🚀 Quick Integration Steps

### Minimal Integration (5 minutes)

Just add AI suggestions panel:

```swift
// After your search field
if let suggestions = aiSuggestions, searchText.count >= 3 {
    AISearchSuggestionsPanel(
        query: searchText,
        suggestions: suggestions.suggestions,
        relatedTopics: suggestions.relatedTopics,
        onSuggestionTap: { suggestion in
            searchText = suggestion
        }
    )
}
```

### Full Integration (15 minutes)

Follow all steps above for complete AI-powered search.

---

## 🎨 Customization

### Adjust AI Trigger Length

```swift
// Trigger AI after 2 characters instead of 3
if newValue.count >= 2 {
    performAISearch()
}
```

### Change Debounce Delay

```swift
// Wait 1 second instead of 0.5
try? await Task.sleep(nanoseconds: 1_000_000_000)
```

### Disable Specific Features

```swift
// Only show suggestions, no biblical context
let suggestions = try await genkitService.generateSearchSuggestions(...)
// Don't call enhanceBiblicalSearch
```

---

## 📊 Performance Tips

### 1. Debouncing (Already Implemented)
- Waits 0.5s after typing stops
- Prevents too many AI calls
- Saves API costs

### 2. Caching
Add simple caching:

```swift
@State private var suggestionCache: [String: SearchSuggestions] = [:]

private func performAISearch() {
    // Check cache first
    if let cached = suggestionCache[searchText] {
        aiSuggestions = cached
        return
    }
    
    // ... make AI call
    
    // Cache result
    suggestionCache[searchText] = suggestions
}
```

### 3. Loading States

Show skeleton while AI loads:

```swift
if isLoadingAI {
    LoadingSkeletonPanel()
} else if let suggestions = aiSuggestions {
    AISearchSuggestionsPanel(...)
}
```

---

## ✅ Testing

### Test 1: Biblical Search
Search for: "Moses", "Paul", "Jerusalem", "Bethlehem"

Expected: Biblical context card appears

### Test 2: Regular Search
Search for: "prayer group", "bible study", "worship"

Expected: Smart suggestions appear

### Test 3: Filter Suggestions
Search for any query

Expected: Smart filter banner appears

---

## 🎉 You're Done!

Your search is now powered by AI! Users will love:
- ✅ Smarter search suggestions
- ✅ Biblical context for names/places
- ✅ Intelligent filter recommendations
- ✅ Discovery of related topics

**Restart your Genkit server and test it out!** 🚀
