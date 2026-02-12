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
                                .transition(AnyTransition.asymmetric(
                                    insertion: AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity),
                                    removal: AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity)
                                ))
                            }
                            
                            // Biblical Search Card
                            if showingBiblicalCard {
                                if searchQuery.lowercased().contains("david") {
                                    BiblicalSearchCard(result: SampleData.davidResult)
                                        .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
                                } else if searchQuery.lowercased().contains("paul") {
                                    BiblicalSearchCard(result: SampleData.paulResult)
                                        .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
                                } else if searchQuery.lowercased().contains("jerusalem") {
                                    BiblicalSearchCard(result: SampleData.jerusalemResult)
                                        .transition(AnyTransition.scale.combined(with: AnyTransition.opacity))
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
                                .transition(AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity))
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

// MARK: - Preview

#Preview("AI Search Examples") {
    AISearchExamplesView()
}

#Preview("David Search Card") {
    ScrollView {
        BiblicalSearchCard(result: SampleData.davidResult)
            .padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
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
