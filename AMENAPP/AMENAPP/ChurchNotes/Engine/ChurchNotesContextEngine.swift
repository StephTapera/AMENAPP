import Foundation

// Local, on-device context analysis engine for Church Notes.
// Privacy-first: no raw note content leaves the device without explicit user action.
// Extends the ChurchNotesIntelligenceService pattern with context-layer outputs.
@MainActor
final class ChurchNotesContextEngine {

    static let shared = ChurchNotesContextEngine()
    private init() {}

    // MARK: - Scripture Detection

    // Matches references like "John 3:16", "1 Corinthians 13:4-7", "Genesis 1:1"
    private let scripturePattern = #/(?:(?:1|2|3)\s)?[A-Z][a-z]+(?:\s[A-Z][a-z]+)?\s\d+:\d+(?:-\d+)?/#

    func detectScriptureReferences(in text: String) -> [CNRelatedScripture] {
        let matches = text.matches(of: scripturePattern)
        var seen = Set<String>()
        return matches.compactMap { match in
            let ref = String(text[match.range])
            guard seen.insert(ref).inserted else { return nil }
            return CNRelatedScripture(
                id: UUID().uuidString,
                reference: ref,
                text: nil,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .confirmed,
                    whySuggested: "Referenced directly in your note text"
                )
            )
        }
    }

    // MARK: - Theme Detection

    private let themeKeywords: [String: [String]] = [
        "Faith & Trust":         ["trust", "faith", "believe", "confident", "rely"],
        "Surrender":             ["surrender", "let go", "yield", "give up", "release control"],
        "Obedience":             ["obey", "obedience", "follow", "step out", "comply"],
        "Forgiveness":           ["forgive", "mercy", "grace", "pardon", "unforgiveness"],
        "Identity in Christ":    ["identity", "who I am", "beloved", "child of God", "worth"],
        "Prayer":                ["pray", "prayer", "intercede", "petition", "seek God"],
        "Hope":                  ["hope", "promise", "waiting", "anticipate", "future"],
        "Purpose & Calling":     ["calling", "purpose", "mission", "vocation", "sent"],
        "Community & Body":      ["together", "church", "body", "fellowship", "one another"],
        "Humility":              ["humble", "humility", "servant", "meek", "not my own"],
        "Grief & Lament":        ["grief", "mourn", "lament", "sorrow", "loss"],
        "Gratitude":             ["grateful", "thankful", "praise", "bless", "appreciate"],
        "Fear & Anxiety":        ["fear", "afraid", "anxious", "worry", "scared"],
        "Leadership":            ["lead", "shepherd", "steward", "guide", "oversee"],
        "God's Word":            ["scripture", "word of God", "passage", "verse", "bible"]
    ]

    func detectThemes(in text: String, noteHistory: [String] = []) -> [CNDetectedTheme] {
        let lowered = text.lowercased()
        var themes: [CNDetectedTheme] = []

        for (theme, keywords) in themeKeywords {
            let hits = keywords.filter { lowered.contains($0) }
            guard !hits.isEmpty else { continue }

            let historyCount = noteHistory.filter { note in
                keywords.contains(where: { note.lowercased().contains($0) })
            }.count

            themes.append(CNDetectedTheme(
                id: UUID().uuidString,
                theme: theme,
                occurrenceCount: historyCount + 1,
                isRecurring: historyCount >= 2,
                exampleQuotes: extractQuotes(matching: hits, from: text),
                provenance: CNProvenanceLabel(
                    source: historyCount > 0 ? "your note + prior notes" : "your note",
                    confidence: hits.count >= 2 ? .confirmed : .possible,
                    whySuggested: "Keywords found: \(hits.prefix(3).joined(separator: ", "))"
                )
            ))
        }

        return Array(themes.sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(5))
    }

    // MARK: - Prayer Prompts

    func generatePrayerPrompts(from text: String, themes: [CNDetectedTheme]) -> [CNPrayerPrompt] {
        var prompts: [CNPrayerPrompt] = []
        let lowered = text.lowercased()

        for theme in themes.prefix(3) {
            prompts.append(CNPrayerPrompt(
                id: UUID().uuidString,
                text: "Lord, as I reflect on \(theme.theme.lowercased()), what are you inviting me into?",
                category: .personal,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Based on \"\(theme.theme)\" theme detected in your note"
                )
            ))
        }

        if lowered.contains("struggle") || lowered.contains("difficult") || lowered.contains("hard") {
            prompts.append(CNPrayerPrompt(
                id: UUID().uuidString,
                text: "God, I bring what feels heavy right now — I'm asking you to meet me here.",
                category: .surrender,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Note references difficulty or struggle"
                )
            ))
        }

        if lowered.contains("grateful") || lowered.contains("thankful") || lowered.contains("thank") {
            prompts.append(CNPrayerPrompt(
                id: UUID().uuidString,
                text: "Thank you, Father — for what you've shown me and given me today.",
                category: .thanksgiving,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .confirmed,
                    whySuggested: "Note expresses gratitude"
                )
            ))
        }

        if lowered.contains("others") || lowered.contains("friend") || lowered.contains("family") {
            prompts.append(CNPrayerPrompt(
                id: UUID().uuidString,
                text: "I lift up the people on my heart — may they experience your presence.",
                category: .intercession,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Note mentions others who may need prayer"
                )
            ))
        }

        return prompts
    }

    // MARK: - Reflection Questions

    func generateReflectionQuestions(from text: String, themes: [CNDetectedTheme]) -> [CNReflectionQuestion] {
        var questions: [CNReflectionQuestion] = []

        for theme in themes.prefix(2) {
            questions.append(CNReflectionQuestion(
                id: UUID().uuidString,
                text: "How might the theme of \(theme.theme.lowercased()) connect to something God has been working in your life?",
                isPersonal: true,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Generated from \"\(theme.theme)\" theme"
                )
            ))
        }

        questions.append(CNReflectionQuestion(
            id: UUID().uuidString,
            text: "What from today's message do you most want to carry into your week?",
            isPersonal: true,
            provenance: CNProvenanceLabel(
                source: "system",
                confidence: .confirmed,
                whySuggested: "Standard reflective question for sermon notes"
            )
        ))

        questions.append(CNReflectionQuestion(
            id: UUID().uuidString,
            text: "Is there something here that feels unresolved — something to sit with or pray through before Sunday?",
            isPersonal: true,
            provenance: CNProvenanceLabel(
                source: "system",
                confidence: .confirmed,
                whySuggested: "Invites continued reflection"
            )
        ))

        return questions
    }

    // MARK: - Small Group Questions

    func generateSmallGroupQuestions(from text: String, themes: [CNDetectedTheme]) -> [CNSmallGroupQuestion] {
        var questions: [CNSmallGroupQuestion] = []

        for theme in themes.prefix(2) {
            questions.append(CNSmallGroupQuestion(
                id: UUID().uuidString,
                text: "Where have you recently seen \(theme.theme.lowercased()) at work in your own life?",
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Generated from \"\(theme.theme)\" theme"
                )
            ))
        }

        questions.append(CNSmallGroupQuestion(
            id: UUID().uuidString,
            text: "What one thing from this message challenged or encouraged you most — and why?",
            provenance: CNProvenanceLabel(
                source: "system",
                confidence: .confirmed,
                whySuggested: "Standard small group opening question"
            )
        ))

        questions.append(CNSmallGroupQuestion(
            id: UUID().uuidString,
            text: "Is there something from this message that someone in your group might need to hear or pray through together?",
            provenance: CNProvenanceLabel(
                source: "system",
                confidence: .confirmed,
                whySuggested: "Encourages communal reflection"
            )
        ))

        return questions
    }

    // MARK: - Action Suggestion Extraction

    func extractActionSuggestions(from text: String) -> [CNActionSuggestion] {
        var suggestions: [CNActionSuggestion] = []
        let lowered = text.lowercased()
        var seenIds = Set<String>()

        let commitmentPhrases = ["i will", "i need to", "i should", "commit to", "going to", "plan to", "i want to"]
        for phrase in commitmentPhrases {
            guard lowered.contains(phrase) else { continue }
            if let range = lowered.range(of: phrase) {
                let sentence = extractSentence(containing: range, in: text)
                guard !sentence.isEmpty else { continue }
                let id = UUID().uuidString
                guard seenIds.insert(sentence.prefix(30).lowercased()).inserted else { continue }
                suggestions.append(CNActionSuggestion(
                    id: id,
                    type: .personalAction,
                    text: sentence,
                    sourceQuote: sentence,
                    provenance: CNProvenanceLabel(
                        source: "your note",
                        confidence: .possible,
                        whySuggested: "Contains commitment language: \"\(phrase)\""
                    )
                ))
            }
        }

        if lowered.contains("pray for") || lowered.contains("keep in prayer") {
            suggestions.append(CNActionSuggestion(
                id: UUID().uuidString,
                type: .prayerItem,
                text: "Add a prayer item from this note",
                sourceQuote: nil,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Note contains prayer intentions"
                )
            ))
        }

        return Array(suggestions.prefix(5))
    }

    // MARK: - Smart Recap

    func generateSmartRecap(
        for noteId: String,
        from text: String,
        themes: [CNDetectedTheme],
        scriptures: [CNRelatedScripture]
    ) -> CNSmartRecap {
        let topThemeNames = themes.prefix(3).map { $0.theme }
        let scriptureRefs = scriptures.prefix(3).map { $0.reference }

        let whatStoodOut: String
        if let firstTheme = topThemeNames.first {
            let others = topThemeNames.dropFirst().joined(separator: ", ")
            whatStoodOut = others.isEmpty
                ? "A recurring theme appears to be \(firstTheme.lowercased()). This may connect to something God has been working in your heart."
                : "Your notes touch on \(firstTheme.lowercased())\(others.isEmpty ? "" : ", \(others)"). This may connect to something ongoing in your life."
        } else {
            whatStoodOut = "Here's a brief look at what stood out in your notes today."
        }

        let prayerItems = themes.prefix(3).map { theme in
            "Pray through what \(theme.theme.lowercased()) means for you this week."
        }

        return CNSmartRecap(
            id: UUID().uuidString,
            noteId: noteId,
            whatStoodOut: whatStoodOut,
            prayerItems: Array(prayerItems),
            nextStep: "Revisit one key thought from today before Sunday.",
            relatedScriptures: scriptureRefs,
            relatedNoteIds: [],
            isEdited: false,
            editedText: nil,
            generatedAt: Date(),
            provenance: CNProvenanceLabel(
                source: "your note",
                confidence: .possible,
                whySuggested: "Based on note content — review before saving"
            )
        )
    }

    // MARK: - Smart Capture Classification

    func classifyCapture(extractedText: String, sourceJobId: String) -> CNSmartCaptureResult {
        let lowered = extractedText.lowercased()
        let detectedType: CNSmartCaptureContentType

        if lowered.contains("pray") || lowered.contains("please pray") {
            detectedType = .prayerRequest
        } else if lowered.matches(of: scripturePattern).count > 0 {
            detectedType = .scriptureReference
        } else if lowered.contains("this week") || lowered.contains("action") || lowered.contains("homework") {
            detectedType = .actionItem
        } else if lowered.contains("announce") || lowered.contains("join us") || lowered.contains("event") {
            detectedType = .announcement
        } else if extractedText.hasPrefix("\u{201C}") || extractedText.contains(" — ") {
            detectedType = .quote
        } else {
            detectedType = .unknown
        }

        return CNSmartCaptureResult(
            id: UUID().uuidString,
            sourceJobId: sourceJobId,
            detectedType: detectedType,
            extractedText: extractedText,
            confidence: .possible,
            requiresReview: true,
            reviewState: .pending,
            provenance: CNProvenanceLabel(
                source: "OCR / transcript",
                confidence: .possible,
                whySuggested: "Detected from captured media — please review before saving"
            )
        )
    }

    // MARK: - Full Analysis

    func analyzeForContext(noteId: String, noteText: String, noteHistory: [String] = []) -> CNContextResult {
        let themes = detectThemes(in: noteText, noteHistory: noteHistory)
        let scriptures = detectScriptureReferences(in: noteText)
        let prayerPrompts = generatePrayerPrompts(from: noteText, themes: themes)
        let reflectionQuestions = generateReflectionQuestions(from: noteText, themes: themes)
        let smallGroupQuestions = generateSmallGroupQuestions(from: noteText, themes: themes)
        let actionSuggestions = extractActionSuggestions(from: noteText)

        return CNContextResult(
            noteId: noteId,
            relatedScriptures: scriptures,
            relatedNotes: [],
            detectedThemes: themes,
            prayerPrompts: prayerPrompts,
            reflectionQuestions: reflectionQuestions,
            smallGroupQuestions: smallGroupQuestions,
            actionSuggestions: actionSuggestions,
            smartCaptures: [],
            generatedAt: Date()
        )
    }

    // MARK: - Helpers

    private func extractQuotes(matching keywords: [String], from text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        var quotes: [String] = []
        for sentence in sentences {
            let lowered = sentence.lowercased()
            if keywords.contains(where: { lowered.contains($0) }) {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 10 { quotes.append(String(trimmed.prefix(120))) }
            }
            if quotes.count >= 2 { break }
        }
        return quotes
    }

    private func extractSentence(containing range: Range<String.Index>, in text: String) -> String {
        let lowered = text.lowercased()
        let needle = String(lowered[range])
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for sentence in sentences {
            if sentence.lowercased().contains(needle) {
                return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }
}
