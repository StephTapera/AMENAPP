//
//  SearchTestData.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  Test data and mock search service for testing search functionality
//

import Foundation
import SwiftUI
import Combine

// MARK: - Mock Search Service (For Testing)

@MainActor
class MockSearchService: ObservableObject {
    static let shared = MockSearchService()
    
    @Published var isSearching = false
    @Published var searchResults: [AppSearchResult] = []
    @Published var recentSearches: [String] = ["prayer", "bible study", "worship"]
    
    private init() {}
    
    // MARK: - Mock Search
    
    func search(query: String, filter: SearchViewTypes.SearchFilter = .all) async throws -> [AppSearchResult] {
        guard !query.isEmpty else { return [] }
        
        print("🔍 Mock searching for: '\(query)'")
        
        isSearching = true
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let allResults = MockSearchData.allResults
        let lowercaseQuery = query.lowercased()
        
        // Filter by type
        var filtered = allResults
        switch filter {
        case .people:
            filtered = filtered.filter { $0.type == .person }
        case .groups:
            filtered = filtered.filter { $0.type == .group }
        case .posts:
            filtered = filtered.filter { $0.type == .post }
        case .events:
            filtered = filtered.filter { $0.type == .event }
        case .all:
            break
        }
        
        // Filter by query
        let results = filtered.filter { result in
            result.title.lowercased().contains(lowercaseQuery) ||
            result.subtitle.lowercased().contains(lowercaseQuery) ||
            result.metadata.lowercased().contains(lowercaseQuery)
        }
        
        isSearching = false
        searchResults = results
        
        // Add to recent searches
        if !recentSearches.contains(query) {
            recentSearches.insert(query, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
        }
        
        print("✅ Found \(results.count) mock results")
        
        return results
    }
    
    func loadRecentSearches() {
        // Already loaded
    }
}

// MARK: - Mock Search Data

struct MockSearchData {
    
    // MARK: - People
    
    static let people: [AppSearchResult] = [
        AppSearchResult(
            firestoreId: "user1",
            title: "Sarah Johnson",
            subtitle: "@sarahjohnson",
            metadata: "245 followers • Youth pastor at City Church • Loves worship music and prayer",
            type: .person,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "user2",
            title: "David Martinez",
            subtitle: "@davidm",
            metadata: "892 followers • Bible study leader • Passionate about discipleship",
            type: .person,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "user3",
            title: "Emily Chen",
            subtitle: "@emilyc",
            metadata: "156 followers • Worship leader • Singer and songwriter",
            type: .person,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "user4",
            title: "Michael Brown",
            subtitle: "@mikebrown",
            metadata: "567 followers • Missionary in Kenya • Sharing the Gospel daily",
            type: .person,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "user5",
            title: "Rachel Kim",
            subtitle: "@rachelk",
            metadata: "324 followers • Prayer warrior • Leads women's Bible study",
            type: .person,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "user6",
            title: "Pastor James Wilson",
            subtitle: "@pastorjames",
            metadata: "1.2K followers • Senior Pastor • Teaching God's Word for 20 years",
            type: .person,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "user7",
            title: "Hannah Lee",
            subtitle: "@hannahlee",
            metadata: "198 followers • Young adults ministry • Coffee and Jesus enthusiast",
            type: .person,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "user8",
            title: "Daniel Garcia",
            subtitle: "@dang",
            metadata: "445 followers • Men's ministry leader • Iron sharpens iron",
            type: .person,
            isVerified: false
        ),
    ]
    
    // MARK: - Groups
    
    static let groups: [AppSearchResult] = [
        AppSearchResult(
            firestoreId: "group1",
            title: "Prayer Warriors",
            subtitle: "Daily prayer community",
            metadata: "234 members • Active 24/7 • Praying for the nation",
            type: .group,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "group2",
            title: "Bible Study Fellowship",
            subtitle: "Deep dive into Scripture",
            metadata: "567 members • Weekly studies • All denominations welcome",
            type: .group,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "group3",
            title: "Worship Together",
            subtitle: "Musicians and singers unite",
            metadata: "189 members • Share worship songs • Monthly jam sessions",
            type: .group,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "group4",
            title: "Young Adults Fellowship",
            subtitle: "Ages 18-30 community",
            metadata: "412 members • Game nights • Bible studies • Service projects",
            type: .group,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "group5",
            title: "Christian Singles",
            subtitle: "Faith-centered dating",
            metadata: "1.2K members • Events • Devotionals • Accountability",
            type: .group,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "group6",
            title: "Mission Minded",
            subtitle: "Global missions community",
            metadata: "298 members • Support missionaries • Prayer • Fundraising",
            type: .group,
            isVerified: false
        ),
    ]
    
    // MARK: - Posts
    
    static let posts: [AppSearchResult] = [
        AppSearchResult(
            firestoreId: "post1",
            title: "Answered Prayer Testimony!",
            subtitle: "Sarah Johnson",
            metadata: "God answered my prayer for healing! My grandmother is cancer-free! 🙏",
            type: .post,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "post2",
            title: "Psalm 23 - A Beautiful Reminder",
            subtitle: "David Martinez",
            metadata: "The Lord is my shepherd, I shall not want... Reflecting on God's provision",
            type: .post,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "post3",
            title: "New Worship Song Released!",
            subtitle: "Emily Chen",
            metadata: "Just released my new worship song 'Grace Abounds' - check it out! 🎵",
            type: .post,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "post4",
            title: "Bible Study Tonight!",
            subtitle: "Pastor James Wilson",
            metadata: "Join us at 7 PM for an amazing study on Romans 8. All are welcome!",
            type: .post,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "post5",
            title: "Prayer Request - Job Search",
            subtitle: "Hannah Lee",
            metadata: "Please pray as I search for a new job. Trusting God's timing and plan.",
            type: .post,
            isVerified: false
        ),
    ]
    
