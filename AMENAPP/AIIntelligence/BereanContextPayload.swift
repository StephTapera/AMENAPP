import Foundation

struct BereanContextPayload: Codable, Equatable, Identifiable {
    let id: String
    let selectedText: String
    let surroundingText: String?
    let sourceSurface: String
    let sourceId: String?
    let contentType: BereanContextContentType
    let scriptureReference: String?
    let languageCode: String?
    let metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        selectedText: String,
        surroundingText: String? = nil,
        sourceSurface: String,
        sourceId: String? = nil,
        contentType: BereanContextContentType,
        scriptureReference: String? = nil,
        languageCode: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.selectedText = selectedText
        self.surroundingText = surroundingText
        self.sourceSurface = sourceSurface
        self.sourceId = sourceId
        self.contentType = contentType
        self.scriptureReference = scriptureReference
        self.languageCode = languageCode
        self.metadata = metadata
    }
}

enum BereanContextContentType: String, Codable, CaseIterable {
    case scripture
    case post
    case comment
    case caption
    case transcript
    case note
    case message
    case media
    case article
    case unknown
}

enum BereanContextAction: String, Codable, CaseIterable, Identifiable {
    case askBerean
    case explain
    case simplify
    case summarize
    case reflect
    case prayAboutThis
    case compareScripture
    case translate
    case define
    case historicalContext
    case saveToChurchNotes
    case createStudy
    case addReminder
    case turnIntoPrayer
    case turnIntoDevotional
    case turnIntoSermonOutline
    case shareReflection
    case askFollowUp
    case voiceExplain
    case discussWithGroup
    case askMentor
    case askPastor
    case searchRelatedVerses
    case createCarousel
    case createPost
    case continueReading
    case factCheck
    case crossReference
    case emotionalInsight
    case leadershipInsight
    case youthExplanation
    case beginnerExplanation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askBerean: return "Ask Berean"
        case .explain: return "Explain"
        case .simplify: return "Simplify"
        case .summarize: return "Summarize"
        case .reflect: return "Reflect"
        case .prayAboutThis: return "Pray"
        case .compareScripture: return "Compare"
        case .translate: return "Translate"
        case .define: return "Define"
        case .historicalContext: return "History"
        case .saveToChurchNotes: return "Save"
        case .createStudy: return "Study"
        case .addReminder: return "Reminder"
        case .turnIntoPrayer: return "Prayer"
        case .turnIntoDevotional: return "Devotional"
        case .turnIntoSermonOutline: return "Outline"
        case .shareReflection: return "Share"
        case .askFollowUp: return "Follow-Up"
        case .voiceExplain: return "Voice"
        case .discussWithGroup: return "Discuss"
        case .askMentor: return "Mentor"
        case .askPastor: return "Pastor"
        case .searchRelatedVerses: return "Verses"
        case .createCarousel: return "Carousel"
        case .createPost: return "Post"
        case .continueReading: return "Continue"
        case .factCheck: return "Fact Check"
        case .crossReference: return "Cross Ref"
        case .emotionalInsight: return "Insight"
        case .leadershipInsight: return "Leadership"
        case .youthExplanation: return "Youth"
        case .beginnerExplanation: return "Beginner"
        }
    }

    var systemImage: String {
        switch self {
        case .askBerean: return "sparkles"
        case .explain: return "text.bubble"
        case .simplify: return "textformat.abc"
        case .summarize: return "text.quote"
        case .reflect: return "leaf"
        case .prayAboutThis, .turnIntoPrayer: return "hands.sparkles"
        case .compareScripture, .crossReference: return "books.vertical"
        case .translate: return "globe"
        case .define: return "character.book.closed"
        case .historicalContext: return "clock"
        case .saveToChurchNotes: return "square.and.pencil"
        case .createStudy: return "book.closed"
        case .addReminder: return "bell"
        case .turnIntoDevotional: return "sun.max"
        case .turnIntoSermonOutline: return "list.bullet.rectangle"
        case .shareReflection: return "square.and.arrow.up"
        case .askFollowUp: return "questionmark.bubble"
        case .voiceExplain: return "waveform"
        case .discussWithGroup: return "person.2"
        case .askMentor: return "person.crop.circle.badge.questionmark"
        case .askPastor: return "cross"
        case .searchRelatedVerses: return "magnifyingglass"
        case .createCarousel: return "rectangle.stack"
        case .createPost: return "plus.app"
        case .continueReading: return "arrow.right"
        case .factCheck: return "checkmark.seal"
        case .emotionalInsight: return "heart.text.square"
        case .leadershipInsight: return "person.3.sequence"
        case .youthExplanation: return "figure.2.and.child.holdinghands"
        case .beginnerExplanation: return "graduationcap"
        }
    }

    var requiresExpandedWorkspace: Bool {
        switch self {
        case .createStudy, .turnIntoSermonOutline, .createCarousel, .createPost, .discussWithGroup:
            return true
        default:
            return false
        }
    }
}

// MARK: - BereanContextActionResult
// Wire shape extended with constitutional audit fields (safety-hardening, 2026-06-12).
// constitutionalMode and epistemicDeclaration are non-optional so downstream consumers
// always have an audit trail anchor.

struct BereanContextActionResult: Identifiable, Equatable {
    let id: String
    let action: BereanContextAction
    let title: String
    let answer: String
    let scriptureReferences: [String]
    let suggestedActions: [String]
    let safetyNotice: String?
    let threadId: String?
    /// The constitutional mode that was in effect when this result was produced.
    let constitutionalMode: BereanConstitutionalMode
    /// Epistemic declaration attached by the gate — surfaces uncertainty to UI.
    let epistemicDeclaration: EpistemicDeclaration
}
