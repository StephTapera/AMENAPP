# AI Search Testing Guide

## 🎯 Quick Start

I've created a **complete testing interface** for your AI Search features! Here's how to use it:

### 1. Open the Test View

Add this to your app to test the search components:

```swift
// In your ContentView or wherever you want to test
NavigationLink("Test AI Search") {
    AISearchExamplesView()
}
```

Or just show it directly:
```swift
AISearchExamplesView()
```

### 2. Try These Example Searches

The test view includes pre-configured examples that demonstrate all your AI search features:

#### 📖 **Biblical Person Search** - Type "David" or "Paul"
- Shows the `BiblicalSearchCard` with:
  - Summary of the person
  - Key Bible verses
  - Related people
  - Fun facts

#### 📍 **Biblical Place Search** - Type "Jerusalem"
- Shows place-specific information
- Historical context
- Related people and events

#### 🙏 **Smart Filter Suggestions** - Type "Prayer groups" or "Worship events"
- Shows the `SmartFilterBanner`
- Suggests relevant filters
- One-click filter application

#### ✨ **AI Suggestions** - Type any search query
- Shows the `AISearchSuggestionsPanel`
- Related search suggestions
- Topic tags

## 📁 Files Created

### ✅ AISearchExamples.swift
**Complete testing interface with:**
- Interactive search bar
- Sample data for all components
- Example queries you can click
- All three AI search components working together

**Example searches included:**
1. **David** - Biblical person with Psalms, Goliath story
2. **Paul** - Apostle with missionary journeys
3. **Jerusalem** - Holy city with historical context
4. **Prayer groups** - Smart filter suggestions
5. **Worship events** - Event filtering
6. **Bible study** - General suggestions

### ✅ AISearchEnhancements.swift (Updated)
Added data models at the top so components work standalone.

## 🎨 Components Available

### 1. BiblicalSearchCard
```swift
BiblicalSearchCard(result: biblicalResult)
```
Shows rich biblical context with verses, people, and facts.

### 2. AISearchSuggestionsPanel
```swift
AISearchSuggestionsPanel(
    query: "your query",
    suggestions: ["suggestion 1", "suggestion 2"],
    relatedTopics: ["topic1", "topic2"],
    onSuggestionTap: { suggestion in
        // Handle tap
    }
)
```
Shows AI-powered search suggestions and related topics.

### 3. SmartFilterBanner
```swift
SmartFilterBanner(
    suggestion: FilterSuggestion(
        filters: ["groups", "events"],
        explanation: "Why these filters make sense"
    ),
    onApplyFilters: { filters in
        // Apply filters
    }
)
```
Suggests and applies smart filters based on search context.

## 🔌 Integration with Real Search

To integrate into your actual SearchView:

```swift
// In SearchViewComponents.swift or your search view

// Add states for AI components
@State private var aiSuggestions: [String] = []
@State private var relatedTopics: [String] = []
@State private var biblicalResult: BiblicalSearchResult?
@State private var filterSuggestion: FilterSuggestion?

// In your search onChange handler:
.onChange(of: searchText) { oldValue, newValue in
    guard !newValue.isEmpty else { return }
    
    Task {
        // Call your backend or use sample data
        aiSuggestions = SampleData.getSuggestions(for: newValue)
        relatedTopics = SampleData.getRelatedTopics(for: newValue)
        
        // Check if biblical search
        if newValue.lowercased().contains("david") {
            biblicalResult = SampleData.davidResult
        }
        
        // Check if needs filter suggestion
        if newValue.lowercased().contains("prayer") {
            filterSuggestion = SampleData.filterSuggestion
        }
    }
}

// In your search results view:
ScrollView {
    VStack(spacing: 16) {
        // Smart Filter Banner
        if let suggestion = filterSuggestion {
            SmartFilterBanner(
                suggestion: suggestion,
                onApplyFilters: { filters in
                    // Apply to your search filters
                }
            )
        }
        
        // Biblical Card
        if let biblical = biblicalResult {
            BiblicalSearchCard(result: biblical)
        }
        
        // AI Suggestions
        if !aiSuggestions.isEmpty {
            AISearchSuggestionsPanel(
                query: searchText,
                suggestions: aiSuggestions,
                relatedTopics: relatedTopics,
                onSuggestionTap: { suggestion in
                    searchText = suggestion
                }
            )
        }
        
        // Your existing search results...
    }
}
```

## 🎭 Sample Data Provided

The `SampleData` struct includes:

### Biblical Figures
- **David**: King, Psalms author, Goliath slayer
- **Paul**: Apostle, missionary, letter writer
- **Jerusalem**: Holy city, Temple location

### Search Suggestions
Dynamic suggestions based on keywords:
- Biblical names → Bible stories and context
- Prayer/Worship → Groups and events
- Bible study → Study groups and resources

### Filter Suggestions
Smart filters that make sense for:
- Prayer searches → Groups + Events
- Worship searches → Events + People
- Study searches → Groups + Posts

## 🚀 Next Steps

1. **Test the UI**: Run `AISearchExamplesView()` in your app
2. **Try different searches**: Use the example buttons or type your own
3. **Customize the data**: Modify `SampleData` to match your app's content
4. **Connect to backend**: Replace sample data with real API calls
5. **Add more examples**: Extend `SampleData` with more biblical figures, places, events

## 💡 Tips

- All components use your custom OpenSans fonts
- Animations are smooth with spring physics
- FlowLayout automatically wraps chips/tags
- Colors match your app's purple theme
- All components are reusable and composable

## 🐛 Debugging

If something doesn't show:
1. Check the search query matches the conditions in `SampleData`
2. Ensure state variables are updating
3. Verify animations aren't hiding content
4. Check console for any errors

Enjoy testing your AI-powered search! 🎉
