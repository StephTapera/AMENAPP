//
//  ChurchNotesOrganizeService.swift
//  AMENAPP
//
//  AI note cleanup: messy notes + transcript → structured sermon note.
//  Uses ClaudeService for the Berean Organize feature.
//

import Foundation
import SwiftUI
import Combine

// MARK: - OrganizedSermonNote

struct OrganizedSermonNote: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let mainMessage: String
    let keyPoints: [String]
    let scriptures: [String]
    let themes: [String]
    let personalTakeaways: [String]
    let actionSteps: [String]
    let prayerResponse: String
    let questionsToRevisit: [String]
    let suggestedFolderTheme: NoteColorTheme
    let suggestedNoteType: NoteType

    /// Smart file name suggestion (no church/speaker context at struct level)
    var suggestedFileName: String {
        return title
    }
}

// MARK: - ReflectionPromptSet

struct ReflectionPromptSet: Identifiable {
    let id = UUID()
    let prompts: [String]
    let growthLoopSchedule: GrowthLoopSchedule

    struct GrowthLoopSchedule {
        let day1Prompt: String
        let day3Prompt: String
        let day7Prompt: String
    }
}

// MARK: - ChurchNotesOrganizeService

@MainActor
final class ChurchNotesOrganizeService: ObservableObject {
    static let shared = ChurchNotesOrganizeService()

    @Published var isOrganizing: Bool = false
    @Published var lastOrganizedNote: OrganizedSermonNote?
    @Published var lastReflectionPrompts: ReflectionPromptSet?
    @Published var organizationProgress: Double = 0.0

    private init() {}

    // MARK: - Main Organize Flow

    func organizeNote(
        rawContent: String,
        transcript: String?,
        churchName: String?,
        speakerName: String?,
        serviceDate: Date
    ) async throws -> OrganizedSermonNote {
        isOrganizing = true
        organizationProgress = 0.1
        defer {
            isOrganizing = false
            organizationProgress = 0.0
        }

        let prompt = buildOrganizePrompt(
            rawContent: rawContent,
            transcript: transcript,
            churchName: churchName,
            speakerName: speakerName
        )

        organizationProgress = 0.3

        let response = try await ClaudeService.shared.sendMessageSync(
            prompt,
            conversationHistory: [],
            mode: .scholar
        )

        organizationProgress = 0.8

        let organized = parseOrganizedResponse(
            response,
            churchName: churchName,
            speakerName: speakerName,
            date: serviceDate
        )

        organizationProgress = 1.0
        lastOrganizedNote = organized
        return organized
    }

    // MARK: - Reflection Prompts

    func generateReflectionPrompts(for organizedNote: OrganizedSermonNote) async -> ReflectionPromptSet {
        let prompt = """
        Based on this sermon summary, generate exactly 5 short, personal reflection questions \
        that encourage honest self-examination. Also write three growth-loop prompts: \
        one for 24 hours later (DAY1:), one for 3 days later (DAY3:), one for 7 days later (DAY7:).

        Sermon title: \(organizedNote.title)
        Main message: \(organizedNote.mainMessage)
        Themes: \(organizedNote.themes.joined(separator: ", "))
        Personal takeaways: \(organizedNote.personalTakeaways.joined(separator: "; "))

        Format each reflection question on its own line starting with PROMPT:
        Format growth prompts as DAY1: ... / DAY3: ... / DAY7: ...
        """

        do {
            let response = try await ClaudeService.shared.sendMessageSync(
                prompt,
                conversationHistory: [],
                mode: .scholar
            )
            return parseReflectionPrompts(response, for: organizedNote)
        } catch {
            dlog("ChurchNotesOrganizeService generateReflectionPrompts error: \(error)")
            return fallbackReflectionPrompts(for: organizedNote)
        }
    }

    // MARK: - Scripture Detection

