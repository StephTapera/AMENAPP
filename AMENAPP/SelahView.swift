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

// MARK: - Selah View (full-screen reading mode)

struct SelahView: View {
    let message: BereanMessage
    let originalQuery: String
    var onContinueInChat: (() -> Void)? = nil
    var onAskFollowUp: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: SelahFormat = .essay
    @Namespace private var formatNamespace
    @State private var sections: [SelahSection] = []
    @State private var expandedSections: Set<UUID> = []
    @State private var showHighlights = true
    @State private var showSaveConfirmation = false
    @State private var isSavingNote = false
    @State private var isGenerating = false

    // Actions sheet
    @State private var showActionsSheet = false

    @StateObject private var churchNotesService = ChurchNotesService()

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color(red: 0.98, green: 0.98, blue: 0.98)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: close + title + highlights toggle
                topBar

                // Format picker pills
                formatPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.top, 8)

                // Reading content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Query title
                        queryHeader
                            .padding(.horizontal, 24)
                            .padding(.top, 28)
                            .padding(.bottom, 20)

                        // Generating indicator
                        if isGenerating {
                            SelahThinkingDots()
                                .padding(.horizontal, 24)
                                .padding(.bottom, 16)
                        }

                        // Sections
                        ForEach(sections) { section in
                            SelahSectionView(
                                section: section,
                                isExpanded: expandedSections.contains(section.id),
                                showHighlights: showHighlights,
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
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

                        // Actions bar
                        actionsBar
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 48)
                    }
                }
            }

            // Save confirmation toast
            if showSaveConfirmation {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved to Church Notes")
                            .font(.system(size: 14, weight: .semibold))
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
            // All sections start expanded on first load
            expandedSections = Set(sections.map { $0.id })
        }
        .onChange(of: selectedFormat) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                rebuildSections()
                expandedSections = Set(sections.map { $0.id })
            }
        }
    }

    // MARK: - Top Bar

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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }

            // Center label
            Text("Selah")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            // Highlights toggle — right
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showHighlights.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showHighlights ? "highlighter" : "highlighter")
                            .font(.system(size: 13, weight: .medium))
                        Text(showHighlights ? "On" : "Off")
                            .font(.system(size: 12, weight: .medium))
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
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
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
    }

    // MARK: - Query Header

    private var queryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEREAN")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.accentColor.opacity(0.75))

            Text(originalQuery.isEmpty ? "Scripture Study" : originalQuery)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.system(size: 12))
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
                // Copy
                actionButton(icon: "doc.on.doc", label: "Copy") {
                    UIPasteboard.general.string = message.content
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                // Share
                actionButton(icon: "square.and.arrow.up", label: "Share") {
                    showActionsSheet = true
                }
                // Save
                actionButton(icon: "note.text.badge.plus", label: "Church Notes") {
                    saveToChurchNotes()
                }
                // Continue
                actionButton(icon: "bubble.left.and.bubble.right", label: "Chat") {
                    onContinueInChat?()
                    dismiss()
                }
            }
            .padding(.vertical, 4)

            // Ask Follow-up
            Button {
                onAskFollowUp?("Tell me more about this")
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 14, weight: .medium))
                    Text("Ask Follow-up")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
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
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func rebuildSections() {
        sections = SelahParser.parse(response: message.content, format: selectedFormat)
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSaveConfirmation = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            showSaveConfirmation = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingNote = false
                }
            }
        }
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
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if isSelected {
                        Text(format.rawValue)
                            .font(.system(size: 12, weight: .semibold))
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
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isPressed = false }
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
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                                        .font(.system(size: 11, weight: .semibold))
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 0)
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
                .font(.system(size: 15))
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
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor, in: Circle())
                            .padding(.top, 1)
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.30))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                    }
                    Text(isNumbered ? cleanLine.drop(while: { $0.isNumber || $0 == "." || $0 == ")" || $0 == " " }).description : cleanLine)
                        .font(.system(size: 15))
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
            .font(.system(size: 15))
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