    // MARK: - Events
    
    static let events: [AppSearchResult] = [
        AppSearchResult(
            firestoreId: "event1",
            title: "Sunday Worship Night",
            subtitle: "City Church",
            metadata: "This Sunday at 6 PM • Worship, prayer, and fellowship • All welcome",
            type: .event,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "event2",
            title: "Men's Bible Study Breakfast",
            subtitle: "Daniel Garcia hosting",
            metadata: "Saturday 8 AM • Pancakes and Proverbs • RSVP required",
            type: .event,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "event3",
            title: "Youth Group Game Night",
            subtitle: "Sarah Johnson organizing",
            metadata: "Friday 7 PM • Games, snacks, devotional • Ages 13-18",
            type: .event,
            isVerified: false
        ),
        AppSearchResult(
            firestoreId: "event4",
            title: "Prayer Vigil for Healing",
            subtitle: "Prayer Warriors group",
            metadata: "All day Friday • Join anytime • Praying for the sick",
            type: .event,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "event5",
            title: "Worship Concert - Emily Chen",
            subtitle: "Grace Community Church",
            metadata: "Next Saturday 7 PM • Free admission • Bring friends!",
            type: .event,
            isVerified: true
        ),
        AppSearchResult(
            firestoreId: "event6",
            title: "Missions Conference 2026",
            subtitle: "Mission Minded group",
            metadata: "March 15-17 • Guest speakers • Workshops • Volunteer opportunities",
            type: .event,
            isVerified: true
        ),
    ]
    
    // MARK: - All Results Combined
    
    static let allResults: [AppSearchResult] = people + groups + posts + events
}

// MARK: - Wrapper to Test Search

struct TestSearchView: View {
    @StateObject private var mockService = MockSearchService.shared
    
    var body: some View {
        SearchViewWithMockData()
    }
}

struct SearchViewWithMockData: View {
    @State private var searchText = ""
    @State private var selectedFilter: SearchViewTypes.SearchFilter = .all
    @State private var searchResults: [AppSearchResult] = []
    @State private var isSearching = false
    
    // AI Features
    @State private var showAISuggestions = false
    @State private var showBiblicalCard = false
    @State private var showFilterBanner = false
    
    let mockService = MockSearchService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search people, groups, posts...", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()
                
                // Filter chips
                if !searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SearchViewTypes.SearchFilter.allCases, id: \.self) { filter in
                                SoftSearchFilterChip(
                                    filter: filter,
                                    isSelected: selectedFilter == filter,
                                    action: {
                                        selectedFilter = filter
                                        performSearch()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Results
                ScrollView {
                    VStack(spacing: 16) {
                        if searchText.isEmpty {
                            emptyState
                        } else if isSearching {
                            ProgressView("Searching...")
                                .padding()
                        } else {
                            // AI Components
                            if showFilterBanner {
                                SmartFilterBanner(
                                    suggestion: FilterSuggestion(
                                        filters: ["groups", "events"],
                                        explanation: "Based on your search, try filtering by Groups and Events"
                                    ),
                                    onApplyFilters: { _ in }
                                )
                            }
                            
                            if showBiblicalCard {
                                BiblicalSearchCard(result: SampleData.davidResult)
                            }
                            
                            if showAISuggestions {
                                AISearchSuggestionsPanel(
                                    query: searchText,
                                    suggestions: SampleData.getSuggestions(for: searchText),
                                    relatedTopics: SampleData.getRelatedTopics(for: searchText),
                                    onSuggestionTap: { suggestion in
                                        searchText = suggestion
                                    }
                                )
                            }
                            
                            // Results
                            if searchResults.isEmpty {
                                noResults
                            } else {
                                resultsList
                            }
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Search")
            .onChange(of: searchText) { _, newValue in
                if !newValue.isEmpty {
                    performSearch()
                    updateAIComponents()
                } else {
                    searchResults = []
                    showAISuggestions = false
                    showBiblicalCard = false
                    showFilterBanner = false
                }
            }
        }
    }
    
    var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.purple.gradient)
            
            Text("Start Searching")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Text("Find people, groups, posts, and events")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Try searching for:")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                
                ForEach(["prayer", "bible study", "worship", "Sarah"], id: \.self) { term in
                    Button {
                        searchText = term
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text(term)
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .padding()
    }
    
    var noResults: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No results found")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("Try a different search term")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    var resultsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchResults) { result in
                SearchResultRow(result: result)
            }
        }
        .padding(.horizontal)
    }
    
    func performSearch() {
        Task {
            isSearching = true
            searchResults = try await mockService.search(query: searchText, filter: selectedFilter)
            isSearching = false
        }
    }
    
    func updateAIComponents() {
        let query = searchText.lowercased()
        showAISuggestions = !query.isEmpty
        showBiblicalCard = query.contains("david") || query.contains("paul") || query.contains("jerusalem")
        showFilterBanner = query.contains("prayer") || query.contains("worship")
    }
}

struct SearchResultRow: View {
    let result: AppSearchResult
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.type.icon)
                .font(.system(size: 24))
                .foregroundStyle(result.type.color)
                .frame(width: 40, height: 40)
                .background(result.type.color.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(result.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    if result.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                }
                
                Text(result.subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Text(result.metadata)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#Preview {
    SearchViewWithMockData()
}
