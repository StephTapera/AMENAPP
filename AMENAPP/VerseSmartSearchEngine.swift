//
//  VerseSmartSearchEngine.swift
//  AMENAPP
//
//  Intelligent multi-modal verse search with reference parsing,
//  semantic matching, topic classification, person search, and date context
//

import Foundation
import Combine

@MainActor
class VerseSmartSearchEngine: ObservableObject {
    @Published var results: [SmartVerseResult] = []
    @Published var isSearching = false
    @Published var searchMode: VerseSearchMode = .all
    
    private var searchTask: Task<Void, Never>?
    
    // Reference pattern: matches "John 3:16", "1 Cor 13:4-8", "Phil 4", etc.
    private let referencePattern = try? NSRegularExpression(
        pattern: #"^[1-3]?\s?[A-Za-z]+\.?\s+\d+(?::\d+(?:-\d+)?)?"#,
        options: .caseInsensitive
    )
    
    /// Main search entry point with intelligent routing
    func search(query: String, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        
        searchTask?.cancel()
        isSearching = true
        
        searchTask = Task { @MainActor in
            // Brief debounce
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            
            // Route to appropriate search strategy
            var candidates: [BibleVerse] = []
            var matchType: SmartVerseResult.MatchType = .popular
            
            if isReference(trimmed) {
                // Direct reference lookup
                candidates = await searchByReference(trimmed, translation: translation, baseViewModel: baseViewModel)
                matchType = .exactReference
            } else if let person = detectPerson(trimmed) {
                // Person-based search
                candidates = await searchByPerson(person, translation: translation, baseViewModel: baseViewModel)
                matchType = .personMatch
            } else if let seasonal = detectSeasonal(trimmed) {
                // Date/seasonal search
                candidates = await searchBySeasonal(seasonal, translation: translation, baseViewModel: baseViewModel)
                matchType = .seasonalMatch
            } else if let topic = detectTopic(trimmed) {
                // Topic-based search
                candidates = await searchByTopic(topic, translation: translation, baseViewModel: baseViewModel)
                matchType = .topicMatch
            } else {
                // General keyword/phrase search
                candidates = await searchByKeyword(trimmed, translation: translation, baseViewModel: baseViewModel)
                matchType = .phraseMatch
            }
            
            guard !Task.isCancelled else { return }
            
            // Convert to SmartVerseResult with scoring
            let scored = scoreAndSort(verses: candidates, query: trimmed, primaryMatchType: matchType)
            results = scored
            isSearching = false
        }
    }
    
    // MARK: - Reference Detection & Search
    
