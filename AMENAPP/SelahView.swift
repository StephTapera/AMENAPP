//
//  SelahView.swift
//  AMENAPP
//
//  Created by Steph on 3/3/26.
//
//  "Selah" — a Hebrew pause marker in Scripture. This reading view
//  turns a long Berean AI response into a focused, distraction-free
//  editorial reading experience.

import SwiftUI
import FirebaseAuth

// MARK: - Reading Format

enum SelahFormat: String, CaseIterable, Identifiable {
    case tldr     = "TL;DR"
    case bullets  = "Bullets"
    case outline  = "Outline"
    case essay    = "Essay"
    case steps    = "Steps"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tldr:    return "bolt.fill"
        case .bullets: return "list.bullet"
        case .outline: return "list.number"
        case .essay:   return "doc.text"
        case .steps:   return "arrow.right.circle"
        }
    }
}

// MARK: - Content Section Model

struct SelahSection: Identifiable {
    let id = UUID()
    let kind: SectionKind
    var body: String
    var keyPhrases: [String]
    var references: [String]

    enum SectionKind: String {
        case summary      = "Summary"
        case keyPoints    = "Key Points"
        case context      = "Context"
        case evidence     = "Scripture Support"
        case application  = "Apply It"
        case caveats      = "Worth Noting"
        case nextSteps    = "Explore Further"
    }
}

// MARK: - Response Parser

private struct SelahParser {

    /// Splits a raw AI response into semantic sections based on keywords and structure.
    static func parse(response: String, format: SelahFormat) -> [SelahSection] {
        var sections: [SelahSection] = []
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build a compact summary from the first 200 chars of the response
        let summaryText = extractSummary(from: text)
        sections.append(SelahSection(
            kind: .summary,
            body: summaryText,
            keyPhrases: extractKeyPhrases(from: summaryText),
            references: []
        ))

        // Extract scripture references throughout
        let allRefs = extractScriptureRefs(from: text)

        // Remaining body (after first paragraph)
        let body = extractBody(from: text)

        switch format {
        case .tldr:
            // Short — just summary + key takeaways
            let takeaways = extractTakeaways(from: text)
            if !takeaways.isEmpty {
                sections.append(SelahSection(
                    kind: .keyPoints,
                    body: takeaways,
                    keyPhrases: extractKeyPhrases(from: takeaways),
                    references: allRefs
                ))
            }

        case .bullets:
            let points = extractBulletPoints(from: text)
            sections.append(SelahSection(
                kind: .keyPoints,
                body: points,
                keyPhrases: extractKeyPhrases(from: points),
                references: allRefs
            ))
            if !allRefs.isEmpty {
                sections.append(SelahSection(
                    kind: .evidence,
                    body: allRefs.joined(separator: "\n"),
                    keyPhrases: [],
                    references: allRefs
                ))
            }

        case .outline:
            sections.append(SelahSection(
                kind: .context,
                body: body,
                keyPhrases: extractKeyPhrases(from: body),
                references: allRefs
            ))
            if !allRefs.isEmpty {
                sections.append(SelahSection(
                    kind: .evidence,
                    body: allRefs.joined(separator: "\n"),
                    keyPhrases: [],
                    references: allRefs
                ))
            }
            let application = extractApplication(from: text)
            if !application.isEmpty {
                sections.append(SelahSection(
                    kind: .application,
                    body: application,
                    keyPhrases: extractKeyPhrases(from: application),
                    references: []
                ))
            }

        case .essay:
            sections.append(SelahSection(
                kind: .context,
                body: body,
                keyPhrases: extractKeyPhrases(from: body),
                references: allRefs
            ))
            let application = extractApplication(from: text)
            if !application.isEmpty {
                sections.append(SelahSection(
                    kind: .application,
                    body: application,
                    keyPhrases: extractKeyPhrases(from: application),
                    references: []
                ))
            }
            let caveats = extractCaveats(from: text)
            if !caveats.isEmpty {
                sections.append(SelahSection(
                    kind: .caveats,
                    body: caveats,
                    keyPhrases: [],
                    references: []
                ))
            }
            sections.append(SelahSection(
                kind: .nextSteps,
                body: suggestNextSteps(from: text),
                keyPhrases: [],
                references: []
            ))

        case .steps:
            let steps = extractSteps(from: text)
            sections.append(SelahSection(
                kind: .keyPoints,
                body: steps,
                keyPhrases: extractKeyPhrases(from: steps),
                references: allRefs
            ))
            let application = extractApplication(from: text)
            if !application.isEmpty {
                sections.append(SelahSection(
                    kind: .application,
                    body: application,
                    keyPhrases: extractKeyPhrases(from: application),
                    references: []
                ))
            }
        }

        return sections.filter { !$0.body.isEmpty }
    }

