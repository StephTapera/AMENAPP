//
//  EnhancedSearchService.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/24/26.
//
//  Production-ready AI-enhanced search with Genkit integration
//

import Foundation
import FirebaseFirestore
import Combine
import SwiftUI

// MARK: - AI Search Models

struct AISearchSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let type: SuggestionType
    let icon: String
    
    enum SuggestionType {
        case query
        case topic
        case biblical
        case filter
    }
}

struct SearchFilterRecommendation: Identifiable {
    let id = UUID()
    let filter: String
    let reason: String
    let icon: String
    let color: Color
}

// MARK: - Enhanced Search Service with AI

@MainActor
class EnhancedSearchService: ObservableObject {
    static let shared = EnhancedSearchService()
    
    private let db = Firestore.firestore()
    private let genkitService = BereanGenkitService.shared
    private let userSearchService = UserSearchService.shared
    
    @Published var isSearching = false
    @Published var searchResults: [AppSearchResult] = []
    @Published var aiSuggestions: [AISearchSuggestion] = []
    @Published var filterRecommendations: [SearchFilterRecommendation] = []
    @Published var recentSearches: [String] = []
    @Published var error: String?
    
    private var suggestionTask: Task<Void, Never>?
    private let maxRecentSearches = 10
    
    private init() {
        loadRecentSearches()
    }
    
    // MARK: - AI-Enhanced Search
    
    /// Search with AI suggestions and smart filtering
    func searchWithAI(
        query: String,
        filter: SearchViewTypes.SearchFilter = .all,
        context: String? = nil
    ) async throws -> [AppSearchResult] {
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        
        print("🤖 AI-Enhanced Search: '\(query)' with filter: \(filter.rawValue)")
        
        isSearching = true
        defer { isSearching = false }
        
        // 1. Get AI suggestions in parallel with search
        Task {
            await generateAISuggestions(for: query, context: contextString(from: filter))
            await generateFilterRecommendations(for: query)
        }
        
        // 2. Perform search based on filter
        var results: [AppSearchResult] = []
        
        switch filter {
        case .all:
            results = try await searchAll(query: query)
            
        case .people:
            results = try await searchPeopleEnhanced(query: query)
            
        case .groups:
            results = try await searchGroups(query: query)
            
        case .posts:
            results = try await searchPosts(query: query)
            
        case .events:
            results = try await searchEvents(query: query)
        }
        
        // 3. Sort by relevance
        results = sortByRelevance(results, query: query)
        
        // 4. Save to recent searches
        saveRecentSearch(query)
        
        await MainActor.run {
            self.searchResults = results
        }
        
        return results
    }
    
    // MARK: - AI Suggestions Generation
    
