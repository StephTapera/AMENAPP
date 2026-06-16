//
//  VerseAttachmentViewModel.swift
//  AMENAPP
//
//  State machine for the Attach a Verse flow.
//  Manages mini attach, full search, inline suggestions,
//  quick replace, and prefetch coordination.
//

import SwiftUI
import Combine

// MARK: - Attachment Flow State

enum VerseAttachmentFlowState: Equatable {
    case idle
    case miniAttach
    case fullSearch
    case attaching
    case attached
    case replacing
    case openingScripture
    case error(String)
    
    static func == (lhs: VerseAttachmentFlowState, rhs: VerseAttachmentFlowState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.miniAttach, .miniAttach), (.fullSearch, .fullSearch),
             (.attaching, .attaching), (.attached, .attached), (.replacing, .replacing),
             (.openingScripture, .openingScripture):
            return true
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - ViewModel

@MainActor
final class VerseAttachmentViewModel: ObservableObject {
    
    // MARK: - Flow State
    
    @Published var flowState: VerseAttachmentFlowState = .idle
    
    // MARK: - Attached Scripture
    
    @Published var attachedScripture: ScriptureAttachment?
    
    // MARK: - Mini Attach
    
    @Published var showMiniAttach = false
    @Published var topSuggestion: BibleVerse?
    @Published var miniSuggestions: [BibleVerse] = []
    
    // MARK: - Full Sheet
    
    @Published var showFullSheet = false
    @Published var searchQuery = ""
    @Published var selectedTranslation: LocalBibleTranslation = .BSB
    @Published var selectedFilter: VerseSearchMode = .all
    @Published var searchResults: [SmartVerseResult] = []
    @Published var selectedSearchVerse: BibleVerse?
    @Published var isSearching = false
    @Published var searchError: String?
    
    // MARK: - Inline Suggestion
    
    @Published var showInlineSuggestion = false
    @Published var inlineSuggestedVerse: BereanScriptureChip?
    @Published var inlineSuggestionLabel: String = ""
    
    // MARK: - Quick Replace
    
    @Published var showQuickReplace = false
    @Published var quickReplaceResults: [BibleVerse] = []
    
    // MARK: - Scripture Detail
    
    @Published var showScriptureDetail = false
    @Published var scriptureDetailContext: SelahLaunchContext?
    
    // MARK: - Private
    
    private let searchEngine = VerseSmartSearchEngine()
    private let prefetchManager = ScripturePrefetchManager.shared
    private let recentHistory = RecentVerseHistory.shared
    private let intentDetector = ScriptureIntentDetector()
    
    private var searchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var dismissedSuggestions: Set<String> = []
    private var lastAnalyzedDraft: String = ""
    
    // MARK: - Computed
    
    var hasAttachment: Bool { attachedScripture != nil }
    var recentVerses: [ScriptureAttachment] { recentHistory.recentVerses }
    
    // MARK: - Actions
    
    /// Open the mini attach drawer
    func openMiniAttach(draftText: String) {
        flowState = .miniAttach
        showMiniAttach = true
        
        // Build suggestions from draft context
        Task {
            await buildMiniSuggestions(draftText: draftText)
        }
    }
    
    /// Expand mini to full sheet
    func expandToFullSheet() {
        flowState = .fullSearch
        showMiniAttach = false
        showFullSheet = true
    }
    
    /// Dismiss mini attach
    func dismissMiniAttach() {
        showMiniAttach = false
        flowState = hasAttachment ? .attached : .idle
    }
    
    /// Dismiss full sheet
    func dismissFullSheet() {
        showFullSheet = false
        searchQuery = ""
        selectedSearchVerse = nil
        searchResults = []
        searchError = nil
        flowState = hasAttachment ? .attached : .idle
    }
    
    /// Attach from inline scripture chip suggestion
    func attachVerse(_ chip: BereanScriptureChip, source: ScriptureAttachment.AttachmentSource) {
        let attachment = ScriptureAttachment.from(chip: chip, source: source)
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
            attachedScripture = attachment
            flowState = .attached
        }
        recentHistory.addVerse(attachment)
        prefetchManager.prefetch(attachment: attachment)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showMiniAttach = false
        showFullSheet = false
        showQuickReplace = false
        searchQuery = ""
        selectedSearchVerse = nil
        searchResults = []
    }

