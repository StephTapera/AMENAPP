// SemanticTopicService.swift
// AMENAPP
//
// On-device semantic understanding of topics across all AMEN surfaces.
// Powers:
//   - Post, comment, note topic tagging
//   - Scripture reference detection + normalization
//   - "Related verses / notes / resources" cross-linking
//   - Feed diversity scoring (cluster awareness)
//   - Search intent classification
//   - Spiritual content detection for AI routing
//   - Quality scoring for feed ranking
//
// All fast methods run fully on-device (< 2ms).
// Embedding-based methods call Vertex AI embeddings via Cloud Functions.

import Foundation
import NaturalLanguage

// MARK: - Topic Cluster

enum SpiritualTopicCluster: String, CaseIterable, Codable {
    case scripture        = "Scripture"
    case prayer           = "Prayer"
    case testimony        = "Testimony"
    case discipleship     = "Discipleship"
    case worship          = "Worship"
    case theology         = "Theology"
    case community        = "Community"
    case faithAndWork     = "Faith & Work"
    case mentalHealth     = "Mental Health"
    case family           = "Family"
    case evangelism       = "Evangelism"
    case servanthood      = "Servanthood"
    case grief            = "Grief"
    case healing          = "Healing"
    case propheticWord    = "Prophetic"
    case general          = "General"

    // Color for UI chips
    var chipColor: (r: Double, g: Double, b: Double) {
        switch self {
        case .scripture:    return (0.88, 0.38, 0.28)
        case .prayer:       return (0.35, 0.60, 0.88)
        case .testimony:    return (0.25, 0.72, 0.52)
        case .discipleship: return (0.58, 0.35, 0.88)
        case .worship:      return (0.92, 0.62, 0.20)
        case .theology:     return (0.40, 0.40, 0.80)
        case .community:    return (0.20, 0.68, 0.62)
        case .faithAndWork: return (0.70, 0.45, 0.22)
        case .mentalHealth: return (0.25, 0.65, 0.40)
        case .family:       return (0.85, 0.40, 0.55)
        case .evangelism:   return (0.95, 0.50, 0.25)
        case .servanthood:  return (0.35, 0.60, 0.80)
        case .grief:        return (0.55, 0.55, 0.70)
        case .healing:      return (0.28, 0.75, 0.55)
        case .propheticWord:return (0.72, 0.30, 0.80)
        case .general:      return (0.55, 0.55, 0.55)
        }
    }
}

// MARK: - Topic Tag

struct TopicTag: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let cluster: SpiritualTopicCluster
    let confidence: Double      // 0-1.0
    let isScriptureRef: Bool
    let normalizedRef: String?  // e.g. "John 3:16" normalized form

    var isHighConfidence: Bool { confidence >= 0.70 }
}

// MARK: - Scripture Reference Parser

struct ScriptureRef: Equatable {
    let book: String
    let chapter: Int
    let verse: Int?
    let endVerse: Int?

    var displayString: String {
        var s = "\(book) \(chapter)"
        if let v = verse { s += ":\(v)" }
        if let ev = endVerse { s += "-\(ev)" }
        return s
    }
}

// MARK: - SemanticTopicService

@MainActor
final class SemanticTopicService {

    static let shared = SemanticTopicService()

    // Keyword → cluster mapping (fast, on-device)
    private let clusterKeywords: [SpiritualTopicCluster: [String]] = [
        .scripture:     ["bible", "scripture", "verse", "passage", "book of", "psalm", "proverbs", "genesis",
                          "exodus", "matthew", "mark", "luke", "john", "acts", "romans", "corinthians",
                          "ephesians", "philippians", "colossians", "hebrews", "revelation", "old testament",
                          "new testament", "esv", "niv", "kjv", "nkjv", "word of god"],
        .prayer:        ["pray", "prayer", "intercession", "supplication", "thanksgiving", "petition",
                          "lord hear", "god please", "amen", "holy spirit guide"],
        .testimony:     ["testimony", "god did", "miracle", "healed", "delivered", "transformed", "breakthrough",
                          "god saved", "my story", "what god has done"],
        .discipleship:  ["disciple", "follow jesus", "grow in faith", "sanctification", "obedience",
                          "study bible", "devotional", "quiet time", "daily bread", "spiritual discipline"],
        .worship:       ["worship", "praise", "glorify", "hymn", "song", "holy holy", "magnify",
                          "exalt", "lift your name", "adoration"],
        .theology:      ["theology", "doctrine", "hermeneutics", "exegesis", "salvation", "atonement",
                          "justification", "sanctification", "election", "predestination", "trinity",
                          "incarnation", "resurrection", "eschatology", "soteriology"],
        .community:     ["church", "fellowship", "community", "brothers sisters", "body of christ",
                          "small group", "accountability", "together", "unity", "one another"],
        .faithAndWork:  ["work", "career", "calling", "vocation", "business", "monday", "marketplace",
                          "faith at work", "purpose", "stewardship", "excellence"],
        .mentalHealth:  ["anxiety", "depression", "mental health", "peace", "rest", "overwhelmed",
                          "stress", "fear", "worry", "cast your cares", "be still"],
        .family:        ["family", "marriage", "spouse", "husband", "wife", "children", "parenting",
                          "father", "mother", "home", "household"],
        .evangelism:    ["gospel", "share faith", "lost", "salvation", "great commission", "witness",
                          "evangelize", "missions", "outreach", "tell about jesus"],
        .servanthood:   ["serve", "servant", "ministry", "volunteer", "give", "generosity", "help others",
                          "compassion", "social justice", "mercy"],
        .grief:         ["grief", "loss", "mourning", "death", "passed away", "heartbreak", "sorrow",
                          "weeping", "comfort", "valley"],
        .healing:       ["healing", "healed", "health", "sick", "disease", "miracle healing", "by his stripes",
                          "divine healing", "restoration", "recovery"],
        .propheticWord: ["prophecy", "prophetic", "word of the lord", "vision", "dream", "thus saith",
                          "revelation", "discernment", "spiritual gifts"]
    ]

