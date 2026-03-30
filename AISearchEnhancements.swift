//
//  AISearchEnhancements.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//

import SwiftUI

// MARK: - AI Search Suggestions Panel

struct AISearchSuggestionsPanel: View {
    let query: String
    let suggestions: [String]
    let relatedTopics: [String]
    let onSuggestionTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)
                
                Text("AI Suggestions")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
            }
            
            // Suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try searching for:")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            onSuggestionTap(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple)
                                
                                Text(suggestion)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.05))
                            )
                        }
                    }
                }
            }
            
            // Related Topics
            if !relatedTopics.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related topics:")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(relatedTopics, id: \.self) { topic in
                            Button {
                                onSuggestionTap(topic)
                            } label: {
                                Text(topic)
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.purple.opacity(0.1))
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Biblical Search Enhancement Card

struct BiblicalSearchCard: View {
    let result: BiblicalSearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.blue)
                
                Text("Biblical Context")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue.opacity(0.6))
                    .font(.system(size: 14))
            }
            
            // Summary
            Text(result.summary)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Key Verses
            if !result.keyVerses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Verses")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(result.keyVerses, id: \.self) { verse in
                            VerseChip(reference: verse)
                        }
                    }
                }
            }
            
            // Related People
            if !result.relatedPeople.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related People")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(result.relatedPeople, id: \.self) { person in
                                PersonChip(name: person)
                            }
                        }
                    }
                }
            }
            
            // Fun Facts
            if !result.funFacts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        
                        Text("Did You Know?")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(Array(result.funFacts.enumerated()), id: \.offset) { index, fact in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                            
                            Text(fact)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        )
        .padding(.horizontal)
    }
}

// MARK: - Smart Filter Banner

struct SmartFilterBanner: View {
    let suggestion: FilterSuggestion
    let onApplyFilters: ([String]) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                    
                    Text("Smart Filters")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            if isExpanded {
                Text(suggestion.explanation)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                
                HStack(spacing: 8) {
                    ForEach(suggestion.filters, id: \.self) { filter in
                        Text(filter.capitalized)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.1))
                            )
                    }
                    
                    Spacer()
                    
                    Button {
                        onApplyFilters(suggestion.filters)
                    } label: {
                        Text("Apply")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.purple)
                            )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
}

// MARK: - Supporting Components

struct VerseChip: View {
    let reference: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10))
            
            Text(reference)
                .font(.custom("OpenSans-SemiBold", size: 12))
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.1))
        )
    }
}

struct PersonChip: View {
    let name: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 10))
            
            Text(name)
                .font(.custom("OpenSans-SemiBold", size: 12))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.1))
        )
    }
}

