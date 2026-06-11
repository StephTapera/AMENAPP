//
//  SelahModels.swift
//  AMENAPP
//
//  Data models for the Selah feature system:
//  1. Ask Selah (grounded AI workspace)
//  2. Thought Trails (theme memory)
//  3. Verse Explorer (YouVersion deep integration)
//  4. Transformation Cards (NotebookLM-style)
//  5. Workflow Engine (verse-to-testimony)
//

import SwiftUI
import FirebaseFirestore

// MARK: - Ask Selah Source Bundle

/// Aggregated sources that ground an Ask Selah AI response.
struct SelahSourceBundle {
    var verses: [SelahVerseSource]
    var notes: [SelahNoteSource]
    var prayers: [SelahPrayerSource]
    var testimonies: [SelahTestimonySource]
    var bereanHistory: [SelahBereanSource]

    var isEmpty: Bool {
        verses.isEmpty && notes.isEmpty && prayers.isEmpty && testimonies.isEmpty && bereanHistory.isEmpty
    }

    var totalCount: Int {
        verses.count + notes.count + prayers.count + testimonies.count + bereanHistory.count
    }

    /// Builds a prompt-friendly summary of all sources.
    func promptContext(limit: Int = 2000) -> String {
        var parts: [String] = []

        if !verses.isEmpty {
            let verseSummary = verses.prefix(5).map { "\($0.reference) (\($0.version)): \($0.text.prefix(200))" }.joined(separator: "\n")
            parts.append("SCRIPTURE:\n\(verseSummary)")
        }
        if !notes.isEmpty {
            let notesSummary = notes.prefix(3).map { "[\($0.title)] \($0.contentPreview.prefix(200))" }.joined(separator: "\n")
            parts.append("YOUR NOTES:\n\(notesSummary)")
        }
        if !prayers.isEmpty {
            let prayerSummary = prayers.prefix(3).map { $0.contentPreview.prefix(200).description }.joined(separator: "\n")
            parts.append("YOUR PRAYERS:\n\(prayerSummary)")
        }
        if !testimonies.isEmpty {
            let testSummary = testimonies.prefix(2).map { $0.contentPreview.prefix(200).description }.joined(separator: "\n")
            parts.append("YOUR TESTIMONIES:\n\(testSummary)")
        }
        if !bereanHistory.isEmpty {
            let histSummary = bereanHistory.prefix(3).map { "Q: \($0.query.prefix(80))\nA: \($0.responsePreview.prefix(150))" }.joined(separator: "\n")
            parts.append("PREVIOUS STUDIES:\n\(histSummary)")
        }

        let full = parts.joined(separator: "\n\n")
        return String(full.prefix(limit))
    }
}

struct SelahVerseSource: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
    let version: String
}

struct SelahNoteSource: Identifiable {
    let id = UUID()
    let noteId: String
    let title: String
    let contentPreview: String
    let date: Date
}

struct SelahPrayerSource: Identifiable {
    let id = UUID()
    let prayerId: String
    let contentPreview: String
    let date: Date
}

struct SelahTestimonySource: Identifiable {
    let id = UUID()
    let testimonyId: String
    let contentPreview: String
    let date: Date
}

struct SelahBereanSource: Identifiable {
    let id = UUID()
    let query: String
    let responsePreview: String
    let date: Date
}

// MARK: - Grounded Response

/// An AI response that includes inline citations to the source bundle.
struct SelahGroundedResponse: Identifiable {
    let id = UUID()
    let content: String
    var citations: [SelahCitation]
    let generatedAt: Date

    init(content: String, citations: [SelahCitation] = [], generatedAt: Date = Date()) {
        self.content = content
        self.citations = citations
        self.generatedAt = generatedAt
    }
}

struct SelahCitation: Identifiable {
    let id = UUID()
    let label: String        // e.g., "John 3:16" or "Sunday Sermon Note"
    let sourceType: SourceType
    let snippetPreview: String

    enum SourceType: String {
        case scripture = "Scripture"
        case note      = "Note"
        case prayer    = "Prayer"
        case testimony = "Testimony"
        case berean    = "Study"

        var icon: String {
            switch self {
            case .scripture:  return "book.fill"
            case .note:       return "note.text"
            case .prayer:     return "hands.sparkles"
            case .testimony:  return "person.wave.2"
            case .berean:     return "brain.head.profile"
            }
        }
    }
}

// MARK: - Thought Trails / Theme Memory

/// A recorded Selah session, persisted to Firestore.
struct SelahSession: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var query: String
    var responsePreview: String
    var format: String       // SelahFormat rawValue
    var scriptureRefs: [String]
    var tags: [String]       // Theme tags
    var linkedNoteIds: [String]
    var linkedPrayerIds: [String]
    var linkedTestimonyIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: String = "",
        title: String = "",
        query: String = "",
        responsePreview: String = "",
        format: String = "Essay",
        scriptureRefs: [String] = [],
        tags: [String] = [],
        linkedNoteIds: [String] = [],
        linkedPrayerIds: [String] = [],
        linkedTestimonyIds: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.title = title
        self.query = query
        self.responsePreview = responsePreview
        self.format = format
        self.scriptureRefs = scriptureRefs
        self.tags = tags
        self.linkedNoteIds = linkedNoteIds
        self.linkedPrayerIds = linkedPrayerIds
        self.linkedTestimonyIds = linkedTestimonyIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SelahReflectionEntry: Identifiable {
    let id = UUID()
    let sessionId: String
    let content: String
    let scriptureRef: String?
    let createdAt: Date
}

struct ThemeTag: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var count: Int
    let color: Color

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: ThemeTag, rhs: ThemeTag) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Verse Explorer