    // MARK: Extraction helpers

    private static func extractSummary(from text: String) -> String {
        // First sentence or up to 220 characters
        let sentences = text.components(separatedBy: ". ")
        if let first = sentences.first, first.count > 40 {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasSuffix(".") ? trimmed : trimmed + "."
        }
        let end = text.index(text.startIndex, offsetBy: min(220, text.count))
        let snippet = String(text[..<end])
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines) + (text.count > 220 ? "…" : "")
    }

    private static func extractBody(from text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        let body = paragraphs.dropFirst().joined(separator: "\n\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractKeyPhrases(from text: String) -> [String] {
        // Identify phrases that appear significant: Title Case words, quoted text, all-caps terms
        var phrases: [String] = []
        // Quoted phrases
        let quotePattern = try? NSRegularExpression(pattern: "\"([^\"]{5,60})\"")
        let range = NSRange(text.startIndex..., in: text)
        quotePattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match = match, let range = Range(match.range(at: 1), in: text) {
                phrases.append(String(text[range]))
            }
        }
        // Pick a few notable words if we have no quotes (3-word max phrases)
        if phrases.isEmpty {
            let words = text.split(separator: " ").map(String.init)
            let important = words.filter { $0.count > 6 && $0.first?.isUppercase == true }
            phrases = Array(important.prefix(3))
        }
        return Array(Set(phrases)).prefix(4).map { $0 }
    }

    private static func extractScriptureRefs(from text: String) -> [String] {
        // Match patterns like "John 3:16", "Genesis 1:1-3", "Psalm 23", "Hebrews 11:1"
        let pattern = try? NSRegularExpression(
            pattern: #"(?:Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalm|Psalms|Proverbs|Ecclesiastes|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|Jude|Revelation)\s+\d+(?::\d+(?:-\d+)?)?(?:\s*,\s*\d+(?::\d+)?)*"#
        )
        var refs: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        pattern?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let match = match, let range = Range(match.range, in: text) {
                let ref = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !refs.contains(ref) { refs.append(ref) }
            }
        }
        return refs
    }

    private static func extractBulletPoints(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let bullets = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("•") || t.hasPrefix("-") || t.hasPrefix("*") || t.hasPrefix("–")
        }
        if bullets.isEmpty { return text }
        return bullets.joined(separator: "\n")
    }

    private static func extractTakeaways(from text: String) -> String {
        let lower = text.lowercased()
        if let range = lower.range(of: "key takeaway") ?? lower.range(of: "in summary") ?? lower.range(of: "to summarize") {
            let snippet = String(text[range.upperBound...].prefix(400))
            return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: extract first 3 sentences
        let sentences = text.components(separatedBy: ". ")
        return sentences.prefix(3).joined(separator: ". ") + "."
    }

    private static func extractApplication(from text: String) -> String {
        let lower = text.lowercased()
        let markers = ["apply", "practical", "in your life", "daily life", "how to", "action step", "this means", "therefore"]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let start = text.index(range.lowerBound, offsetBy: 0)
                let snippet = String(text[start...].prefix(500))
                return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func extractCaveats(from text: String) -> String {
        let lower = text.lowercased()
        let markers = ["however", "note that", "it's worth", "keep in mind", "caveat", "important to note", "although"]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let start = text.index(range.lowerBound, offsetBy: 0)
                let snippet = String(text[start...].prefix(400))
                return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func extractSteps(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let numbered = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.first?.isNumber == true && (t.dropFirst().hasPrefix(".") || t.dropFirst().hasPrefix(")"))
        }
        if numbered.isEmpty { return extractTakeaways(from: text) }
        return numbered.joined(separator: "\n")
    }

    private static func suggestNextSteps(from text: String) -> String {
        let refs = extractScriptureRefs(from: text)
        var suggestions: [String] = []
        if !refs.isEmpty {
            suggestions.append("Read " + (refs.first ?? "") + " in full context")
        }
        suggestions.append("Ask Berean to go deeper on any section")
        suggestions.append("Save these insights to Church Notes")
        return suggestions.joined(separator: "\n")
    }
}

// MARK: - Selah View (full-screen reading + workspace)

struct SelahView: View {
    let message: BereanMessage
    let originalQuery: String
    var onContinueInChat: (() -> Void)? = nil
    var onAskFollowUp: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFormat: SelahFormat = .essay
    @Namespace private var formatNamespace
    @Namespace private var tabNamespace
    @State private var sections: [SelahSection] = []
    @State private var expandedSections: Set<UUID> = []
    @State private var showHighlights = true
    @State private var showSaveConfirmation = false
    @State private var isSavingNote = false
    @State private var isGenerating = false
    @State private var scrollOffset: CGFloat = 0

    // Tab system
    @State private var selectedTab: SelahTab = .read

    // Actions sheet
    @State private var showActionsSheet = false

    // Verse explorer
    @State private var selectedVerseRef: String?
    @State private var showVerseExplorer = false

    // Save / action toast message
    @State private var toastMessage = ""
    @State private var toastIsSuccess = true
    @State private var toastDismissTask: Task<Void, Never>?

    @StateObject private var churchNotesService = ChurchNotesService()
    @ObservedObject private var selahService = SelahService.shared
    @ObservedObject private var verseService = DailyVerseGenkitService.shared

    // Scripture reader sheet — opened from SelahVOTDCard "Read Chapter" pill
    @State private var showScriptureReader = false
    @State private var scriptureReaderRef: SelahScriptureReference?
    private let scriptureProvider: any SelahBibleTranslationProvider = SelahLocalPublicDomainBibleProvider()
    @StateObject private var scripturePrefs = SelahScriptureReaderPreferencesStore()

    enum SelahTab: String, CaseIterable, Identifiable {
        case read       = "Read"
        case ask        = "Ask Selah"
        case trails     = "Trails"
        case explore    = "Explore"
        case transform  = "Transform"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .read:      return "doc.text"
            case .ask:       return "brain.head.profile"
            case .trails:    return "point.3.connected.trianglepath.dotted"
            case .explore:   return "book.fill"
            case .transform: return "wand.and.stars"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            (colorScheme == .dark ? Color(.systemBackground) : Color(red: 0.97, green: 0.97, blue: 0.97))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with glass treatment
                topBar

                // Tab selector
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Format picker — only in Read tab, and only when there is enough
                // prose for the lenses to differ. On a short daily-verse payload
                // TL;DR / Bullets / Steps all collapse to the same text, so we hide
                // the picker rather than promise five identical formats.
                if selectedTab == .read && contentIsRichEnoughForFormats {
                    formatPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Thin separator
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)

                // Tab content
                tabContent
            }

            // Top-edge blur overlay
            ScrollEdgeTopBlurOverlay(scrollOffset: scrollOffset, panelHeight: 56)
                .ignoresSafeArea(edges: .top)

            // Save confirmation toast
            if showSaveConfirmation {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: toastIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(toastIsSuccess ? .green : .orange)
                        Text(toastMessage.isEmpty ? "Saved to Church Notes" : toastMessage)
                            .font(.systemScaled(14, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .onAppear {
            rebuildSections()
            expandedSections = Set(sections.map { $0.id })
            saveSession()
        }
        .onChange(of: selectedFormat) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                rebuildSections()
                expandedSections = Set(sections.map { $0.id })
            }
        }
        .onDisappear {
            toastDismissTask?.cancel()
            toastDismissTask = nil
        }
        .sheet(isPresented: $showVerseExplorer) {
            if let ref = selectedVerseRef {
                SelahVerseExplorerView(reference: ref) { _ in
                    showVerseExplorer = false
                    selectedTab = .ask
                }
                .presentationDragIndicator(.visible)
            }
        }
        // Scripture reader — opened when user taps "Read Chapter" on SelahVOTDCard
        .sheet(isPresented: $showScriptureReader) {
            if let ref = scriptureReaderRef {
                SelahScriptureReaderView(
                    initialReference: ref,
                    provider: scriptureProvider,
                    preferencesStore: scripturePrefs
                )
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Top Bar (Liquid Glass)

    private var topBar: some View {
        ZStack {
            // Close button — left
            HStack {
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                        Image(systemName: "xmark")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Selah")
                Spacer()
            }

            // Center label
            Text("Selah")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)

            // Right controls
            HStack(spacing: 8) {
                Spacer()

                // Highlights toggle (read tab only)
                if selectedTab == .read {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.8))) {
                            showHighlights.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "highlighter")
                                .font(.systemScaled(13, weight: .medium))
                            Text(showHighlights ? "On" : "Off")
                                .font(.systemScaled(12, weight: .medium))
                        }
                        .foregroundStyle(showHighlights ? Color.accentColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(showHighlights ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Key-phrase highlights")
                    .accessibilityValue(showHighlights ? "On" : "Off")
                    .accessibilityHint("Toggles colored highlighting of key phrases in the reading")
                    .transition(.opacity)
                }

                // Workflow button
                StartWorkflowButton(
                    verseReference: message.verseReferences.first,
                    onCreated: {
                        toastMessage = "Journey started"
                        showToast(success: true)
                        selectedTab = .read
                    },
                    onFailed: { message in
                        toastMessage = message.isEmpty ? "Could not start journey" : message
                        showToast(success: false)
                    }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(SelahTab.allCases) { tab in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78))) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.systemScaled(11, weight: selectedTab == tab ? .semibold : .regular))
                                if selectedTab == tab {
                                    Text(tab.rawValue)
                                        .font(.systemScaled(12, weight: .semibold))
                                        .lineLimit(1)
                                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                }
                            }
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, selectedTab == tab ? 14 : 12)
                            .padding(.vertical, 7)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(.regularMaterial)
                                        .overlay(
                                            Capsule().strokeBorder(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.80), Color.white.opacity(0.20)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                        )
                                        .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
                                        .matchedGeometryEffect(id: "selahTabLens", in: tabNamespace)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                    .id(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(height: 42)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
                .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .read:
            readTabContent
        case .ask:
            AskSelahView(
                initialQuery: originalQuery == "Daily Verse" ? "Help me reflect on \(message.verseReferences.first ?? "today's verse")" : originalQuery,
                initialVerses: message.verseReferences
            )
        case .trails:
            ThoughtTrailsView()
        case .explore:
            if let firstRef = message.verseReferences.first {
                SelahVerseExplorerView(reference: firstRef) { ref in
                    selectedTab = .ask
                }
            } else {
                exploreEmptyState
            }
        case .transform:
            ScrollView {
                SelahTransformationCardsView(
                    content: message.content,
                    scriptureRefs: message.verseReferences,
                    onSave: { output in
                        saveTransformationToNotes(output)
                    }
                )
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
    }

    private var exploreEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.fill")
                .font(.systemScaled(40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No verses to explore")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This reflection doesn't contain specific\nverse references to explore.")
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
    }

    // MARK: - Read Tab Content

    private var readTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Zero-height scroll offset reader
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geo.frame(in: .named("selahReadScroll")).minY
                    )
                }
                .frame(height: 0)

                // Query title
                queryHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                // Verse of the Day + personalized reflection — only on the true
                // Daily Verse entry. The service caches today's verse globally, so
                // without this gate these cards would also appear on unrelated
                // Ask-Selah / church-note study answers.
                if isDailyVerseEntry, let verse = verseService.todayVerse {
                    SelahVOTDCard(
                        verseRef: verse.reference,
                        verseText: verse.text,
                        heroImageURL: nil,
                        onReadChapter: { ref in
                            if let parsed = SelahScriptureReferenceParser.parse(ref) {
                                scriptureReaderRef = parsed
                                showScriptureReader = true
                            } else if !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                selectedVerseRef = ref
                                showVerseExplorer = true
                            } else {
                                toastMessage = "Could not open chapter"
                                showToast(success: false)
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // Personalized reflection — surfaces the reflection, application,
                    // prayer and related verses the service already generated for this
                    // user today, instead of re-printing the verse text.
                    SelahDailyReflectionCard(verse: verse) { ref in
                        selectedVerseRef = ref
                        showVerseExplorer = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                // Active workflow (if any)
                SelahActiveWorkflowsView { action in
                    handleWorkflowAction(action)
                }
                .padding(.bottom, 12)

                // Generating indicator
                if isGenerating {
                    SelahThinkingDots()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                // Sections (Liquid Glass cards)
                ForEach(sections) { section in
                    SelahSectionView(
                        section: section,
                        isExpanded: expandedSections.contains(section.id),
                        showHighlights: showHighlights,
                        onToggle: {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78))) {
                                if expandedSections.contains(section.id) {
                                    expandedSections.remove(section.id)
                                } else {
                                    expandedSections.insert(section.id)
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                // Scripture reference chips (tappable → Explore tab)
                if !message.verseReferences.isEmpty {
                    scriptureChipsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                // Actions bar
                actionsBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
            }
        }
        .coordinateSpace(name: "selahReadScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            if abs(value - scrollOffset) >= 1 {
                scrollOffset = value
            }
        }
    }

    // MARK: - Scripture Chips

    private var scriptureChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCRIPTURE")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(message.verseReferences, id: \.self) { ref in
                        Button {
                            selectedVerseRef = ref
                            showVerseExplorer = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book.fill")
                                    .font(.systemScaled(10))
                                Text(ref)
                                    .font(.systemScaled(12, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(SelahFormat.allCases) { format in
                        SelahFormatSegment(
                            format: format,
                            isSelected: selectedFormat == format,
                            namespace: formatNamespace
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78))) {
                                selectedFormat = format
                            }
                        }
                        .id(format)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
            }
            .frame(height: 46)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .clipShape(Capsule())
            .onChange(of: selectedFormat) { _, newVal in
                withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.78))) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
    }

    // MARK: - Query Header

    private var queryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELAH")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.accentColor.opacity(0.75))

            Text(originalQuery.isEmpty ? "Scripture Study" : originalQuery)
                .font(.systemScaled(26, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions Bar

    private var actionsBar: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                actionButton(icon: "doc.on.doc", label: "Copy") {
                    UIPasteboard.general.string = message.content
                    toastMessage = "Copied"
                    showToast(success: true)
                }
                actionButton(icon: "square.and.arrow.up", label: "Share") {
                    showActionsSheet = true
                }
                actionButton(icon: "note.text.badge.plus", label: "Notes") {
                    saveToChurchNotes()
                }
                actionButton(icon: "bubble.left.and.bubble.right", label: onContinueInChat == nil ? "Ask" : "Chat") {
                    continueOrOpenAsk()
                }
            }
            .padding(.vertical, 4)

            Button {
                askFollowUp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.bubble")
                        .font(.systemScaled(14, weight: .medium))
                    Text("Ask Follow-up")
                        .font(.systemScaled(14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.primary)
                .amenInteractiveGlassEffect(in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showActionsSheet) {
            ShareSheet(items: [message.content])
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .regular))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func continueOrOpenAsk() {
        if let onContinueInChat {
            onContinueInChat()
            dismiss()
            return
        }
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78))) {
            selectedTab = .ask
        }
        toastMessage = "Ask Selah is ready"
        showToast(success: true)
    }

    private func askFollowUp() {
        let prompt = isDailyVerseEntry
            ? "Help me apply \(message.verseReferences.first ?? "today's verse") today"
            : "Tell me more about this"
        if let onAskFollowUp {
            onAskFollowUp(prompt)
            dismiss()
            return
        }
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.78))) {
            selectedTab = .ask
        }
        toastMessage = "Follow-up ready in Ask Selah"
        showToast(success: true)
    }

    // MARK: - Logic

    /// True only when this Selah was opened from the Daily Verse entry point.
    /// `AIDailyVerseView` constructs `SelahView(..., originalQuery: "Daily Verse")`;
    /// every other entry (Ask Selah, church-note study, post attachments) passes a
    /// different query. Kept intrinsic so the gate lives entirely in this file.
    /// Post-v1 hardening: promote to an explicit `init` flag set at the call site
    /// so the behavior no longer depends on a literal query string.
    private var isDailyVerseEntry: Bool {
        originalQuery == "Daily Verse"
    }

    /// The reading-format lenses only diverge when there is enough prose to slice.
    /// Below this threshold (≈ a verse plus a sentence) every format renders the
    /// same text, so the picker is hidden.
    private var contentIsRichEnoughForFormats: Bool {
        message.content
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .count >= 60
    }

    private func rebuildSections() {
        let parsed = SelahParser.parse(response: message.content, format: selectedFormat)
        sections = Self.pruneRedundant(parsed, against: verseService.todayVerse?.text)
    }

    /// Removes sections that merely echo the daily verse, repeat an earlier
    /// section, or contain nothing but a scripture attribution line. Heuristic
    /// parsing on a short verse payload otherwise produces several near-identical
    /// cards (e.g. SUMMARY and CONTEXT both showing the same verse text, and a
    /// CONTEXT card whose only body is "— Romans 8:28").
    private static func pruneRedundant(_ sections: [SelahSection], against verseText: String?) -> [SelahSection] {
        func normalize(_ s: String) -> String {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let verseKey = verseText.map(normalize)
        var seen: Set<String> = []
        var result: [SelahSection] = []

        for section in sections {
            let trimmed = section.body.trimmingCharacters(in: .whitespacesAndNewlines)

            // Drop attribution-only bodies, e.g. "— Romans 8:28".
            let withoutDash = String(trimmed.drop { "—–-".contains($0) || $0 == " " })
                .trimmingCharacters(in: .whitespaces)
            if section.references.contains(withoutDash) { continue }

            let key = normalize(trimmed)
            if key.isEmpty { continue }

            // Drop bodies that are wholly a fragment of the daily verse text.
            if let verseKey, !verseKey.isEmpty, key.count > 12,
               key == verseKey || verseKey.contains(key) {
                continue
            }

            // Drop exact repeats of an earlier section.
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(section)
        }
        return result
    }

    private func saveSession() {
        Task {
            let refs = SelahParser.parse(response: message.content, format: .outline)
                .flatMap { $0.references }
            let themes = selahService.detectThemes(in: message.content)
            _ = try? await selahService.saveSession(
                title: originalQuery.isEmpty ? "Scripture Study" : String(originalQuery.prefix(60)),
                query: originalQuery,
                responsePreview: message.content,
                format: selectedFormat,
                scriptureRefs: refs,
                tags: themes
            )
        }
    }

    private func saveToChurchNotes() {
        guard !isSavingNote else { return }
        isSavingNote = true

        let title = originalQuery.isEmpty ? "Berean Study" : String(originalQuery.prefix(60))
        let content = message.content
        let refs = SelahParser.parse(response: content, format: .outline)
            .flatMap { $0.references }
        let scripture = refs.first

        let note = ChurchNote(
            userId: Auth.auth().currentUser?.uid ?? "",
            title: title,
            sermonTitle: "Berean AI · Selah",
            churchName: nil,
            pastor: nil,
            date: Date(),
            content: content,
            scripture: scripture,
            keyPoints: sections.filter { $0.kind == .keyPoints }.map { $0.body },
            tags: ["Berean", "AI Study"],
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date(),
            permission: .privateNote
        )

        Task {
            do {
                try await churchNotesService.createNote(note)
                await MainActor.run {
                    isSavingNote = false
                    toastMessage = "Saved to Church Notes"
                    showToast(success: true)
                }
            } catch {
                await MainActor.run {
                    isSavingNote = false
                    toastMessage = error.localizedDescription.isEmpty ? "Could not save note" : error.localizedDescription
                    showToast(success: false)
                }
            }
        }
    }

    private func saveTransformationToNotes(_ output: SelahTransformationOutput) {
        let note = ChurchNote(
            userId: Auth.auth().currentUser?.uid ?? "",
            title: "\(output.type.rawValue): \(originalQuery.prefix(40))",
            sermonTitle: "Selah · \(output.type.rawValue)",
            churchName: nil,
            pastor: nil,
            date: Date(),
            content: output.content,
            scripture: output.scriptureRefs.first,
            keyPoints: [],
            tags: ["Selah", output.type.rawValue],
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date(),
            permission: .privateNote
        )

        Task {
            do {
                try await churchNotesService.createNote(note)
                await MainActor.run {
                    toastMessage = "\(output.type.rawValue) saved to Church Notes"
                    showToast(success: true)
                }
            } catch {
                await MainActor.run {
                    toastMessage = error.localizedDescription.isEmpty ? "Could not save transformation" : error.localizedDescription
                    showToast(success: false)
                }
            }
        }
    }

    private func showToast(success: Bool = true) {
        toastDismissTask?.cancel()
        toastIsSuccess = success
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
            showSaveConfirmation = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showSaveConfirmation = false
            }
            toastDismissTask = nil
        }
    }

    private func handleWorkflowAction(_ action: WorkflowAction) {
        switch action {
        case .openVerse(let ref):
            selectedVerseRef = ref
            showVerseExplorer = true
        case .startSelah:
            selectedTab = .ask
        case .createPrayer:
            // Would deep-link to prayer creation — for now dismiss and let caller handle
            dismiss()
        case .openJournal:
            saveToChurchNotes()
        case .createTestimony:
            dismiss()
        case .shareToOpenTable:
            dismiss()
        }
    }
}