    // Scripture book name variations → canonical form
    private let bookAliases: [String: String] = [
        "gen": "Genesis", "ex": "Exodus", "lev": "Leviticus",
        "num": "Numbers", "deut": "Deuteronomy", "josh": "Joshua",
        "judg": "Judges", "ruth": "Ruth", "1 sam": "1 Samuel", "2 sam": "2 Samuel",
        "1 kings": "1 Kings", "2 kings": "2 Kings",
        "psa": "Psalms", "ps": "Psalms", "psalm": "Psalms",
        "prov": "Proverbs", "eccl": "Ecclesiastes", "isa": "Isaiah",
        "jer": "Jeremiah", "ezek": "Ezekiel", "dan": "Daniel",
        "hos": "Hosea", "joel": "Joel", "amos": "Amos",
        "matt": "Matthew", "mk": "Mark", "lk": "Luke",
        "jn": "John", "joh": "John", "acts": "Acts",
        "rom": "Romans", "1 cor": "1 Corinthians", "2 cor": "2 Corinthians",
        "gal": "Galatians", "eph": "Ephesians", "phil": "Philippians",
        "col": "Colossians", "1 thess": "1 Thessalonians", "2 thess": "2 Thessalonians",
        "1 tim": "1 Timothy", "2 tim": "2 Timothy", "tit": "Titus",
        "philem": "Philemon", "heb": "Hebrews", "jas": "James",
        "1 pet": "1 Peter", "2 pet": "2 Peter",
        "1 jn": "1 John", "2 jn": "2 John", "3 jn": "3 John",
        "jude": "Jude", "rev": "Revelation"
    ]

    // Spiritual quality signals (positive)
    private let spiritualQualitySignals = [
        "scripture", "verse", "bible", "prayer", "testimony", "worship", "grace",
        "faith", "hope", "love", "redemption", "mercy", "truth", "wisdom", "christ"
    ]

    // Anti-quality signals (addiction-risk or low-value content)
    private let lowQualitySignals = [
        "click to see", "you won't believe", "shocking truth", "secret revealed",
        "controversial", "viral", "share this now", "comment amen if", "type amen"
    ]

    private init() {}

    // MARK: - Primary API

    /// Extract topic tags from any text. Fast on-device.
    func extractTags(from text: String, input: String = "") async -> [String] {
        let combinedText = "\(text) \(input)"
        let tags = classifyTopics(combinedText)
        let scriptureRefs = detectScriptureReferences(in: combinedText)
        var result = tags.map { "\($0.cluster.rawValue.lowercased())" }
        result += scriptureRefs.map { "verse:\($0.displayString)" }
        return Array(Set(result))
    }

    /// Fast synchronous tag extraction (no async, no cloud) — for feed scoring
    func extractTagsFast(from text: String) async -> [String] {
        classifyTopics(text).map { $0.cluster.rawValue.lowercased() }
    }

    /// Full topic tag array with confidence scores
    func classifyText(_ text: String) -> [TopicTag] {
        classifyTopics(text)
    }

    /// Detect and normalize scripture references in text
    func detectScripture(in text: String) -> [ScriptureRef] {
        detectScriptureReferences(in: text)
    }

    /// Check if text is likely spiritual in nature (for routing decisions)
    func looksSpiritual(_ text: String) -> Bool {
        let lower = text.lowercased()
        return spiritualQualitySignals.contains(where: { lower.contains($0) })
    }

