//
//  ScriptureGraphModels.swift
//  AMENAPP
//
//  Domain models for the Living Scripture Graph —
//  a semantic, theological, and narrative graph engine.
//
//  Graph shape per passage:
//    verse → cross-references → themes → Greek/Hebrew word insights
//      → Christ-connection → application paths → scene context
//
//  Firestore collections (populated by backend):
//    scripture_passages      — canonical passage metadata
//    scripture_themes        — thematic clusters
//    scripture_cross_refs    — directed cross-reference edges
//    scripture_word_insights — Greek/Hebrew lexicon entries
//    scripture_christ_connections — typological & prophetic connections to Jesus
//    scripture_application_paths  — practical application prompts
//    scripture_scene_context      — historical/cultural background
//    study_cache             — per-user study cache entries
//

import Foundation

// MARK: - Scripture Reference

/// A strongly-typed scripture reference (book, chapter, verse range).
struct ScripturePassageRef: Codable, Hashable, Equatable {
    let book: String           // e.g. "John"
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int?         // nil for single-verse references
    let translation: String    // e.g. "ESV", "NIV", "KJV"

    /// Formatted display string, e.g. "John 3:16 (ESV)" or "Romans 8:28–30 (NIV)"
    var displayString: String {
        let verse = verseEnd.map { "\(verseStart)–\($0)" } ?? "\(verseStart)"
        return "\(book) \(chapter):\(verse) (\(translation))"
    }

    /// Compact key for graph lookups, e.g. "john_3_16_esv"
    var graphKey: String {
        "\(book.lowercased())_\(chapter)_\(verseStart)_\(translation.lowercased())"
    }
}

// MARK: - Passage Payload

/// The full hydrated payload for a scripture passage node in the graph.
/// Returned by `studyPassage` Cloud Function.
struct ScripturePassagePayload: Codable, Identifiable, Equatable {
    let id: String             // Firestore document ID
    let reference: ScripturePassageRef
    let text: String           // Full passage text in the requested translation
    let summary: String        // One-sentence summary for the graph node label
    let themes: [ScriptureTheme]
    let crossReferences: [ScriptureCrossRef]
    let wordInsights: [WordStudyItem]
    let christConnection: ChristConnectionItem?
    let applicationPaths: [ApplicationPath]
    let sceneContext: ScriptureSceneContext?
    let cachedAt: Date
}

// MARK: - Scripture Theme

/// A thematic cluster node in the Scripture Graph.
struct ScriptureTheme: Codable, Identifiable, Equatable {
    let id: String
    let name: String           // e.g. "Redemption", "Grace", "Covenant"
    let description: String
    let relatedPassages: [String]  // Firestore document IDs of related passages
    let category: ThemeCategory

    enum ThemeCategory: String, Codable {
        case theological    = "theological"   // Doctrine, systematic theology
        case narrative      = "narrative"     // Story arc, characters
        case prophetic      = "prophetic"     // Prophecy and fulfillment
        case wisdom         = "wisdom"        // Proverbs, principles
        case ethical        = "ethical"       // Moral instruction
        case eschatological = "eschatological" // End times, kingdom
    }
}

// MARK: - Cross Reference

/// A directed edge in the Scripture Graph connecting two passages.
struct ScriptureCrossRef: Codable, Identifiable, Equatable {
    let id: String
    let sourcePassageId: String
    let targetReference: ScripturePassageRef
    let targetText: String     // Short excerpt for inline display
    let relationshipType: CrossRefRelationship
    /// How strongly this cross-reference is supported (0–1).
    let strength: Double

    enum CrossRefRelationship: String, Codable {
        case fulfillment    = "fulfillment"   // OT prophecy → NT fulfillment
        case parallel       = "parallel"      // Similar event or teaching
        case contrast       = "contrast"      // Antithetical or contrasting passage
        case quotation      = "quotation"     // Direct NT quotation of OT
        case allusion       = "allusion"      // Indirect reference
        case commentary     = "commentary"    // Passage that explains this one
        case application    = "application"   // Passage that applies this teaching
    }
}

// MARK: - Word Study Item

/// A Greek (NT) or Hebrew (OT) word study attached to a key term in the passage.
struct WordStudyItem: Codable, Identifiable, Equatable {
    let id: String
    /// The English word in the passage.
    let surfaceWord: String
    /// The original-language word (Greek/Hebrew script).
    let originalWord: String
    /// Transliteration.
    let transliteration: String
    /// Strong's number (e.g. "G26" for ἀγάπη).
    let strongsNumber: String?
    /// Definition from lexicon.
    let definition: String
    /// Semantic range: other ways this word is used across the Bible.
    let semanticRange: [String]
    /// The language of the source text.
    let language: OriginalLanguage
    /// A short devotional implication of the word's meaning.
    let devotionalNote: String?

