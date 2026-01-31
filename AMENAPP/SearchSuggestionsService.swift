//
//  SearchSuggestionsService.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct SearchSuggestion: Identifiable, Codable {
    let id: String
    let text: String
    let category: SuggestionCategory
    let icon: String
    let color: String
    let context: String?
    let popularity: Int
    
    enum SuggestionCategory: String, Codable {
        case person = "person"
        case group = "group"
        case post = "post"
        case event = "event"
        case topic = "topic"
        case bible = "bible"
        case prayer = "prayer"
        case recent = "recent"
    }
}

// MARK: - Search Suggestions Service

@Observable
@MainActor
class SearchSuggestionsService {
    static let shared = SearchSuggestionsService()
    
    var suggestions: [SearchSuggestion] = []
    var isLoading = false
    
    private let db = Firestore.firestore()
    private var searchTask: Task<Void, Never>?
    
    // Local cache for fast suggestions
    private var trendingSearches: [String] = []
    private var recentSearches: [String] = []
    
    private init() {}
    
    // MARK: - Get Suggestions
    
    func getSuggestions(for query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        
        searchTask = Task {
            isLoading = true
            
            var allSuggestions: [SearchSuggestion] = []
            
            // 1. Check for @ symbol (user search)
            if query.hasPrefix("@") {
                allSuggestions.append(contentsOf: await getUserSuggestions(query: query))
            }
            // 2. Check for # symbol (hashtag/topic)
            else if query.hasPrefix("#") {
                allSuggestions.append(contentsOf: await getTopicSuggestions(query: query))
            }
            // 3. General search
            else {
                // Get all types of suggestions
                async let people = getPeopleSuggestions(query: query)
                async let groups = getGroupSuggestions(query: query)
                async let topics = getTopicSuggestions(query: query)
                async let biblical = getBiblicalSuggestions(query: query)
                
                let (peopleResults, groupResults, topicResults, biblicalResults) = await (people, groups, topics, biblical)
                
                allSuggestions.append(contentsOf: biblicalResults)
                allSuggestions.append(contentsOf: peopleResults)
                allSuggestions.append(contentsOf: groupResults)
                allSuggestions.append(contentsOf: topicResults)
            }
            
            // Add recent searches that match
            allSuggestions.append(contentsOf: getRecentSearchSuggestions(query: query))
            
            // Sort by relevance and limit
            allSuggestions.sort { $0.popularity > $1.popularity }
            
            if !Task.isCancelled {
                suggestions = Array(allSuggestions.prefix(8))
                isLoading = false
            }
        }
    }
    
    // MARK: - Get People Suggestions
    