    /// Attach a verse
    func attachVerse(_ verse: BibleVerse, source: ScriptureAttachment.AttachmentSource) {
        let attachment = ScriptureAttachment.from(verse: verse, source: source)
        
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
            attachedScripture = attachment
            flowState = .attached
        }
        
        // Record in history
        recentHistory.addVerse(attachment)
        
        // Prefetch for fast open
        prefetchManager.prefetch(attachment: attachment)
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Dismiss surfaces
        showMiniAttach = false
        showFullSheet = false
        showQuickReplace = false
        
        // Reset search
        searchQuery = ""
        selectedSearchVerse = nil
        searchResults = []
    }
    
    /// Remove attached scripture
    func removeAttachment() {
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
            attachedScripture = nil
            flowState = .idle
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    /// Replace attached scripture (opens quick replace)
    func openQuickReplace() {
        guard hasAttachment else { return }
        flowState = .replacing
        showQuickReplace = true
        
        Task {
            await buildQuickReplaceResults()
        }
    }
    
    /// Dismiss quick replace
    func dismissQuickReplace() {
        showQuickReplace = false
        flowState = hasAttachment ? .attached : .idle
    }
    
    /// Open scripture detail via SelahView
    func openScriptureDetail(from sourceContext: SelahLaunchContext.SourceContext = .composer) {
        guard let attachment = attachedScripture else { return }
        flowState = .openingScripture
        
        let payload = prefetchManager.getCachedPayload(for: attachment)
        
        scriptureDetailContext = SelahLaunchContext(
            attachment: attachment,
            sourceContext: sourceContext,
            prefetchedPayload: payload,
            translationPreference: selectedTranslation.rawValue,
            openMode: .verseFocus
        )
        showScriptureDetail = true
    }
    
    /// Open scripture detail for a specific attachment (e.g. from post card)
    func openScriptureDetail(for attachment: ScriptureAttachment, from sourceContext: SelahLaunchContext.SourceContext = .postCard) {
        flowState = .openingScripture
        
        let payload = prefetchManager.getCachedPayload(for: attachment)
        
        scriptureDetailContext = SelahLaunchContext(
            attachment: attachment,
            sourceContext: sourceContext,
            prefetchedPayload: payload,
            translationPreference: attachment.translation,
            openMode: .verseFocus
        )
        showScriptureDetail = true
    }
    
    func dismissScriptureDetail() {
        showScriptureDetail = false
        scriptureDetailContext = nil
        flowState = hasAttachment ? .attached : .idle
    }
    
    // MARK: - Search
    
    func performSearch() {
        searchTask?.cancel()
        
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            searchError = nil
            return
        }
        
        isSearching = true
        searchError = nil
        
        searchTask = Task {
            // Debounce 250ms
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            
            let baseVM = AttachVerseViewModel()
            await searchEngine.search(query: query, translation: selectedTranslation, baseViewModel: baseVM)
            
            guard !Task.isCancelled else { return }
            
            searchResults = searchEngine.results
            isSearching = false
            
            // Prefetch top results
            for result in searchEngine.results.prefix(3) {
                let attachment = ScriptureAttachment.from(verse: result.verse, source: .manualSearch)
                prefetchManager.prefetch(attachment: attachment)
            }
        }
    }
    
    // MARK: - Inline Intelligence
    
    /// Analyze draft text for scripture suggestions (debounced)
    func analyzeDraftText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip if unchanged or too short
        guard trimmed.count >= 8, trimmed != lastAnalyzedDraft else {
            if trimmed.count < 8 {
                withAnimation { showInlineSuggestion = false }
            }
            return
        }
        lastAnalyzedDraft = trimmed
        
        suggestionTask?.cancel()
        suggestionTask = Task {
            // Debounce 800ms for typing
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            
            let result = intentDetector.detect(in: trimmed)
            
            guard !Task.isCancelled, result.confidence >= 0.7 else {
                withAnimation { showInlineSuggestion = false }
                return
            }
            
            // Check if dismissed
            if dismissedSuggestions.contains(result.verse.reference) {
                return
            }
            
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                inlineSuggestedVerse = result.verse
                inlineSuggestionLabel = result.reason
                showInlineSuggestion = true
            }
        }
    }
    
    /// Dismiss inline suggestion
    func dismissInlineSuggestion() {
        if let verse = inlineSuggestedVerse {
            dismissedSuggestions.insert(verse.reference)
        }
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
            showInlineSuggestion = false
            inlineSuggestedVerse = nil
        }
    }
    
    // MARK: - Bridge (backwards compat)
    
    /// Legacy: get reference string for post data
    var legacyVerseReference: String {
        attachedScripture?.canonicalReference ?? ""
    }
    
    /// Legacy: get text string for post data
    var legacyVerseText: String {
        attachedScripture?.previewText ?? ""
    }
    
    /// Restore from legacy data
    func restoreFromLegacy(reference: String, text: String) {
        guard !reference.isEmpty else { return }
        if let attachment = ScriptureAttachment.from(legacyReference: reference, legacyText: text) {
            attachedScripture = attachment
            flowState = .attached
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildMiniSuggestions(draftText: String) async {
        var suggestions: [BibleVerse] = []
        
        // 1. Check draft for a strong suggestion
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 8 {
            let result = intentDetector.detect(in: trimmed)
            if result.confidence >= 0.6 {
                let chip = result.verse
                let parsed = ScriptureReferenceParser.parse(chip.reference)
                let bookId = BibleBook.all.first(where: { $0.displayName == parsed.book })?.id ?? parsed.book.lowercased()
                let ref = ScriptureReference(bookId: bookId, chapter: parsed.chapter, startVerse: parsed.verseStart, endVerse: parsed.verseEnd)
                topSuggestion = BibleVerse(reference: ref, number: parsed.verseStart, text: chip.text, translation: chip.translation)
            } else {
                topSuggestion = nil
            }
        } else {
            topSuggestion = nil
        }
        
        // 2. Recent verses
        let recentBibleVerses = recentHistory.recentVerses.prefix(4).map { $0.asBibleVerse }
        suggestions.append(contentsOf: recentBibleVerses)
        
        // 3. Popular verses as fallback if no recent
        if suggestions.isEmpty {
            let popular = searchEngine.getPopularVerses(translation: selectedTranslation)
            suggestions = popular.map { $0.verse }
        }
        
        miniSuggestions = suggestions
    }
    
    private func buildQuickReplaceResults() async {
        guard let current = attachedScripture else { return }
        var results: [BibleVerse] = []
        
        // 1. Same chapter, nearby verses
        let baseVM = AttachVerseViewModel()
        baseVM.selectedTranslation = selectedTranslation
        
        // Search by book name for related verses
        await searchEngine.search(query: current.book, translation: selectedTranslation, baseViewModel: baseVM)
        let related = searchEngine.results
            .filter { $0.verse.reference.displayString != current.canonicalReference }
            .prefix(3)
            .map { $0.verse }
        results.append(contentsOf: related)

        // 2. Same topic if we can detect
        let topicResults = searchEngine.getTopicalSuggestions(
            topic: detectTopicFromVerse(current),
            translation: selectedTranslation
        )
        let topicVerses = topicResults
            .filter { $0.verse.reference.displayString != current.canonicalReference }
            .prefix(3)
            .map { $0.verse }
        results.append(contentsOf: topicVerses)
        
        // 3. Recent (not current)
        let recentOthers = recentHistory.recentVerses
            .filter { $0.canonicalReference != current.canonicalReference }
            .prefix(3)
            .map { $0.asBibleVerse }
        results.append(contentsOf: recentOthers)
        
        // Deduplicate
        var seen = Set<String>()
        quickReplaceResults = results.filter { verse in
            let key = verse.reference.displayString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
    
    private func detectTopicFromVerse(_ attachment: ScriptureAttachment) -> VerseTopic {
        let text = attachment.previewText.lowercased()
        for topic in VerseTopic.allCases {
            for keyword in topic.keywords {
                if text.contains(keyword) {
                    return topic
                }
            }
        }
        return .hope // default fallback
    }
}

// MARK: - SelahView Launch Context

struct SelahLaunchContext: Equatable {
    let attachment: ScriptureAttachment
    let sourceContext: SourceContext
    let prefetchedPayload: PrefetchedScripturePayload?
    let translationPreference: String
    let openMode: OpenMode
    
    enum SourceContext: String {
        case composer
        case postCard
        case inlineSuggestion
        case replaceDrawer
        case miniAttach
    }
    
    enum OpenMode: String {
        case verseFocus
        case chapterFocus
        case readOnly
    }
    
    static func == (lhs: SelahLaunchContext, rhs: SelahLaunchContext) -> Bool {
        lhs.attachment == rhs.attachment && lhs.sourceContext == rhs.sourceContext
    }
}