struct VerseExpansion: Identifiable {
    let id = UUID()
    let reference: String
    let passages: [ScripturePassage]
    let contextBefore: String?
    let contextAfter: String?
}

struct CrossReference: Identifiable {
    let id = UUID()
    let sourceRef: String
    let targetRef: String
    let relationship: String   // "parallel", "fulfillment", "allusion", "contrast"
    let snippet: String?
}

// MARK: - Transformation Cards

enum SelahTransformationType: String, CaseIterable, Identifiable {
    case devotional   = "Devotional"
    case prayerGuide  = "Prayer Guide"
    case studyOutline = "Study Outline"
    case memoryCard   = "Memory Card"
    case journalPrompt = "Journal Prompt"
    case shareSnippet = "Share Snippet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devotional:    return "sun.max.fill"
        case .prayerGuide:   return "hands.sparkles"
        case .studyOutline:  return "list.number"
        case .memoryCard:    return "rectangle.stack.fill"
        case .journalPrompt: return "pencil.line"
        case .shareSnippet:  return "square.and.arrow.up"
        }
    }

    var description: String {
        switch self {
        case .devotional:    return "Turn this into a short morning devotional"
        case .prayerGuide:   return "Generate a guided prayer based on these insights"
        case .studyOutline:  return "Create a structured Bible study outline"
        case .memoryCard:    return "Distill into a flashcard-style memory aid"
        case .journalPrompt: return "Create reflective journaling prompts"
        case .shareSnippet:  return "Craft a shareable insight for social"
        }
    }

    var accentColor: Color {
        switch self {
        case .devotional:    return .orange
        case .prayerGuide:   return .purple
        case .studyOutline:  return .blue
        case .memoryCard:    return .green
        case .journalPrompt: return .teal
        case .shareSnippet:  return .pink
        }
    }
}

struct SelahTransformationOutput: Identifiable {
    let id = UUID()
    let type: SelahTransformationType
    let content: String
    let scriptureRefs: [String]
    let generatedAt: Date

    init(type: SelahTransformationType, content: String, scriptureRefs: [String] = [], generatedAt: Date = Date()) {
        self.type = type
        self.content = content
        self.scriptureRefs = scriptureRefs
        self.generatedAt = generatedAt
    }
}

// MARK: - Workflow Engine

/// The stages in the verse-to-testimony workflow.
enum WorkflowStage: String, CaseIterable, Identifiable, Codable {
    case verse     = "Verse"
    case reflect   = "Reflect"
    case pray      = "Pray"
    case journal   = "Journal"
    case testimony = "Testimony"
    case share     = "Share"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .verse:     return "book.fill"
        case .reflect:   return "brain.head.profile"
        case .pray:      return "hands.sparkles"
        case .journal:   return "pencil.line"
        case .testimony: return "person.wave.2"
        case .share:     return "square.and.arrow.up"
        }
    }

    var prompt: String {
        switch self {
        case .verse:     return "Start with a verse"
        case .reflect:   return "Reflect on what it means to you"
        case .pray:      return "Turn your reflection into prayer"
        case .journal:   return "Journal your experience"
        case .testimony: return "Shape it into a testimony"
        case .share:     return "Share with your community"
        }
    }

    /// Ordered index for progress tracking.
    var order: Int {
        switch self {
        case .verse:     return 0
        case .reflect:   return 1
        case .pray:      return 2
        case .journal:   return 3
        case .testimony: return 4
        case .share:     return 5
        }
    }
}

/// A persisted workflow instance.
struct SelahWorkflow: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var verseReference: String
    var currentStage: String   // WorkflowStage rawValue
    var stageData: [String: String]  // stage rawValue → user content
    var createdAt: Date
    var updatedAt: Date
    var isComplete: Bool

    init(
        userId: String = "",
        verseReference: String = "",
        currentStage: String = "Verse",
        stageData: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isComplete: Bool = false
    ) {
        self.userId = userId
        self.verseReference = verseReference
        self.currentStage = currentStage
        self.stageData = stageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isComplete = isComplete
    }

    var currentWorkflowStage: WorkflowStage {
        WorkflowStage(rawValue: currentStage) ?? .verse
    }
}

/// Suggestion for the next step in a workflow.
struct WorkflowSuggestion: Identifiable {
    let id = UUID()
    let stage: WorkflowStage
    let prompt: String
    let aiSuggestion: String?
}

/// Actions that can be triggered from workflow UI.
enum WorkflowAction {
    case openVerse(String)
    case startSelah
    case createPrayer
    case openJournal
    case createTestimony
    case shareToOpenTable
}

struct SelahLastReadEntry: Equatable {
    let sessionId: String?
    let sessionTitle: String
    let reference: String
    let updatedAt: Date
}

enum SelahLastReadResolver {
    static func resolve(
        sessions: [SelahSession],
        excluding excludedReferences: [String] = [],
        now: Date = Date(),
        maxAge: TimeInterval = 30 * 24 * 60 * 60
    ) -> SelahLastReadEntry? {
        let excluded = Set(excludedReferences.map { normalizedReference($0) }.filter { !$0.isEmpty })

        return sessions
            .compactMap { session -> SelahLastReadEntry? in
                guard now.timeIntervalSince(session.createdAt) <= maxAge else { return nil }
                guard let rawReference = session.scriptureRefs.first else { return nil }

                let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reference.isEmpty else { return nil }
                guard !excluded.contains(normalizedReference(reference)) else { return nil }

                let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return SelahLastReadEntry(
                    sessionId: session.id,
                    sessionTitle: title.isEmpty ? reference : title,
                    reference: reference,
                    updatedAt: session.createdAt
                )
            }
            .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
    }

    private static func normalizedReference(_ reference: String) -> String {
        reference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
