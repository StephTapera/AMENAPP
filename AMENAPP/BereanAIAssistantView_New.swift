//
//  BereanAIAssistantView.swift
//  AMENAPP
//
//  Redesigned with Next.js-inspired minimalist interface
//

import SwiftUI
import Combine

/// Berean AI Assistant - Clean, modern, intelligent Bible study companion
struct BereanAIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BereanViewModel()

    // Search and interaction state
    @State private var searchText = ""
    @State private var isSearchFocused = false
    @FocusState private var searchFieldFocused: Bool
    @State private var searchSuggestions: [String] = []
    @State private var showingSuggestions = false
    @State private var isThinking = false

    // Smart features
    @State private var recentSearches: [String] = []
    @State private var popularQuestions: [QuickAction] = []
    @State private var showHistory = false

    var body: some View {
        ZStack {
            // Clean gray background (Next.js style)
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                ScrollView {
                    VStack(spacing: 40) {
                        Spacer().frame(height: 60)

                        // Large centered title
                        titleSection

                        // Smart search bar
                        smartSearchBar

                        // Search suggestions (if active)
                        if showingSuggestions && !searchSuggestions.isEmpty {
                            suggestionsPanel
                        }

                        Spacer().frame(height: 40)

                        // Action cards (Next.js style)
                        actionCardsGrid

                        Spacer().frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Conversation view overlay (when chat is active)
            if !viewModel.messages.isEmpty {
                conversationOverlay
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            loadSmartFeatures()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    )
            }

            Spacer()

            // By AMEN badge
            Text("By AMEN")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.6))

            // Settings button
            Button {
                // Show settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 12) {
            // Main title (like NEXT.JS)
            HStack(spacing: 0) {
                Text("BEREAN")
                    .font(.system(size: 52, weight: .bold, design: .default))
                    .foregroundStyle(.black)

                Text("AI")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(.leading, 4)
            }
            .tracking(-1.5)

            // Subtitle
            Text("Your intelligent Bible study companion")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
        }
    }

    // MARK: - Smart Search Bar

    private var smartSearchBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Search icon
                Image(systemName: isSearchFocused ? "sparkles" : "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSearchFocused ? .orange : .black.opacity(0.4))
                    .symbolEffect(.bounce, value: isSearchFocused)

                // Search field
                TextField("Ask anything about the Bible...", text: $searchText)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.black)
                    .focused($searchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) { _, newValue in
                        updateSearchSuggestions(for: newValue)
                    }

                // Clear button
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchSuggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }

                // Voice search button
                Button {
                    // Start voice input
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(isSearchFocused ? 0.12 : 0.08), radius: isSearchFocused ? 12 : 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSearchFocused ? Color.orange.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .onChange(of: searchFieldFocused) { _, isFocused in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isSearchFocused = isFocused
                }
            }

            // Quick search tips
            if !isSearchFocused && searchText.isEmpty {
                HStack(spacing: 8) {
                    ForEach(["Cross-references", "Greek meaning", "Timeline"], id: \.self) { tip in
                        Button {
                            searchText = tip
                            searchFieldFocused = true
                        } label: {
                            Text(tip)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.white)
                                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                                )
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSearchFocused)
    }

    // MARK: - Search Suggestions

    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchSuggestions.prefix(5), id: \.self) { suggestion in
                Button {
                    searchText = suggestion
                    performSearch()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.black.opacity(0.4))

                        Text(suggestion)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.black.opacity(0.8))

                        Spacer()

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.01))
                }
                .buttonStyle(.plain)

                if suggestion != searchSuggestions.prefix(5).last {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    // MARK: - Action Cards Grid

    private var actionCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ActionCard(
                icon: "book.fill",
                title: "Study Plans",
                description: "Structured Bible reading and study guides",
                action: { showStudyPlans() }
            )

            ActionCard(
                icon: "lightbulb.fill",
                title: "Devotionals",
                description: "AI-generated daily devotional content",
                action: { showDevotionals() }
            )

            ActionCard(
                icon: "person.2.fill",
                title: "Characters",
                description: "Deep dives into Biblical personalities",
                action: { showCharacters() }
            )

            ActionCard(
                icon: "chart.bar.fill",
                title: "Timeline",
                description: "Interactive historical Bible timeline",
                action: { showTimeline() }
            )

            ActionCard(
                icon: "globe",
                title: "Translations",
                description: "Compare multiple Bible translations",
                action: { showTranslations() }
            )

            ActionCard(
                icon: "bookmark.fill",
                title: "Saved",
                description: "Your saved insights and conversations",
                action: { showSaved() }
            )
        }
    }

    // MARK: - Conversation Overlay

    private var conversationOverlay: some View {
        VStack(spacing: 0) {
            // Conversation header
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.messages.removeAll()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.6))
                }

                Text("Conversation")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)

                Spacer()

                Button {
                    // Clear conversation
                    viewModel.messages.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.white)

            // Messages
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.96))

            // Input bar
            conversationInputBar
        }
        .background(.white)
    }

    private var conversationInputBar: some View {
        HStack(spacing: 12) {
            TextField("Type your message...", text: $searchText)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                )

            Button {
                performSearch()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(searchText.isEmpty ? .gray : .orange)
            }
            .disabled(searchText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        // Add to recent searches
        if !recentSearches.contains(searchText) {
            recentSearches.insert(searchText, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
        }

        // Send message
        Task {
            await viewModel.sendMessage(searchText)
            searchText = ""
            showingSuggestions = false
            searchFieldFocused = false
        }
    }

    private func updateSearchSuggestions(for query: String) {
        guard !query.isEmpty else {
            searchSuggestions = []
            showingSuggestions = false
            return
        }

        // Smart suggestions based on query
        let smartSuggestions = generateSmartSuggestions(for: query)

        withAnimation(.easeOut(duration: 0.2)) {
            searchSuggestions = smartSuggestions
            showingSuggestions = !smartSuggestions.isEmpty
        }
    }

    private func generateSmartSuggestions(for query: String) -> [String] {
        let lowercasedQuery = query.lowercased()
        var suggestions: [String] = []

        // Context-aware suggestions
        if lowercasedQuery.contains("what") || lowercasedQuery.contains("who") {
            suggestions.append(contentsOf: [
                "What does \(query) mean in Greek?",
                "Who was \(query) in the Bible?",
                "What are cross-references for \(query)?"
            ])
        }

        if lowercasedQuery.contains("how") || lowercasedQuery.contains("why") {
            suggestions.append(contentsOf: [
                "How is \(query) relevant today?",
                "Why did \(query) happen?",
                "How can I apply \(query) to my life?"
            ])
        }

        // Topic-based suggestions
        if lowercasedQuery.contains("love") || lowercasedQuery.contains("faith") || lowercasedQuery.contains("hope") {
            suggestions.append("Show me verses about \(query)")
            suggestions.append("Study guide on \(query)")
        }

        // Recent searches
        suggestions.append(contentsOf: recentSearches.filter { $0.lowercased().contains(lowercasedQuery) })

        return Array(Set(suggestions)).prefix(5).map { $0 }
    }

    private func loadSmartFeatures() {
        // Load popular questions
        popularQuestions = [
            QuickAction(title: "What does love mean in Greek?", icon: "text.book.closed"),
            QuickAction(title: "Timeline of Jesus' life", icon: "calendar"),
            QuickAction(title: "Meaning of Psalms 23", icon: "book"),
            QuickAction(title: "Who was Paul?", icon: "person")
        ]
    }

    private func showStudyPlans() {
        searchText = "Show me Bible study plans"
        performSearch()
    }

    private func showDevotionals() {
        searchText = "Generate a devotional for today"
        performSearch()
    }

    private func showCharacters() {
        searchText = "Tell me about Biblical characters"
        performSearch()
    }

    private func showTimeline() {
        searchText = "Show me a Biblical timeline"
        performSearch()
    }

    private func showTranslations() {
        searchText = "Compare Bible translations"
        performSearch()
    }

    private func showSaved() {
        // Show saved messages
    }
}

// MARK: - Action Card

struct ActionCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))

                // Title with arrow
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black.opacity(0.4))
                }

                // Description
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.black.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(color: .black.opacity(isPressed ? 0.12 : 0.08), radius: isPressed ? 8 : 12, y: 4)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: BereanMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(message.isUser ? .white : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.isUser ? Color.black : Color.white)
                    )

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.black.opacity(0.4))
                    .padding(.horizontal, 4)
            }

            if !message.isUser {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Supporting Types

struct QuickAction {
    let title: String
    let icon: String
}