    func detectScriptureReferences(in text: String) -> [String] {
        // Pattern covers: "Romans 8:28", "John 3:16-17", "Hebrews 11", "1 Corinthians 13:4"
        let pattern = #"(?:1\s|2\s|3\s)?[A-Z][a-z]+(?:\s[A-Z][a-z]+)?\s\d+(?::\d+(?:-\d+)?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        let bookNames = Set([
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges",
            "Ruth", "Samuel", "Kings", "Chronicles", "Ezra", "Nehemiah", "Esther", "Job",
            "Psalms", "Proverbs", "Ecclesiastes", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
            "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "Corinthians", "Galatians",
            "Ephesians", "Philippians", "Colossians", "Thessalonians", "Timothy", "Titus",
            "Philemon", "Hebrews", "James", "Peter", "Jude", "Revelation"
        ])

        var results: [String] = []
        for match in matches {
            if let range = Range(match.range, in: text) {
                let ref = String(text[range])
                let firstWord = ref.components(separatedBy: .whitespaces).first { !$0.isEmpty && !$0.allSatisfy(\.isNumber) } ?? ""
                if bookNames.contains(firstWord) {
                    results.append(ref)
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }

    // MARK: - Theme Detection

    func detectThemes(in text: String) -> [String] {
        let themeKeywords: [String: [String]] = [
            "faith":      ["faith", "believe", "belief", "trust", "confidence"],
            "obedience":  ["obey", "obedience", "follow", "submit", "surrender"],
            "grace":      ["grace", "mercy", "forgiveness", "forgiven", "unmerited"],
            "prayer":     ["pray", "prayer", "intercession", "petition", "seek"],
            "trust":      ["trust", "rely", "depend", "lean on", "rest in"],
            "worship":    ["worship", "praise", "glorify", "adore", "exalt"],
            "conviction": ["conviction", "convict", "repent", "repentance", "turn away"],
            "identity":   ["identity", "who I am", "child of God", "chosen", "beloved"],
            "calling":    ["calling", "purpose", "mission", "sent", "vocation"],
            "surrender":  ["surrender", "let go", "yield", "release", "give up"],
            "growth":     ["grow", "growth", "mature", "sanctification", "transform"],
            "love":       ["love", "compassion", "kindness", "care", "sacrifice"]
        ]

        let lowered = text.lowercased()
        var detected: [String] = []

        for (theme, keywords) in themeKeywords {
            if keywords.contains(where: { lowered.contains($0) }) {
                detected.append(theme)
            }
        }

        return detected.sorted()
    }

    // MARK: - Smart File Naming

    func generateSmartFileName(
        churchName: String?,
        speakerName: String?,
        title: String,
        date: Date
    ) -> String {
        let yearStr = date.formatted(.dateTime.year())

        // Easter detection: rough heuristic
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if month == 4 && (day >= 9 && day <= 18) {
            return "Easter Sunday \(yearStr)"
        }

        if let church = churchName, !church.isEmpty {
            return "Sunday at \(church) — \(title)"
        } else if let speaker = speakerName, !speaker.isEmpty {
            return "\(speaker) — \(title)"
        }
        return title
    }

    // MARK: - Private: Prompt Building

    private func buildOrganizePrompt(
        rawContent: String,
        transcript: String?,
        churchName: String?,
        speakerName: String?
    ) -> String {
        var contextLines: [String] = []
        if let church = churchName, !church.isEmpty {
            contextLines.append("Church: \(church)")
        }
        if let speaker = speakerName, !speaker.isEmpty {
            contextLines.append("Speaker: \(speaker)")
        }
        let context = contextLines.isEmpty ? "" : contextLines.joined(separator: "\n") + "\n\n"

        var transcriptSection = ""
        if let transcript = transcript, !transcript.isEmpty {
            transcriptSection = "\n\nSERMON TRANSCRIPT (audio capture):\n\(transcript)"
        }

        return """
        You are helping organize a set of church notes into a clear, structured sermon record. \
        Analyze both the handwritten notes and any transcript provided, then return a structured \
        response using ONLY the labeled fields below. Be concise and faith-centered.

        \(context)NOTES:\n\(rawContent)\(transcriptSection)

        Return EXACTLY these labeled fields, one per line:
        TITLE: [clean sermon title — 3-8 words]
        SUBTITLE: [conviction or theme subtitle — optional, or NONE]
        MAIN: [1-2 sentence summary of the core message]
        POINT_1: [first key point]
        POINT_2: [second key point]
        POINT_3: [third key point]
        POINT_4: [fourth key point — or NONE]
        POINT_5: [fifth key point — or NONE]
        SCRIPTURE_1: [first scripture reference — book chapter:verse]
        SCRIPTURE_2: [second scripture reference — or NONE]
        SCRIPTURE_3: [third scripture reference — or NONE]
        THEME_1: [first spiritual theme tag — single word or short phrase]
        THEME_2: [second theme — or NONE]
        THEME_3: [third theme — or NONE]
        TAKEAWAY_1: [personal "I" statement takeaway]
        TAKEAWAY_2: [second takeaway — or NONE]
        TAKEAWAY_3: [third takeaway — or NONE]
        ACTION_1: [concrete action step]
        ACTION_2: [second action step — or NONE]
        PRAYER: [2-3 sentence prayer response to the message]
        QUESTION_1: [open question or thing to study further — or NONE]
        QUESTION_2: [second question — or NONE]
        FOLDER_COLOR: [one of: gold, blue, green, red, purple, gray, teal, amber]
        NOTE_TYPE: [one of: Sermon Note, Personal Reflection, Bible Study, Prayer Entry, Berean Conversation, Church Visit, Worship Reflection]
        """
    }

    // MARK: - Private: Response Parsing

    private func parseOrganizedResponse(
        _ response: String,
        churchName: String?,
        speakerName: String?,
        date: Date
    ) -> OrganizedSermonNote {
        func extract(_ prefix: String) -> String? {
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix(prefix.uppercased() + ":") {
                    let value = trimmed
                        .dropFirst(prefix.count + 1)
                        .trimmingCharacters(in: .whitespaces)
                    return (value.isEmpty || value.uppercased() == "NONE") ? nil : value
                }
            }
            return nil
        }

        func extractMultiple(_ prefixes: [String]) -> [String] {
            prefixes.compactMap { extract($0) }
        }

        let title = extract("TITLE") ?? "Sermon Notes"
        let subtitle = extract("SUBTITLE")
        let mainMessage = extract("MAIN") ?? "A message from God's Word."

        let keyPoints = extractMultiple(["POINT_1", "POINT_2", "POINT_3", "POINT_4", "POINT_5"])
        let scriptures = extractMultiple(["SCRIPTURE_1", "SCRIPTURE_2", "SCRIPTURE_3"])
        let themes = extractMultiple(["THEME_1", "THEME_2", "THEME_3"])
        let takeaways = extractMultiple(["TAKEAWAY_1", "TAKEAWAY_2", "TAKEAWAY_3"])
        let actions = extractMultiple(["ACTION_1", "ACTION_2"])
        let prayer = extract("PRAYER") ?? "Lord, help me live out what I heard today."
        let questions = extractMultiple(["QUESTION_1", "QUESTION_2"])

        let colorRaw = extract("FOLDER_COLOR") ?? "gold"
        let folderColor = NoteColorTheme(rawValue: colorRaw.lowercased()) ?? .gold

        let noteTypeRaw = extract("NOTE_TYPE") ?? "Sermon Note"
        let noteType = NoteType(rawValue: noteTypeRaw) ?? .sermonNote

        return OrganizedSermonNote(
            title: title,
            subtitle: subtitle,
            mainMessage: mainMessage,
            keyPoints: keyPoints,
            scriptures: scriptures,
            themes: themes,
            personalTakeaways: takeaways,
            actionSteps: actions,
            prayerResponse: prayer,
            questionsToRevisit: questions,
            suggestedFolderTheme: folderColor,
            suggestedNoteType: noteType
        )
    }

    // MARK: - Private: Reflection Prompt Parsing

    private func parseReflectionPrompts(
        _ response: String,
        for note: OrganizedSermonNote
    ) -> ReflectionPromptSet {
        let lines = response.components(separatedBy: "\n")

        var prompts: [String] = lines
            .filter { $0.uppercased().hasPrefix("PROMPT:") }
            .map { String($0.dropFirst("PROMPT:".count)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        func extractGrowth(_ prefix: String) -> String {
            lines.first { $0.uppercased().hasPrefix(prefix + ":") }
                .map { String($0.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces) }
            ?? fallbackGrowthPrompt(day: prefix, note: note)
        }

        // Ensure we always have 3 prompts minimum
        while prompts.count < 3 {
            prompts.append(fallbackReflectionQuestion(index: prompts.count, note: note))
        }

        let schedule = ReflectionPromptSet.GrowthLoopSchedule(
            day1Prompt: extractGrowth("DAY1"),
            day3Prompt: extractGrowth("DAY3"),
            day7Prompt: extractGrowth("DAY7")
        )

        return ReflectionPromptSet(prompts: Array(prompts.prefix(5)), growthLoopSchedule: schedule)
    }

    private func fallbackReflectionPrompts(for note: OrganizedSermonNote) -> ReflectionPromptSet {
        let prompts = [
            "What stood out most to you from today's message?",
            "How does \(note.mainMessage.prefix(60))... apply to your life right now?",
            "What is one thing you want to remember from this sermon a year from now?",
            "Is there something you feel God is specifically asking you to do or change?",
            "Who in your life needs to hear what you heard today?"
        ]

        let schedule = ReflectionPromptSet.GrowthLoopSchedule(
            day1Prompt: "What was the one thing from Sunday you're still thinking about?",
            day3Prompt: "Have you taken any steps toward the action you felt called to?",
            day7Prompt: "Looking back on this message — what has God been confirming in your week?"
        )
        return ReflectionPromptSet(prompts: prompts, growthLoopSchedule: schedule)
    }

    private func fallbackReflectionQuestion(index: Int, note: OrganizedSermonNote) -> String {
        let defaults = [
            "What stood out most to you from today's message?",
            "How does this apply to your life right now?",
            "What is one thing you want to remember from this sermon?",
            "Is there something God is specifically asking you to do?",
            "Who in your life needs to hear what you heard today?"
        ]
        return defaults[min(index, defaults.count - 1)]
    }

    private func fallbackGrowthPrompt(day: String, note: OrganizedSermonNote) -> String {
        switch day {
        case "DAY1": return "What was the one thing from this message you're still thinking about?"
        case "DAY3": return "Have you taken any steps toward what God put on your heart?"
        case "DAY7": return "Looking back — what has God confirmed in your week since this message?"
        default:     return "How has this message stayed with you?"
        }
    }
}