    /// On-device content quality score for feed ranking (0-1.0)
    func localQualityScore(text: String) async -> Double {
        let lower = text.lowercased()
        let wordCount = text.split(separator: " ").count

        // Length score: 15-150 words is ideal
        let lengthScore: Double = {
            switch wordCount {
            case 0...5:   return 0.20
            case 6...14:  return 0.50
            case 15...80: return 0.90
            case 81...150: return 0.85
            case 151...300: return 0.75
            default:      return 0.60
            }
        }()

        // Quality signals
        let positiveCount = spiritualQualitySignals.filter { lower.contains($0) }.count
        let negativeCount = lowQualitySignals.filter { lower.contains($0) }.count
        let qualityBonus = min(0.20, Double(positiveCount) * 0.04)
        let qualityPenalty = min(0.40, Double(negativeCount) * 0.15)

        // Scripture references boost quality
        let hasScripture = !detectScriptureReferences(in: text).isEmpty
        let scriptureBonus = hasScripture ? 0.10 : 0

        return max(0, min(1.0, lengthScore + qualityBonus - qualityPenalty + scriptureBonus))
    }

    /// Returns the best-matched cluster for a text (for diversity bucketing in feed)
    func primaryCluster(for text: String) -> SpiritualTopicCluster {
        classifyTopics(text).max(by: { $0.confidence < $1.confidence })?.cluster ?? .general
    }

    // MARK: - Topic Classification (on-device)

    private func classifyTopics(_ text: String) -> [TopicTag] {
        let lower = text.lowercased()
        var tags: [TopicTag] = []

        for (cluster, keywords) in clusterKeywords {
            let matchCount = keywords.filter { lower.contains($0) }.count
            guard matchCount > 0 else { continue }

            let confidence = min(1.0, Double(matchCount) / 3.0 * 0.8 + 0.20)
            tags.append(TopicTag(
                id: UUID().uuidString,
                label: cluster.rawValue,
                cluster: cluster,
                confidence: confidence,
                isScriptureRef: false,
                normalizedRef: nil
            ))
        }

        // Sort by confidence descending, limit to top 5
        return Array(tags.sorted { $0.confidence > $1.confidence }.prefix(5))
    }

    // MARK: - Scripture Reference Detection

    private func detectScriptureReferences(in text: String) -> [ScriptureRef] {
        var refs: [ScriptureRef] = []

        // Pattern: "John 3:16" or "Ps 23" or "1 Cor 13:1-13"
        let pattern = #"(?i)(1|2|3)?\s*([A-Za-z]+\.?)\s+(\d+)(?::(\d+)(?:-(\d+))?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return refs }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            // Extract book name
            var bookParts: [String] = []
            if let numRange = Range(match.range(at: 1), in: text) {
                bookParts.append(String(text[numRange]))
            }
            if let nameRange = Range(match.range(at: 2), in: text) {
                bookParts.append(String(text[nameRange]).lowercased().replacingOccurrences(of: ".", with: ""))
            }
            let rawBook = bookParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard let canonicalBook = resolveBook(rawBook) else { continue }

            // Extract chapter
            guard let chapterRange = Range(match.range(at: 3), in: text),
                  let chapter = Int(text[chapterRange]) else { continue }

            // Extract optional verse
            var verse: Int? = nil
            var endVerse: Int? = nil
            if let verseRange = Range(match.range(at: 4), in: text) {
                verse = Int(text[verseRange])
            }
            if let endVerseRange = Range(match.range(at: 5), in: text) {
                endVerse = Int(text[endVerseRange])
            }

            refs.append(ScriptureRef(book: canonicalBook, chapter: chapter, verse: verse, endVerse: endVerse))
        }

        return refs
    }

    private func resolveBook(_ raw: String) -> String? {
        let lower = raw.lowercased()
        // Direct alias match
        if let canonical = bookAliases[lower] { return canonical }
        // Partial match against aliases
        for (alias, canonical) in bookAliases {
            if lower.hasPrefix(alias) || alias.hasPrefix(lower) { return canonical }
        }
        return nil
    }
}

// MARK: - Topic Chip UI Component

import SwiftUI

struct TopicClusterChip: View {
    let cluster: SpiritualTopicCluster
    var small: Bool = false

    var body: some View {
        Text(cluster.rawValue)
            .font(.system(size: small ? 10 : 12, weight: .medium))
            .foregroundStyle(chipColor)
            .padding(.horizontal, small ? 7 : 10)
            .padding(.vertical, small ? 3 : 5)
            .background(
                Capsule()
                    .fill(chipColor.opacity(0.12))
                    .overlay(Capsule().stroke(chipColor.opacity(0.25), lineWidth: 0.5))
            )
    }

    private var chipColor: Color {
        let c = cluster.chipColor
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
