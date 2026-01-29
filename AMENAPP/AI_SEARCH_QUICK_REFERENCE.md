# 🔍 AI-Powered Search - Quick Reference

## ✅ What's Been Added

### Backend (Genkit Flows)
1. ✅ **generateSearchSuggestions** - Smart query improvements
2. ✅ **enhanceBiblicalSearch** - Biblical people/places context
3. ✅ **suggestSearchFilters** - Intelligent filter recommendations

### iOS (Swift)
1. ✅ **BereanGenkitService** - 3 new search methods
2. ✅ **AISearchEnhancements.swift** - Ready-to-use UI components
3. ✅ **Search support types** - Models for AI results

---

## 🎯 AI Search Capabilities

| Feature | What It Does | Example |
|---------|--------------|---------|
| **Smart Suggestions** | Rewrites & improves queries | "david" → "King David of Israel" |
| **Biblical Context** | Provides verses, facts, related people | Search "Moses" → Life summary + verses |
| **Smart Filters** | Recommends best filters | "prayer group" → Groups, Events |
| **Related Topics** | Discovers connections | "faith" → Hope, Trust, Belief |

---

## 🚀 Quick Start

### Step 1: Restart Server
```bash
cd genkit
Ctrl + C  (if running)
npm run dev
```

### Step 2: Add to SearchView

```swift
// Add state
@State private var aiSuggestions: SearchSuggestions?
@State private var biblicalResult: BiblicalSearchResult?
private let genkitService = BereanGenkitService.shared

// Add function
private func performAISearch() {
    Task {
        let suggestions = try await genkitService.generateSearchSuggestions(
            query: searchText,
            context: "general"
        )
        aiSuggestions = suggestions
    }
}

// Trigger on search
.onChange(of: searchText) { old, new in
    if new.count >= 3 {
        performAISearch()
    }
}

// Display results
if let suggestions = aiSuggestions {
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

### Step 3: Build & Test
```bash
Cmd + R in Xcode
Navigate to Search
Type "david" or "prayer"
Watch AI magic! ✨
```

---

## 📱 UI Components Available

### 1. AISearchSuggestionsPanel
Shows smart suggestions and related topics

```swift
AISearchSuggestionsPanel(
    query: searchText,
    suggestions: ["suggestion 1", "suggestion 2"],
    relatedTopics: ["topic 1", "topic 2"],
    onSuggestionTap: { suggestion in
        // Handle tap
    }
)
```

### 2. BiblicalSearchCard
Displays rich biblical context

```swift
BiblicalSearchCard(result: biblicalResult)
```

### 3. SmartFilterBanner
Recommends filters to apply

```swift
SmartFilterBanner(
    suggestion: filterSuggestion,
    onApplyFilters: { filters in
        // Apply filters
    }
)
```

---

## 🎨 Example Searches to Test

### Biblical Names
- "david" → King context + verses + related people
- "paul" → Apostle context + missionary journeys
- "moses" → Exodus leader + ten commandments

### Places
- "jerusalem" → Holy city + historical context
- "bethlehem" → Birth of Jesus + biblical significance

### Regular Searches
- "prayer group" → Suggests: groups, events filters
- "bible study" → Related: fellowship, discipleship
- "worship" → Suggests: music, praise topics

---

## 💡 Pro Tips

### 1. Debounce AI Calls
```swift
Task {
    try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
    if searchText == newValue {
        performAISearch() // Still same query
    }
}
```

### 2. Cache Results
```swift
@State private var cache: [String: SearchSuggestions] = [:]

if let cached = cache[searchText] {
    return cached // Use cache
}
```

### 3. Loading States
```swift
if isLoadingAI {
    ProgressView()
} else if let suggestions = aiSuggestions {
    AISearchSuggestionsPanel(...)
}
```

---

## 🔧 Customization

### Change AI Trigger
```swift
if newValue.count >= 2 { // Trigger after 2 chars
    performAISearch()
}
```

### Only Show for Specific Filters
```swift
if selectedFilter == .people || selectedFilter == .bible {
    performAISearch()
}
```

### Add Biblical Detection
```swift
let biblicalKeywords = ["david", "paul", "moses", "jesus", "jerusalem"]
if biblicalKeywords.contains(where: { searchText.lowercased().contains($0) }) {
    // Call enhanceBiblicalSearch
}
```

---

## 📊 What Users Will See

### Before (Regular Search)
```
Search: "david"

Results:
• Dave Johnson (User)
• David Lee (User)
• David's Prayer Group
```

### After (AI-Powered)
```
Search: "david"

┌─────────────────────────────────┐
│ ✨ AI Suggestions               │
│                                 │
│ • King David of Israel          │
│ • David and Goliath            │
│ • Psalms of David              │
│                                 │
│ Related: [Psalms] [Israel]     │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ 📖 Biblical Context             │
│                                 │
│ David was the second king...   │
│                                 │
│ Verses: [1 Sam 16:7] [Ps 23:1]│
│                                 │
│ 💡 Wrote 73 Psalms             │
└─────────────────────────────────┘

Regular Results:
• Dave Johnson (User)
• David Lee (User)
• David's Prayer Group
```

**Users get both AI context AND regular results!**

---

## ✅ Files Created

1. ✅ **genkitberean-flows.ts** - 3 new AI flows
2. ✅ **BereanGenkitService.swift** - 3 new methods + support types
3. ✅ **AISearchEnhancements.swift** - UI components
4. ✅ **AI_SEARCH_INTEGRATION_GUIDE.md** - Full integration guide
5. ✅ **AI_SEARCH_QUICK_REFERENCE.md** - This file

---

## 🎯 Integration Checklist

- [ ] Restart Genkit server (`npm run dev`)
- [ ] Add `@State` variables to SearchView
- [ ] Add `performAISearch()` function
- [ ] Trigger on `.onChange(of: searchText)`
- [ ] Display `AISearchSuggestionsPanel`
- [ ] (Optional) Add `BiblicalSearchCard`
- [ ] (Optional) Add `SmartFilterBanner`
- [ ] Build and test! (`Cmd + R`)

---

## 🐛 Troubleshooting

### No AI suggestions appearing
1. Check server is running (`http://localhost:3400`)
2. Check console for errors
3. Verify search text is >= 3 characters
4. Check debounce delay hasn't prevented call

### Biblical context not showing
1. Make sure query contains biblical keywords
2. Check `enhanceBiblicalSearch` is being called
3. Verify the type (person/place/event) is correct

### Slow responses
1. AI calls take 1-3 seconds (normal)
2. Use loading states to show progress
3. Consider increasing debounce delay
4. Cache frequently searched terms

---

## 📚 Full Documentation

See **AI_SEARCH_INTEGRATION_GUIDE.md** for:
- Complete step-by-step integration
- Detailed examples
- Performance optimization
- Advanced customization

---

## 🎉 Summary

You now have **3 powerful AI search features**:

1. ✅ **Smart Suggestions** - Better queries & related topics
2. ✅ **Biblical Intelligence** - Rich context for Bible searches
3. ✅ **Smart Filters** - AI recommends filters

**Just restart your server and add the UI components!** 🚀

Need help? Check the full integration guide or the code comments in `AISearchEnhancements.swift`.