    /// Generate AI-powered search suggestions
    private func generateAISuggestions(for query: String, context: String) async {
        // Cancel any ongoing suggestion task
        suggestionTask?.cancel()
        
        suggestionTask = Task {
            do {
                // Check if task was cancelled
                try Task.checkCancellation()
                
                // Call Genkit AI for suggestions
                let result = try await genkitService.generateSearchSuggestions(
                    query: query,
                    context: context
                )
                
                // Check again after async work
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.aiSuggestions = result.suggestions.map { text in
                        AISearchSuggestion(
                            text: text,
                            type: .query,
                            icon: "magnifyingglass"
                        )
                    } + result.relatedTopics.map { topic in
                        AISearchSuggestion(
                            text: topic,
                            type: .topic,
                            icon: "lightbulb.fill"
                        )
                    }
                }
                
                print("✅ Generated \(result.suggestions.count) AI suggestions")
                
            } catch is CancellationError {
                print("⏸️ Suggestion generation cancelled")
            } catch {
                print("⚠️ Error generating suggestions: \(error.localizedDescription)")
                // Fail silently - don't disrupt search
            }
        }
    }
    
    /// Generate smart filter recommendations
    private func generateFilterRecommendations(for query: String) async {
        do {
            let result = try await genkitService.suggestSearchFilters(query: query)
            
            await MainActor.run {
                self.filterRecommendations = result.filters.map { filter in
                    SearchFilterRecommendation(
                        filter: filter,
                        reason: result.explanation,
                        icon: iconForFilter(filter),
                        color: colorForFilter(filter)
                    )
                }
            }
            
            print("✅ Generated \(result.filters.count) filter recommendations")
            
        } catch {
            print("⚠️ Error generating filter recommendations: \(error.localizedDescription)")
            // Fail silently
        }
    }
    
    // MARK: - Enhanced People Search
    
    /// Search people with AI enhancement
    private func searchPeopleEnhanced(query: String) async throws -> [AppSearchResult] {
        // Use UserSearchService for people
        let users = try await userSearchService.searchUsers(query: query, searchType: SearchType.both)
        
        return users.map { user in
            AppSearchResult(
                firestoreId: user.id,
                title: user.displayName,
                subtitle: "@\(user.username)",
                metadata: user.bio ?? "",
                type: .person,
                isVerified: user.isVerified
            )
        }
    }
    
    // MARK: - Search All Categories
    
    private func searchAll(query: String) async throws -> [AppSearchResult] {
        // Search all categories in parallel
        async let people = searchPeopleEnhanced(query: query)
        async let groups = searchGroups(query: query)
        async let posts = searchPosts(query: query)
        async let events = searchEvents(query: query)
        
        let (peopleResults, groupResults, postResults, eventResults) = try await (people, groups, posts, events)
        
        return peopleResults + groupResults + postResults + eventResults
    }
    
    // MARK: - Category-Specific Search
    
    private func searchGroups(query: String) async throws -> [AppSearchResult] {
        // Mock implementation - replace with real Firestore query
        return []
    }
    
    private func searchPosts(query: String) async throws -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        let snapshot = try await db.collection("posts")
            .whereField("contentLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("contentLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            
            guard let content = data["content"] as? String,
                  let authorName = data["authorName"] as? String else {
                return nil
            }
            
            return AppSearchResult(
                firestoreId: doc.documentID,
                title: authorName,
                subtitle: content.prefix(100).description,
                metadata: data["timestamp"] as? String ?? "",
                type: .post,
                isVerified: false
            )
        }
    }
    
    private func searchEvents(query: String) async throws -> [AppSearchResult] {
        // Mock implementation - replace with real Firestore query
        return []
    }
    
    // MARK: - Relevance Sorting
    
    private func sortByRelevance(_ results: [AppSearchResult], query: String) -> [AppSearchResult] {
        let lowercaseQuery = query.lowercased()
        
        return results.sorted { a, b in
            let aScore = relevanceScore(for: a, query: lowercaseQuery)
            let bScore = relevanceScore(for: b, query: lowercaseQuery)
            return aScore > bScore
        }
    }
    
    private func relevanceScore(for result: AppSearchResult, query: String) -> Int {
        var score = 0
        
        let title = result.title.lowercased()
        let subtitle = result.subtitle.lowercased()
        
        // Exact match
        if title == query { score += 100 }
        if subtitle == query { score += 50 }
        
        // Starts with
        if title.hasPrefix(query) { score += 50 }
        if subtitle.hasPrefix(query) { score += 25 }
        
        // Contains
        if title.contains(query) { score += 25 }
        if subtitle.contains(query) { score += 10 }
        
        // Verified bonus
        if result.isVerified { score += 10 }
        
        return score
    }
    
    // MARK: - Recent Searches
    
    private func loadRecentSearches() {
        if let data = UserDefaults.standard.array(forKey: "recentSearches") as? [String] {
            recentSearches = data
        }
    }
    
    private func saveRecentSearch(_ query: String) {
        // Remove if already exists
        recentSearches.removeAll { $0 == query }
        
        // Add to front
        recentSearches.insert(query, at: 0)
        
        // Limit size
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        // Save
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }
    
    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentSearches")
    }
    
    // MARK: - Helper Functions
    
    private func contextString(from filter: SearchViewTypes.SearchFilter) -> String {
        switch filter {
        case .all: return "all"
        case .people: return "people"
        case .groups: return "groups"
        case .posts: return "posts"
        case .events: return "events"
        }
    }
    
    private func iconForFilter(_ filter: String) -> String {
        if filter.contains("people") { return "person.2" }
        if filter.contains("location") { return "location.fill" }
        if filter.contains("interest") { return "heart.fill" }
        if filter.contains("group") { return "person.3" }
        if filter.contains("event") { return "calendar" }
        return "line.3.horizontal.decrease.circle"
    }
    
    private func colorForFilter(_ filter: String) -> Color {
        if filter.contains("people") { return .blue }
        if filter.contains("location") { return .green }
        if filter.contains("interest") { return .pink }
        if filter.contains("group") { return .purple }
        if filter.contains("event") { return .orange }
        return .gray
    }
    
    // MARK: - Clear State
    
    func clearSearch() {
        suggestionTask?.cancel()
        searchResults = []
        aiSuggestions = []
        filterRecommendations = []
        error = nil
        isSearching = false
    }
}
