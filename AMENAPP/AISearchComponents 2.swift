//
//  AISearchComponents.swift
//  AMENAPP
//
//  AI-powered search UI components
//  Suggestions, filter recommendations, and smart search pills
//

import SwiftUI

// Note: SearchSuggestion is defined in SearchSuggestionsService.swift

// MARK: - Filter Recommendation Model

struct AISearchFilterRecommendation: Identifiable {
    let id = UUID()
    let filter: String
    let reason: String
    let confidence: Double
}

// MARK: - AI Search Suggestion Chip

struct AISearchSuggestionChip: View {
    let suggestion: SearchSuggestion  // From SearchSuggestionsService.swift
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)

                Text(suggestion.text)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundColor(.black)
                    .lineLimit(1)

                if suggestion.popularity > 80 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isPressed ? 0.15 : 0.08), radius: isPressed ? 2 : 4, y: isPressed ? 1 : 2)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Filter Recommendation Pill

struct FilterRecommendationPill: View {
    let recommendation: AISearchFilterRecommendation
    let isSelected: Bool
    let action: () -> Void

    private var pillColor: Color {
        switch recommendation.filter.lowercased() {
        case "people", "believers":
            return .blue
        case "posts", "opentable":
            return .green
        case "prayer", "testimonies":
            return .purple
        case "groups", "churches":
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(pillColor)
                }

                Text(recommendation.filter.capitalized)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(isSelected ? pillColor : .black.opacity(0.7))

                if recommendation.confidence > 0.85 {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? pillColor.opacity(0.15) : Color.white)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? pillColor.opacity(0.5) : Color.black.opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Suggestions Section

struct AISearchSuggestionsSection: View {
    let suggestions: [SearchSuggestion]
    let onSelect: (SearchSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)

                Text("AI Suggestions")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        AISearchSuggestionChip(suggestion: suggestion) {
                            onSelect(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(
            Color(white: 0.97)
        )
    }
}

// MARK: - Filter Recommendations Section

struct FilterRecommendationsSection: View {
    let recommendations: [AISearchFilterRecommendation]
    let selectedFilter: String?
    let onSelect: (AISearchFilterRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)

                Text("Smart Filters")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                if let selected = selectedFilter {
                    Text("Active: \(selected)")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recommendations) { recommendation in
                        FilterRecommendationPill(
                            recommendation: recommendation,
                            isSelected: selectedFilter?.lowercased() == recommendation.filter.lowercased()
                        ) {
                            onSelect(recommendation)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Show reason for top recommendation
            if let topRec = recommendations.first, recommendations.count > 0 {
                Text("💡 \(topRec.reason)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 10)
        .background(
            Color(white: 0.97)
        )
    }
}

// MARK: - Enhanced Search Bar with AI

struct AIEnhancedSearchBar: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let showAIIndicator: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.gray)

            // Search field
            TextField("Search with AI...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
                .onChange(of: searchText) { _, _ in
                    isSearching = !searchText.isEmpty
                }

            // AI indicator
            if showAIIndicator {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)

                    Text("AI")
                        .font(.custom("OpenSans-Bold", size: 10))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.12))
                )
            }

            // Clear button
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearching = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.95))
        )
    }
}

// MARK: - AI Search Loading State

struct AISearchLoadingView: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Animated sparkles
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                        .opacity(0.3)
                        .scaleEffect(1.2)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: index
                        )
                }
            }

            Text("AI is searching...")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundColor(.black)

            Text("Finding the best results for \"\(query)\"")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.98))
    }
}

// MARK: - Empty Search State with AI Prompt

struct AISearchEmptyState: View {
    let suggestions: [String]
    let onSuggestionTap: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.blue)
            }

            // Title
            Text("Try AI-Powered Search")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundColor(.black)

            // Description
            Text("Get smarter suggestions and filter recommendations as you type")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Suggested searches
            VStack(alignment: .leading, spacing: 12) {
                Text("Try searching for:")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundColor(.secondary)

                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        onSuggestionTap(suggestion)
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)

                            Text(suggestion)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundColor(.black)

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        )
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.98))
    }
}