// MARK: - Daily Reflection Card (personalized)

/// Surfaces the personalization that `DailyVerseGenkitService` already computes
/// for the Verse of the Day — the "why this verse", reflection, application,
/// prayer prompt, and related verses — none of which the heuristic section
/// parser ever sees. Formation-first: leads with meaning, not metrics.
private struct SelahDailyReflectionCard: View {
    let verse: PersonalizedDailyVerse
    let onOpenVerse: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            badgeRow

            if let why = whyThisVerse {
                Label(why, systemImage: "sparkles")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !verse.reflection.isEmpty {
                block(title: "REFLECTION", body: verse.reflection)
            }
            if !verse.actionPrompt.isEmpty {
                block(title: "APPLY IT", body: verse.actionPrompt)
            }
            if !verse.prayerPrompt.isEmpty {
                block(title: "PRAYER", body: verse.prayerPrompt, italic: true)
            }
            if !verse.relatedVerses.isEmpty {
                relatedVersesRow
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
        )
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 8) {
            if verse.isPersonalizedToUser {
                badge(text: "Personalized for you", icon: "sparkles", tint: Color.accentColor)
            } else if verse.isFromAI {
                badge(text: "AI reflection", icon: "wand.and.stars", tint: .secondary)
            }
            if !verse.theme.isEmpty {
                Text(verse.theme.uppercased())
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func badge(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.systemScaled(10, weight: .semibold))
            Text(text).font(.systemScaled(11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func block(title: String, body: String, italic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text(body)
                .font(.systemScaled(15))
                .italic(italic)
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var relatedVersesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RELATED")
                .font(.systemScaled(10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(verse.relatedVerses, id: \.self) { ref in
                        Button { onOpenVerse(ref) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book.fill").font(.systemScaled(10))
                                Text(ref).font(.systemScaled(12, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(ref)")
                    }
                }
            }
        }
    }

    /// An honest, gentle line explaining why this verse surfaced — shown only when
    /// the Cloud Function confirmed it used the user's own context.
    private var whyThisVerse: String? {
        guard verse.isPersonalizedToUser, let ctx = verse.personalizedFor else { return nil }
        if let topic = ctx.recentPrayerTopics.first(where: { !$0.isEmpty }) {
            return "Because you've been praying about \(topic.lowercased())."
        }
        if let challenge = ctx.currentChallenges.first(where: { !$0.isEmpty }) {
            return "Chosen as you navigate \(challenge.lowercased())."
        }
        if let interest = ctx.interests.first(where: { !$0.isEmpty }) {
            return "Chosen for your focus on \(interest.lowercased())."
        }
        return nil
    }
}

// MARK: - Format Segment (pill bar item)

private struct SelahFormatSegment: View {
    let format: SelahFormat
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.80), Color.white.opacity(0.20)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        )
                        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
                        .matchedGeometryEffect(id: "selahFormatLens", in: namespace)
                }

                HStack(spacing: 5) {
                    Image(systemName: format.icon)
                        .font(.systemScaled(12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if isSelected {
                        Text(format.rawValue)
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .padding(.horizontal, isSelected ? 14 : 12)
                .padding(.vertical, 7)
            }
            .frame(minHeight: 36)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(format.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(Motion.adaptive(.spring(response: 0.18, dampingFraction: 0.7))) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) { isPressed = false }
                }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }
}

// MARK: - Section View (expandable card)

struct SelahSectionView: View {
    let section: SelahSection
    let isExpanded: Bool
    let showHighlights: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Text(section.kind.rawValue.uppercased())
                        .font(.systemScaled(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.kind.rawValue), \(isExpanded ? "expanded" : "collapsed")")

            // Section body
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if section.kind == .keyPoints || section.kind == .nextSteps {
                        pointsBody
                    } else {
                        mainBody
                    }

                    // Scripture references
                    if !section.references.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(section.references, id: \.self) { ref in
                                    Text(ref)
                                        .font(.systemScaled(11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.50), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
                .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
        )
    }

    @ViewBuilder
    private var mainBody: some View {
        if showHighlights && !section.keyPhrases.isEmpty {
            HighlightedTextView(
                text: section.body,
                highlights: section.keyPhrases
            )
        } else {
            Text(section.body)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var pointsBody: some View {
        let lines = section.body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let cleanLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-*–").union(.whitespaces))
                let isNumbered = cleanLine.first?.isNumber == true

                HStack(alignment: .top, spacing: 10) {
                    if isNumbered {
                        Text(String(index + 1))
                            .font(.systemScaled(11, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 20, height: 20)
                            .amenRegularGlassEffect(in: Circle())
                            .padding(.top, 1)
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.30))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                    }
                    Text(isNumbered ? cleanLine.drop(while: { $0.isNumber || $0 == "." || $0 == ")" || $0 == " " }).description : cleanLine)
                        .font(.systemScaled(15))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Highlighted Text

struct HighlightedTextView: View {
    let text: String
    let highlights: [String]

    var body: some View {
        buildAttributed()
            .font(.systemScaled(15))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildAttributed() -> Text {
        var result = AttributedString(text)

        for phrase in highlights {
            var searchStart = result.startIndex
            while searchStart < result.endIndex {
                let searchRange = searchStart..<result.endIndex
                guard let foundRange = result[searchRange].range(of: phrase, options: .caseInsensitive) else {
                    break
                }
                result[foundRange].backgroundColor = Color.yellow.opacity(0.35)
                // Advance past this match
                let after = foundRange.upperBound
                if after >= result.endIndex { break }
                searchStart = after
            }
        }
        return Text(result)
    }
}

// MARK: - 3-dot Thinking Indicator

struct SelahThinkingDots: View {
    @State private var dot1Up = false
    @State private var dot2Up = false
    @State private var dot3Up = false

    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 7
    private let bounce: CGFloat = 10
    private let dur: Double = 0.44

    var body: some View {
        HStack(spacing: spacing) {
            dot(isUp: dot1Up)
            dot(isUp: dot2Up)
            dot(isUp: dot3Up)
        }
        .onAppear { start() }
    }

    private func dot(isUp: Bool) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.55))
            .frame(width: dotSize, height: dotSize)
            .offset(y: isUp ? -bounce : 0)
            .animation(.easeInOut(duration: dur).repeatForever(autoreverses: true), value: isUp)
    }

    private func start() {
        let stagger = dur * 0.5
        withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true)) { dot1Up = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger) {
            withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true)) { dot2Up = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + stagger * 2) {
            withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true)) { dot3Up = true }
        }
    }
}

// MARK: - Preview

#Preview {
    SelahView(
        message: BereanMessage(
            content: """
            Faith, according to Hebrews 11:1, is the substance of things hoped for, the evidence of things not seen. This foundational definition from Scripture reveals that faith is not mere optimism or wishful thinking — it is a substantive conviction, a confident assurance in what God has promised.

            The chapter goes on to list the great "hall of faith": Abel, Enoch, Noah, Abraham, Sarah, Isaac, Jacob, Joseph, Moses, Rahab, and many others. Each of these individuals acted on what they could not see, trusting in the character and promises of God.

            Key insight: Faith is not the absence of doubt, but action taken despite it. Abraham "went out, not knowing where he was going" (Hebrews 11:8). He didn't have a map — he had a promise.

            How to apply this today:
            1. Identify one area where you're waiting on God
            2. Take a concrete step of obedience, even without full clarity
            3. Record what you're trusting God for — then watch for His faithfulness

            Worth noting: Faith must be grounded in the object of faith — God Himself — not the feeling of faith. You can have little faith and still move mountains, as long as that faith is in the right Person (Matthew 17:20).
            """,
            role: .assistant,
            timestamp: Date(),
            verseReferences: ["Hebrews 11:1", "Hebrews 11:8", "Matthew 17:20"]
        ),
        originalQuery: "What is faith according to the Bible?"
    )
}