    private func isReference(_ text: String) -> Bool {
        guard let regex = referencePattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    private func searchByReference(_ ref: String, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async -> [BibleVerse] {
        do {
            let passage = try await YouVersionBibleService.shared.fetchVerse(
                reference: ref,
                version: translation.apiVersion
            )
            return [makeBibleVerse(reference: passage.reference, text: passage.text, translation: translation.rawValue)]
        } catch {
            // Fallback to local library
            return LocalVerseLibrary.search(ref, translation: translation).map { makeBibleVerse(from: $0) }
        }
    }
    
    // MARK: - Topic Detection & Search
    
    private func detectTopic(_ query: String) -> VerseTopic? {
        let q = query.lowercased()
        
        for topic in VerseTopic.allCases {
            // Check if query contains topic name or keywords
            if q.contains(topic.rawValue.lowercased()) {
                return topic
            }
            for keyword in topic.keywords {
                if q.contains(keyword.lowercased()) || keyword.lowercased().contains(q) {
                    return topic
                }
            }
        }
        return nil
    }
    
    private func searchByTopic(_ topic: VerseTopic, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async -> [BibleVerse] {
        // Use first few keywords to search
        let primaryKeywords = Array(topic.keywords.prefix(3)).joined(separator: " ")
        return await searchByKeyword(primaryKeywords, translation: translation, baseViewModel: baseViewModel)
    }
    
    // MARK: - Person Detection & Search
    
    private func detectPerson(_ query: String) -> BiblicalPerson? {
        let q = query.lowercased()
        
        for person in BiblicalPerson.allCases {
            for term in person.searchTerms {
                if q.contains(term.lowercased()) {
                    return person
                }
            }
        }
        return nil
    }
    
    private func searchByPerson(_ person: BiblicalPerson, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async -> [BibleVerse] {
        // Search using person's primary name
        let searchTerm = person.searchTerms.first ?? person.rawValue
        return await searchByKeyword(searchTerm, translation: translation, baseViewModel: baseViewModel)
    }
    
    // MARK: - Seasonal/Date Context Detection & Search
    
    private func detectSeasonal(_ query: String) -> SeasonalContext? {
        let q = query.lowercased()
        
        // Direct seasonal match
        for context in SeasonalContext.allCases {
            if q.contains(context.rawValue.lowercased()) {
                return context
            }
        }
        
        // Contextual date matching
        if q.contains("sunday") || q.contains("worship") {
            return nil // Let it fall through to keyword search
        }
        if q.contains("morning") || q.contains("today") {
            return nil // General encouragement search
        }
        
        return nil
    }
    
    private func searchBySeasonal(_ seasonal: SeasonalContext, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async -> [BibleVerse] {
        // Use seasonal keywords
        let keywords = seasonal.keywords.prefix(2).joined(separator: " ")
        return await searchByKeyword(keywords, translation: translation, baseViewModel: baseViewModel)
    }
    
    // MARK: - General Keyword Search
    
    private func searchByKeyword(_ query: String, translation: LocalBibleTranslation, baseViewModel: AttachVerseViewModel) async -> [BibleVerse] {
        do {
            let passages = try await YouVersionBibleService.shared.searchVerses(
                query: query,
                version: translation.apiVersion,
                limit: 15
            )
            return passages.map { makeBibleVerse(reference: $0.reference, text: $0.text, translation: translation.rawValue) }
        } catch {
            // Fallback to local library
            return LocalVerseLibrary.search(query, translation: translation).map { makeBibleVerse(from: $0) }
        }
    }
    
    // MARK: - Scoring & Ranking
    
    private func scoreAndSort(verses: [BibleVerse], query: String, primaryMatchType: SmartVerseResult.MatchType) -> [SmartVerseResult] {
        let q = query.lowercased()
        
        return verses.map { verse in
            var score = 0
            let refLower = verse.reference.displayString.lowercased()
            let textLower = verse.text.lowercased()
            
            // Base score by match type
            switch primaryMatchType {
            case .exactReference: score += 1000
            case .bookChapter: score += 800
            case .phraseMatch: score += 500
            case .topicMatch: score += 600
            case .personMatch: score += 650
            case .seasonalMatch: score += 550
            case .popular: score += 400
            }
            
            // Reference relevance
            if refLower == q { score += 500 }
            else if refLower.hasPrefix(q) { score += 300 }
            else if refLower.contains(q) { score += 150 }
            
            // Text relevance
            if textLower.contains(q) { score += 200 }
            
            // Word-level matching
            let words = q.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 }
            for word in words {
                if textLower.contains(word) { score += 50 }
                if refLower.contains(word) { score += 75 }
            }
            
            // Detect topics for categorization
            let detectedTopics = detectTopicsInVerse(verse)
            
            return SmartVerseResult(
                verse: verse,
                relevanceScore: score,
                matchType: primaryMatchType,
                topics: detectedTopics
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
        .prefix(12)
        .map { $0 }
    }
    
    private func detectTopicsInVerse(_ verse: BibleVerse) -> [VerseTopic] {
        let textLower = verse.text.lowercased()
        var topics: [VerseTopic] = []
        
        for topic in VerseTopic.allCases {
            for keyword in topic.keywords {
                if textLower.contains(keyword.lowercased()) {
                    if !topics.contains(topic) {
                        topics.append(topic)
                    }
                    break
                }
            }
        }
        
        return Array(topics.prefix(3))
    }
    
    // MARK: - Quick Popular/Recent Suggestions
    
    func getPopularVerses(translation: LocalBibleTranslation) -> [SmartVerseResult] {
        let popular = [
            "John 3:16",
            "Philippians 4:13",
            "Jeremiah 29:11",
            "Psalm 23:1",
            "Proverbs 3:5-6",
            "Romans 8:28"
        ]
        
        return popular.compactMap { ref in
            let verses = LocalVerseLibrary.search(ref, translation: translation).map { makeBibleVerse(from: $0) }
            guard let verse = verses.first else { return nil }
            return SmartVerseResult(
                verse: verse,
                relevanceScore: 100,
                matchType: .popular,
                topics: detectTopicsInVerse(verse)
            )
        }
    }

    func getTopicalSuggestions(topic: VerseTopic, translation: LocalBibleTranslation) -> [SmartVerseResult] {
        let keywords = topic.keywords.first ?? topic.rawValue
        let verses = LocalVerseLibrary.search(keywords, translation: translation).map { makeBibleVerse(from: $0) }

        return verses.prefix(5).map { verse in
            SmartVerseResult(
                verse: verse,
                relevanceScore: 50,
                matchType: .topicMatch,
                topics: [topic]
            )
        }
    }

    // MARK: - Conversion Helpers

    private func makeBibleVerse(from av: AttachableVerse) -> BibleVerse {
        let parsed = ScriptureReferenceParser.parse(av.reference)
        let bookId = BibleBook.all.first(where: { $0.displayName == parsed.book })?.id ?? parsed.book.lowercased()
        let ref = ScriptureReference(bookId: bookId, chapter: parsed.chapter, startVerse: parsed.verseStart, endVerse: parsed.verseEnd)
        return BibleVerse(reference: ref, number: parsed.verseStart, text: av.text, translation: av.translation)
    }

    private func makeBibleVerse(reference: String, text: String, translation: String) -> BibleVerse {
        let parsed = ScriptureReferenceParser.parse(reference)
        let bookId = BibleBook.all.first(where: { $0.displayName == parsed.book })?.id ?? parsed.book.lowercased()
        let ref = ScriptureReference(bookId: bookId, chapter: parsed.chapter, startVerse: parsed.verseStart, endVerse: parsed.verseEnd)
        return BibleVerse(reference: ref, number: parsed.verseStart, text: text, translation: translation)
    }
}
