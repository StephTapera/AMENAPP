//
//  AISearchExamples.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//

import SwiftUI

// MARK: - Example Search Test View

/// This view demonstrates the AI Search components with sample data
/// Use this to test the search UI without needing the backend
struct AISearchExamplesView: View {
    @State private var searchQuery = ""
    @State private var showingSuggestions = false
    @State private var showingBiblicalCard = false
    @State private var showingFilterBanner = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Search...", text: $searchQuery)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .onChange(of: searchQuery) { oldValue, newValue in
                                // Simulate AI response
                                withAnimation {
                                    showingSuggestions = !newValue.isEmpty
                                    showingBiblicalCard = newValue.lowercased().contains("david") ||
                                                         newValue.lowercased().contains("paul") ||
                                                         newValue.lowercased().contains("jerusalem")
                                    showingFilterBanner = newValue.lowercased().contains("prayer") ||
                                                         newValue.lowercased().contains("worship")
                                }
                            }
                        
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                    
                    // Instructions
                    if searchQuery.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.purple.gradient)
                            
                            Text("Try These Example Searches:")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ExampleSearchRow(
                                    icon: "person.fill",
                                    query: "David",
                                    description: "Biblical person search"
                                ) {
                                    searchQuery = "David"
                                }
                                
                                ExampleSearchRow(
                                    icon: "location.fill",
                                    query: "Jerusalem",
                                    description: "Biblical place search"
                                ) {
                                    searchQuery = "Jerusalem"
                                }
                                
                                ExampleSearchRow(
                                    icon: "hands.sparkles.fill",
                                    query: "Prayer groups",
                                    description: "Smart filter suggestion"
                                ) {
                                    searchQuery = "Prayer groups"
                                }
                                
                                ExampleSearchRow(
                                    icon: "music.note",
                                    query: "Worship events",
                                    description: "Smart filter suggestion"
                                ) {
                                    searchQuery = "Worship events"
                                }
                                
                                ExampleSearchRow(
                                    icon: "sparkles",
                                    query: "Bible study",
                                    description: "AI suggestions"
                                ) {
                                    searchQuery = "Bible study"
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 10)
                            )
                            .padding(.horizontal)
                        }
                        .padding(.top, 40)
                    }
                    
                    // AI Components (shown when searching)
                    if !searchQuery.isEmpty {
                        VStack(spacing: 16) {
                            // Smart Filter Banner
                            if showingFilterBanner {
                                SmartFilterBanner(
                                    suggestion: SampleData.filterSuggestion,
                                    onApplyFilters: { filters in
                                        print("Applied filters: \(filters)")
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            }
                            
                            // Biblical Search Card
                            if showingBiblicalCard {
                                if searchQuery.lowercased().contains("david") {
                                    BiblicalSearchCard(result: SampleData.davidResult)
                                        .transition(.scale.combined(with: .opacity))
                                } else if searchQuery.lowercased().contains("paul") {
                                    BiblicalSearchCard(result: SampleData.paulResult)
                                        .transition(.scale.combined(with: .opacity))
                                } else if searchQuery.lowercased().contains("jerusalem") {
                                    BiblicalSearchCard(result: SampleData.jerusalemResult)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            
                            // AI Suggestions Panel
                            if showingSuggestions {
                                AISearchSuggestionsPanel(
                                    query: searchQuery,
                                    suggestions: SampleData.getSuggestions(for: searchQuery),
                                    relatedTopics: SampleData.getRelatedTopics(for: searchQuery),
                                    onSuggestionTap: { suggestion in
                                        searchQuery = suggestion
                                    }
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Search Examples")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Example Search Row Component

struct ExampleSearchRow: View {
    let icon: String
    let query: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(query)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple.opacity(0.3))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sample Data

struct SampleData {
    // MARK: - Biblical Search Results
    
    static let davidResult = BiblicalSearchResult(
        query: "David",
        summary: "David was the second king of Israel and Judah, known for his faith in God, his defeat of Goliath, and his authorship of many Psalms. Despite his sins, he was called 'a man after God's own heart' due to his genuine repentance and devotion.",
        keyVerses: [
            "1 Samuel 17:45",
            "Psalm 23:1",
            "Acts 13:22",
            "2 Samuel 7:16"
        ],
        relatedPeople: [
            "Goliath",
            "Saul",
            "Jonathan",
            "Bathsheba",
            "Solomon",
            "Samuel"
        ],
        funFacts: [
            "David wrote approximately 73 of the 150 Psalms",
            "He was a skilled musician who played the harp for King Saul",
            "Jesus is referred to as the 'Son of David' throughout the New Testament",
            "David's reign lasted 40 years, from approximately 1010-970 BC"
        ]
    )
    
    static let paulResult = BiblicalSearchResult(
        query: "Paul",
        summary: "The Apostle Paul, originally named Saul of Tarsus, was a former persecutor of Christians who became one of the most influential missionaries and writers in early Christianity. He wrote 13 books of the New Testament and spread the Gospel throughout the Mediterranean world.",
        keyVerses: [
            "Acts 9:3-6",
            "Philippians 4:13",
            "Romans 8:28",
            "2 Corinthians 12:9"
        ],
        relatedPeople: [
            "Barnabas",
            "Timothy",
            "Silas",
            "Luke",
            "Priscilla",
            "Aquila"
        ],
        funFacts: [
            "Paul traveled over 10,000 miles on his missionary journeys",
            "He wrote many of his letters while imprisoned",
            "Paul was both a Roman citizen and a Pharisee",
            "He established churches in major cities like Corinth, Ephesus, and Philippi"
        ]
    )
    
    static let jerusalemResult = BiblicalSearchResult(
        query: "Jerusalem",
        summary: "Jerusalem is one of the oldest and most significant cities in biblical history, serving as the capital of ancient Israel and the location of Solomon's Temple. It's considered holy by Judaism, Christianity, and Islam, and plays a central role in biblical prophecy.",
        keyVerses: [
            "Psalm 122:6",
            "2 Chronicles 6:6",
            "Luke 19:41",
            "Revelation 21:2"
        ],
        relatedPeople: [
            "David",
            "Solomon",
            "Jesus",
            "Nehemiah",
            "Melchizedek"
        ],
        funFacts: [
            "Jerusalem has been destroyed and rebuilt at least twice",
            "The city sits at 2,500 feet above sea level",
            "It's mentioned over 800 times in the Bible",
            "Three major world religions consider it a holy city"
        ]
    )
    
    // MARK: - Search Suggestions
    
    static func getSuggestions(for query: String) -> [String] {
        let lowercased = query.lowercased()
        
        if lowercased.contains("david") {
            return [
                "King David's life story",
                "David and Goliath battle",
                "Psalms written by David",
                "David and Jonathan friendship"
            ]
        } else if lowercased.contains("paul") {
            return [
                "Paul's conversion story",
                "Paul's missionary journeys",
                "Letters written by Paul",
                "Paul and Barnabas ministry"
            ]
        } else if lowercased.contains("jerusalem") {
            return [
                "History of Jerusalem",
                "Jerusalem in prophecy",
                "Temple of Jerusalem",
                "Jesus in Jerusalem"
            ]
        } else if lowercased.contains("prayer") {
            return [
                "Prayer meeting groups near me",
                "Weekly prayer gatherings",
                "Morning prayer circles",
                "Prayer warrior communities"
            ]
        } else if lowercased.contains("worship") {
            return [
                "Worship night events",
                "Contemporary worship services",
                "Worship team opportunities",
                "Sunday worship gatherings"
            ]
        } else if lowercased.contains("bible") || lowercased.contains("study") {
            return [
                "Bible study groups in my area",
                "Online Bible studies",
                "Women's Bible study",
                "Men's Bible study fellowship"
            ]
        } else {
            return [
                "Christian fellowship groups",
                "Local church events",
                "Youth ministry activities",
                "Small group gatherings"
            ]
        }
    }
    
    static func getRelatedTopics(for query: String) -> [String] {
        let lowercased = query.lowercased()
        
        if lowercased.contains("david") {
            return ["Psalms", "King Saul", "Solomon", "Israel", "Shepherd", "Temple"]
        } else if lowercased.contains("paul") {
            return ["Acts", "Romans", "Corinthians", "Missionary", "Grace", "Faith"]
        } else if lowercased.contains("jerusalem") {
            return ["Temple", "Zion", "Holy City", "Bethlehem", "Mount of Olives"]
        } else if lowercased.contains("prayer") {
            return ["Intercession", "Worship", "Fellowship", "Devotional", "Meditation"]
        } else if lowercased.contains("worship") {
            return ["Praise", "Music", "Liturgy", "Church", "Hymns", "Devotion"]
        } else if lowercased.contains("bible") || lowercased.contains("study") {
            return ["Scripture", "Teaching", "Discipleship", "Small Groups", "Commentary"]
        } else {
            return ["Community", "Faith", "Church", "Fellowship", "Ministry"]
        }
    }
    
    // MARK: - Filter Suggestions
    
    static let filterSuggestion = FilterSuggestion(
        filters: ["groups", "events"],
        explanation: "Based on your search for prayer-related content, we recommend filtering by Groups and Events to find prayer meetings, gatherings, and community groups in your area."
    )
}

// MARK: - Preview

#Preview("AI Search Examples") {
    AISearchExamplesView()
}

#Preview("David Search Card") {
    ScrollView {
        BiblicalSearchCard(result: SampleData.davidResult)
            .padding(.top)
    }
}

#Preview("AI Suggestions Panel") {
    ScrollView {
        AISearchSuggestionsPanel(
            query: "Bible study",
            suggestions: SampleData.getSuggestions(for: "Bible study"),
            relatedTopics: SampleData.getRelatedTopics(for: "Bible study"),
            onSuggestionTap: { suggestion in
                print("Tapped: \(suggestion)")
            }
        )
        .padding(.top)
    }
}

#Preview("Smart Filter Banner") {
    SmartFilterBanner(
        suggestion: SampleData.filterSuggestion,
        onApplyFilters: { filters in
            print("Applied: \(filters)")
        }
    )
    .padding()
}