    private func getPeopleSuggestions(query: String) async -> [SearchSuggestion] {
        do {
            let snapshot = try await db.collection("users")
                .whereField("searchKeywords", arrayContains: query.lowercased())
                .limit(to: 3)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                guard let displayName = doc.data()["displayName"] as? String,
                      let username = doc.data()["username"] as? String else {
                    return nil
                }
                
                return SearchSuggestion(
                    id: doc.documentID,
                    text: displayName,
                    category: .person,
                    icon: "person.circle.fill",
                    color: "purple",
                    context: "@\(username)",
                    popularity: 10
                )
            }
        } catch {
            print("❌ Error getting people suggestions: \(error)")
            return []
        }
    }
    
    // MARK: - Get User Suggestions (@username)
    
    private func getUserSuggestions(query: String) async -> [SearchSuggestion] {
        let username = String(query.dropFirst()) // Remove @
        
        guard !username.isEmpty else { return [] }
        
        do {
            let snapshot = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: username)
                .whereField("username", isLessThan: username + "\u{f8ff}")
                .limit(to: 5)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                guard let displayName = doc.data()["displayName"] as? String,
                      let username = doc.data()["username"] as? String else {
                    return nil
                }
                
                return SearchSuggestion(
                    id: doc.documentID,
                    text: "@\(username)",
                    category: .person,
                    icon: "at",
                    color: "purple",
                    context: displayName,
                    popularity: 15
                )
            }
        } catch {
            print("❌ Error getting user suggestions: \(error)")
            return []
        }
    }
    
    // MARK: - Get Group Suggestions
    
    private func getGroupSuggestions(query: String) async -> [SearchSuggestion] {
        do {
            let snapshot = try await db.collection("groups")
                .whereField("searchKeywords", arrayContains: query.lowercased())
                .limit(to: 3)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc in
                guard let name = doc.data()["name"] as? String,
                      let memberCount = doc.data()["memberCount"] as? Int else {
                    return nil
                }
                
                return SearchSuggestion(
                    id: doc.documentID,
                    text: name,
                    category: .group,
                    icon: "person.3.fill",
                    color: "blue",
                    context: "\(memberCount) members",
                    popularity: 8
                )
            }
        } catch {
            print("❌ Error getting group suggestions: \(error)")
            return []
        }
    }
    
    // MARK: - Get Topic Suggestions
    
    private func getTopicSuggestions(query: String) async -> [SearchSuggestion] {
        let cleanQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
        
        // Predefined topics
        let topics = [
            ("prayer", "hands.sparkles.fill", "orange"),
            ("bible study", "book.closed.fill", "green"),
            ("testimony", "star.fill", "yellow"),
            ("worship", "music.note", "pink"),
            ("devotional", "book.fill", "purple"),
            ("missions", "globe.americas.fill", "blue"),
            ("youth", "person.2.fill", "indigo"),
            ("family", "house.fill", "teal")
        ]
        
        let matching = topics.filter { $0.0.contains(cleanQuery.lowercased()) }
        
        return matching.map { topic in
            SearchSuggestion(
                id: UUID().uuidString,
                text: "#\(topic.0)",
                category: .topic,
                icon: topic.1,
                color: topic.2,
                context: "Topic",
                popularity: 5
            )
        }
    }
    
    // MARK: - Get Biblical Suggestions
    
    private func getBiblicalSuggestions(query: String) async -> [SearchSuggestion] {
        let biblicalTerms: [(String, String, String)] = [
            // People
            ("david", "King David - Shepherd, Warrior, Psalmist", "person.fill"),
            ("paul", "Apostle Paul - Missionary and Author", "person.fill"),
            ("peter", "Apostle Peter - Fisher of Men", "person.fill"),
            ("moses", "Moses - Prophet and Lawgiver", "person.fill"),
            ("jesus", "Jesus Christ - Son of God", "cross.fill"),
            ("mary", "Mary - Mother of Jesus", "person.fill"),
            ("abraham", "Abraham - Father of Faith", "person.fill"),
            ("solomon", "King Solomon - Wisdom and Temple", "person.fill"),
            
            // Places
            ("jerusalem", "Jerusalem - Holy City", "building.columns.fill"),
            ("bethlehem", "Bethlehem - Birthplace of Jesus", "building.2.fill"),
            ("nazareth", "Nazareth - Jesus' Hometown", "house.fill"),
            ("galilee", "Sea of Galilee - Ministry Location", "water.waves"),
            
            // Events
            ("exodus", "The Exodus - Deliverance from Egypt", "arrow.right.circle.fill"),
            ("resurrection", "The Resurrection - Victory over Death", "sunrise.fill"),
            ("pentecost", "Pentecost - Coming of Holy Spirit", "flame.fill"),
            ("crucifixion", "The Crucifixion - Ultimate Sacrifice", "cross.fill")
        ]
        
        let matching = biblicalTerms.filter { $0.0.contains(query.lowercased()) }
        
        return matching.map { term in
            SearchSuggestion(
                id: UUID().uuidString,
                text: term.0.capitalized,
                category: .bible,
                icon: term.2,
                color: "green",
                context: term.1,
                popularity: 20
            )
        }
    }
    
    // MARK: - Get Recent Search Suggestions
    
    private func getRecentSearchSuggestions(query: String) -> [SearchSuggestion] {
        let matching = recentSearches.filter { $0.lowercased().contains(query.lowercased()) }
        
        return matching.prefix(3).map { search in
            SearchSuggestion(
                id: UUID().uuidString,
                text: search,
                category: .recent,
                icon: "clock.arrow.circlepath",
                color: "gray",
                context: "Recent search",
                popularity: 3
            )
        }
    }
    
    // MARK: - Add Recent Search
    
    func addRecentSearch(_ query: String) {
        // Remove if already exists
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        
        // Add to beginning
        recentSearches.insert(query, at: 0)
        
        // Keep only last 20
        if recentSearches.count > 20 {
            recentSearches = Array(recentSearches.prefix(20))
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }
    
    // MARK: - Load Recent Searches
    
    func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    }
    
    // MARK: - Clear Suggestions
    
    func clearSuggestions() {
        searchTask?.cancel()
        suggestions = []
    }
}