    enum OriginalLanguage: String, Codable {
        case greek  = "greek"
        case hebrew = "hebrew"
        case aramaic = "aramaic"
    }
}

// MARK: - Christ Connection Item

/// Typological or prophetic connection showing how this passage points to Jesus.
/// Non-negotiable principle: never fabricate connections not supported by Scripture or
/// recognized hermeneutical tradition. `confidence` gates display.
struct ChristConnectionItem: Codable, Equatable {
    let passageId: String
    /// A concise statement of the connection.
    let connectionStatement: String
    /// The NT reference that confirms the connection.
    let ntFulfillmentReference: ScripturePassageRef?
    let connectionType: ConnectionType
    /// Hermeneutical confidence (0–1). Display only if ≥ 0.6.
    let confidence: Double
    /// Attribution — which theological tradition supports this reading.
    let hermeneuticalTradition: String?

    enum ConnectionType: String, Codable {
        case directProphecy     = "direct_prophecy"   // Explicitly foretold
        case typology           = "typology"          // Person/event as a type of Christ
        case thematicPattern    = "thematic_pattern"  // Recurring theme pointing forward
        case fulfillment        = "fulfillment"       // OT shadow → NT reality
    }
}

// MARK: - Application Path

/// A practical application prompt rooted in the passage.
/// Designed to be presented as a guided reflection, not a legalistic checklist.
struct ApplicationPath: Codable, Identifiable, Equatable {
    let id: String
    let passageId: String
    let prompt: String         // The reflection/application question or challenge
    let category: ApplicationCategory
    /// Whether this application involves another person (accountability-oriented).
    let relational: Bool
    /// Optional action step (only shown if user opts in).
    let actionStep: String?

    enum ApplicationCategory: String, Codable {
        case personal       = "personal"       // Inner spiritual formation
        case relational     = "relational"     // How to live with others
        case communal       = "communal"       // Church community application
        case evangelistic   = "evangelistic"   // Outreach and witness
        case justice        = "justice"        // Social concern, care for others
    }
}

// MARK: - Scripture Scene Context

/// Historical, cultural, and geographical background for the passage.
/// Used by Scripture Immersion Mode.
struct ScriptureSceneContext: Codable, Equatable {
    let passageId: String
    /// A short narrative description of the historical setting.
    let historicalSetting: String
    /// Cultural practices relevant to understanding the text.
    let culturalNotes: [String]
    /// Author, audience, and purpose of the book.
    let authorContext: String?
    /// Geographical details (city, region, terrain).
    let geographicalContext: String?
    /// Date/period estimate (e.g. "~AD 60–65").
    let datePeriod: String?
    /// Key figures in the scene beyond those named in the text.
    let keyFigures: [String]
    /// The literary genre and how it affects interpretation.
    let literaryGenre: String
    /// Observation → Interpretation → Reflection structure.
    let studyStructure: ImmersionStudyStructure?
}

// MARK: - Immersion Study Structure

/// Structures the passage using the classic inductive Bible study approach:
/// Observation (what does it say?) → Interpretation (what does it mean?)
/// → Reflection (what does it mean for me?).
/// Non-negotiable: clearly distinguish interpretation from observation;
/// reflection must remain invitation, never obligation.
struct ImmersionStudyStructure: Codable, Equatable {
    /// "What does this passage say?" — observation-only, no interpretation.
    let observation: String
    /// "What did it mean in its original context?" — historically grounded.
    let interpretation: String
    /// "What does this invite for my life today?" — personal, invitational.
    let reflection: String
    /// Whether this passage has historically controversial interpretations.
    let hasInterpretiveDebate: Bool
    /// Brief note on the debate (shown only if `hasInterpretiveDebate == true`).
    let interpretiveDebateNote: String?
}

// MARK: - Scripture Graph Payload

/// The full graph exploration payload: a central passage node plus its
/// immediate neighborhood of connections. Returned by the graph explorer.
struct ScriptureGraphPayload: Codable, Equatable {
    let centralPassage: ScripturePassagePayload
    /// Top cross-referenced passages, sorted by `strength` descending.
    let crossRefNodes: [ScripturePassagePayload]
    /// Top thematic connections from the graph.
    let themeCluster: [ScriptureTheme]
    /// Total edges in the full graph (for display purposes).
    let totalEdgeCount: Int
    let fetchedAt: Date
}

// MARK: - Study Cache Entry

/// Per-user cached study session.
/// Firestore: /users/{uid}/studyCache/{cacheKey}
struct StudyCacheEntry: Codable, Identifiable, Equatable {
    let id: String             // Same as cacheKey
    let userId: String
    let passageId: String
    let reference: ScripturePassageRef
    let graphPayload: ScriptureGraphPayload?
    let studiedAt: Date
    var completedImmersionMode: Bool
    var applicationPathsReviewed: [String]  // IDs of ApplicationPath seen
}
