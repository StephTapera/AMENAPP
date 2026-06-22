// MediaIntelligenceEngine.swift
// AMEN App — Community Around Content OS / Intelligence
//
// Extracts topics, community layers, and theme tag clouds from ContentObject metadata.
// All execution is gated by CommunityOSFlag.purityEngine (shared Intelligence gate).
// No external API calls — purely on-device signal mapping.

import Foundation

// MARK: - MediaIntelligenceEngine

actor MediaIntelligenceEngine {

    // MARK: Singleton

    static let shared = MediaIntelligenceEngine()

    private init() {}

    // MARK: Worship Signals (mirrored from PurityEngine domain vocabulary)

    private let worshipTerms: Set<String> = [
        "worship", "praise", "glory", "grace", "holy", "amen",
        "hallelujah", "lord", "jesus", "gospel", "prayer", "scripture",
        "faith", "salvation", "redemption", "blessed", "sanctuary",
        "hymn", "anthem", "devotion", "intercession", "testimony",
        "resurrection", "cross", "savior", "christ", "spirit",
        "sacred", "righteous", "covenant", "repentance", "baptism"
    ]

    // MARK: - Topic Extraction

    /// Maps themes and content kind to CommunityAffinityTopic values.
    /// Combines kind-based defaults with signal matching from metadata and existing themes.
    func extractTopics(from contentObject: ContentObject) -> [CommunityAffinityTopic] {
        var topics = Set<CommunityAffinityTopic>()

        // Kind-based primary mapping
        switch contentObject.kind {
        case .sermon, .bibleVerse, .course:
            topics.insert(.theology)
        case .podcast, .article:
            topics.insert(.discipleship)
        case .book:
            topics.insert(.theology)
            topics.insert(.discipleship)
        case .prayerRequest:
            topics.insert(.prayer)
        case .testimony:
            topics.insert(.discipleship)
        case .event:
            topics.insert(.missions)
        case .song, .video:
            break // Determined by metadata signals below
        case .userPost:
            break
        }

        // Genre-based topic mapping
        let genre = (contentObject.metadata["genre"] ?? "").lowercased()
        if genre.contains("christian") || genre.contains("gospel") || genre.contains("worship") {
            topics.insert(.worship)
        }
        if genre.contains("contemporary christian") || genre.contains("ccm") {
            topics.insert(.worship)
            topics.insert(.discipleship)
        }

        // Theme-based mapping
        for theme in contentObject.themes.map({ $0.lowercased() }) {
            switch theme {
            case "worship", "praise", "glory", "hallelujah", "hymn", "anthem":
                topics.insert(.worship)
            case "prayer", "intercession", "devotion":
                topics.insert(.prayer)
            case "leadership", "vision", "authority":
                topics.insert(.leadership)
            case "discipleship", "faith", "growth", "scripture", "bible":
                topics.insert(.discipleship)
            case "recovery", "healing", "addiction", "freedom", "breakthrough", "restoration":
                topics.insert(.recovery)
            case "marriage", "relationship", "covenant", "wedding":
                topics.insert(.marriage)
            case "fatherhood", "father", "dad", "parenting":
                topics.insert(.fatherhood)
            case "motherhood", "mother", "mom":
                topics.insert(.motherhood)
            case "youth", "teens", "children", "kids", "student":
                topics.insert(.youth)
            case "missions", "evangelism", "outreach", "global":
                topics.insert(.missions)
            case "apologetics", "theology", "doctrine", "truth", "evidence":
                topics.insert(.apologetics)
            case "sermon", "teaching", "study":
                topics.insert(.theology)
            default:
                break
            }
        }

        // Title signal scan
        let titleLower = contentObject.title.lowercased()
        if titleLower.contains("worship") || titleLower.contains("praise") {
            topics.insert(.worship)
        }
        if titleLower.contains("prayer") || titleLower.contains("pray") {
            topics.insert(.prayer)
        }
        if titleLower.contains("leader") || titleLower.contains("vision") {
            topics.insert(.leadership)
        }
        if titleLower.contains("recover") || titleLower.contains("healing") || titleLower.contains("freedom") {
            topics.insert(.recovery)
        }
        if titleLower.contains("marriage") || titleLower.contains("wedding") {
            topics.insert(.marriage)
        }
        if titleLower.contains("youth") || titleLower.contains("teen") || titleLower.contains("kids") {
            topics.insert(.youth)
        }
        if titleLower.contains("mission") || titleLower.contains("evangelis") {
            topics.insert(.missions)
        }
        if titleLower.contains("apologetic") {
            topics.insert(.apologetics)
        }

        let result = Array(topics)
        dlog("[MediaIntelligenceEngine] extractTopics — \(result.count) topics for id: \(contentObject.id)")
        return result
    }

    // MARK: - Community Layer Suggestion

    /// Returns the appropriate CommunityLayer set for this content.
    /// Starts from kind defaults, adds .reflection for worship-signal content,
    /// and adds .study for sermon/book/podcast/course kinds.
    func suggestCommunityLayers(for contentObject: ContentObject) -> [CommunityLayer] {
        var layers = Set<CommunityLayer>(contentObject.kind.defaultCommunityLayers)

        // Add .reflection if the content carries worship signals
        let hasWorshipSignal = containsWorshipSignal(in: contentObject)
        if hasWorshipSignal {
            layers.insert(.reflection)
        }

        // Add .study for teaching-oriented content
        switch contentObject.kind {
        case .sermon, .book, .podcast, .course, .bibleVerse, .article:
            layers.insert(.study)
        default:
            break
        }

        // Preserve kind-default ordering, then append any newly inserted layers
        var ordered = contentObject.kind.defaultCommunityLayers
        for layer in CommunityLayer.allCases {
            if layers.contains(layer), !ordered.contains(layer) {
                ordered.append(layer)
            }
        }

        dlog("[MediaIntelligenceEngine] suggestCommunityLayers — \(ordered.count) layers for id: \(contentObject.id)")
        return ordered
    }

    // MARK: - Theme Tag Cloud

    /// Deduplicates and merges purity themes from the content object with
    /// relevant metadata signals. Returns the top 6 distinct tags.
    func buildThemeTagCloud(for contentObject: ContentObject) -> [String] {
        var seen = Set<String>()
        var tags: [String] = []

        // Start with existing themes (already scored by PurityEngine)
        for theme in contentObject.themes {
            let key = theme.lowercased()
            if seen.insert(key).inserted {
                tags.append(theme)
            }
        }

        // Augment from metadata fields
        let metadataSourceKeys = ["genre", "tags", "category", "topic", "subject"]
        for key in metadataSourceKeys {
            guard let value = contentObject.metadata[key], !value.isEmpty else { continue }
            // Split comma-separated tag lists
            let parts = value.components(separatedBy: CharacterSet(charactersIn: ",;|"))
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                let normalised = trimmed.lowercased()
                guard !normalised.isEmpty, normalised.count >= 3 else { continue }
                if seen.insert(normalised).inserted {
                    tags.append(trimmed.capitalized)
                }
            }
        }

        // Augment from kind display name if not already present
        let kindTag = contentObject.kind.displayName
        if seen.insert(kindTag.lowercased()).inserted {
            tags.append(kindTag)
        }

        let result = Array(tags.prefix(6))
        dlog("[MediaIntelligenceEngine] buildThemeTagCloud — \(result.count) tags for id: \(contentObject.id)")
        return result
    }

    // MARK: Private Helpers

    /// Returns true if the content's title, themes, or metadata contain worship-domain terms.
    private func containsWorshipSignal(in contentObject: ContentObject) -> Bool {
        let corpus = ([contentObject.title]
            + contentObject.themes
            + contentObject.metadata.values)
            .joined(separator: " ")
            .lowercased()

        return worshipTerms.contains { corpus.contains($0) }
    }
}
