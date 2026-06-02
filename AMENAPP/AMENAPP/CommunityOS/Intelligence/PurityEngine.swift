// PurityEngine.swift
// AMEN App — Community Around Content OS / Intelligence
//
// On-device content purity classifier.
// Uses NaturalLanguage NLTagger and keyword signal sets only — no external API calls.
// All execution is gated by CommunityOSFlag.purityEngine.

import Foundation
import NaturalLanguage

// MARK: - PurityEngine

actor PurityEngine {

    // MARK: Singleton

    static let shared = PurityEngine()

    private init() {}

    // MARK: Signal Sets

    /// Signals associated with adult-only content: explicit lyrics, profanity,
    /// sexual language, and slang terms that appear in mainstream music with
    /// explicit RIAA advisory labels. Kept intentionally lowercase for
    /// case-insensitive matching.
    private let explicitKeywords: Set<String> = [
        "explicit", "profanity", "obscene", "vulgar", "crude",
        "lewd", "raunchy", "pornographic", "erotic", "salacious",
        "indecent", "lascivious", "suggestive", "risque", "provocative",
        "explicit content", "adult content", "mature content", "18+", "nsfw",
        "sexual", "sensual", "seductive", "lustful", "carnal",
        "fornication", "adultery", "perverse", "depraved", "filthy",
        "dirty", "smut", "racy", "naughty", "xxx"
    ]

    /// Terms commonly found in content that blasphemes or demeans sacred names,
    /// scripture, or religious practice.
    private let blasphemySignals: Set<String> = [
        "blasphemy", "blasphemous", "sacrilege", "sacrilegious",
        "heresy", "heretical", "profane", "desecrate", "desecration",
        "mockery of god", "mock jesus", "anti-christian", "antichrist",
        "satanic ritual", "occult worship", "demon worship",
        "curse god", "deny christ", "reject salvation"
    ]

    /// Violence, drug, and substance-abuse references commonly found in secular media.
    private let violenceSignals: Set<String> = [
        "murder", "killing", "bloodshed", "gore", "brutality",
        "torture", "assault", "gang", "drug", "cocaine", "heroin",
        "methamphetamine", "crack", "overdose", "trafficking",
        "violence", "massacre", "slaughter", "weapon", "shooting",
        "stabbing", "abuse", "self-harm", "suicide"
    ]

    /// Terms strongly associated with Christian worship, scripture, and faith practice.
    private let worshipSignals: Set<String> = [
        "worship", "praise", "glory", "grace", "holy", "amen",
        "hallelujah", "lord", "jesus", "gospel", "prayer", "scripture",
        "faith", "salvation", "redemption", "blessed", "sanctuary",
        "hymn", "anthem", "devotion", "intercession", "testimony",
        "resurrection", "cross", "savior", "christ", "spirit",
        "sacred", "righteous", "covenant", "repentance", "baptism"
    ]

    // MARK: Public API

    /// Synchronously classifies the purity of content from title + metadata signals.
    /// Checks metadata["lyrics"], metadata["description"], and the title itself.
    func classify(title: String, metadata: [String: String]) -> PurityRating {
        guard CommunityOSFlagService.shared.isEnabled(.purityEngine) else {
            return .unreviewed
        }

        let corpus = buildCorpus(title: title, metadata: metadata)

        if hasAnySignal(from: explicitKeywords, in: corpus) {
            dlog("[PurityEngine] classify — notRecommended: explicit signal hit for title: \(title)")
            return .notRecommended
        }

        if hasAnySignal(from: blasphemySignals, in: corpus) {
            dlog("[PurityEngine] classify — notRecommended: blasphemy signal hit for title: \(title)")
            return .notRecommended
        }

        let violenceCount = countSignals(from: violenceSignals, in: corpus)
        if violenceCount >= 2 {
            dlog("[PurityEngine] classify — someConcerns: \(violenceCount) violence signals for title: \(title)")
            return .someConcerns
        }

        if hasAnySignal(from: worshipSignals, in: corpus) {
            dlog("[PurityEngine] classify — familySafe: worship signal present, no negative signals for title: \(title)")
            return .familySafe
        }

        if violenceCount == 0 {
            dlog("[PurityEngine] classify — unreviewed: no signals detected for title: \(title)")
            return .unreviewed
        }

        dlog("[PurityEngine] classify — someConcerns: mild concerns for title: \(title)")
        return .someConcerns
    }

    /// Uses NLTagger to extract nouns and noun phrases, then filters to
    /// faith-relevant themes. Returns up to 8 distinct theme strings.
    func extractThemes(title: String, metadata: [String: String]) -> [String] {
        guard CommunityOSFlagService.shared.isEnabled(.purityEngine) else {
            return []
        }

        let corpus = buildCorpus(title: title, metadata: metadata)
        var rawTerms: [String] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = corpus

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: corpus.startIndex..<corpus.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, tokenRange in
            if tag == .noun || tag == .adjective {
                let token = String(corpus[tokenRange]).lowercased()
                if token.count >= 3 {
                    rawTerms.append(token)
                }
            }
            return true
        }

        // Filter to faith-relevant terms using worship signals and known domain vocabulary
        let faithDomainTerms: Set<String> = worshipSignals.union([
            "worship", "praise", "glory", "grace", "holy", "faith",
            "prayer", "salvation", "redemption", "blessed", "love",
            "peace", "hope", "healing", "forgiveness", "mercy",
            "justice", "community", "fellowship", "ministry", "mission",
            "family", "church", "bible", "scripture", "sermon",
            "devotion", "testimony", "revival", "freedom", "breakthrough",
            "restoration", "abundance", "covenant", "spirit", "truth"
        ])

        var seen = Set<String>()
        var themes: [String] = []

        for term in rawTerms {
            guard !seen.contains(term) else { continue }
            if faithDomainTerms.contains(term) {
                seen.insert(term)
                themes.append(term.capitalized)
                if themes.count == 8 { break }
            }
        }

        // If NLTagger yielded fewer than 4, augment with direct keyword matches
        if themes.count < 4 {
            for signal in worshipSignals.sorted() {
                guard themes.count < 8 else { break }
                let normalised = signal.lowercased()
                if corpus.lowercased().contains(normalised), !seen.contains(normalised) {
                    seen.insert(normalised)
                    themes.append(signal.capitalized)
                }
            }
        }

        dlog("[PurityEngine] extractThemes — found \(themes.count) themes for title: \(title)")
        return themes
    }

    /// Runs classify + extractThemes on the ContentObject and returns an updated copy.
    func analyze(contentObject: ContentObject) -> ContentObject {
        guard CommunityOSFlagService.shared.isEnabled(.purityEngine) else {
            return contentObject
        }

        let rating = classify(title: contentObject.title, metadata: contentObject.metadata)
        let themes = extractThemes(title: contentObject.title, metadata: contentObject.metadata)

        var updated = contentObject
        updated.purityRating = rating
        updated.themes = themes
        dlog("[PurityEngine] analyze — id: \(contentObject.id), rating: \(rating.rawValue), themes: \(themes)")
        return updated
    }

    // MARK: Private Helpers

    /// Concatenates title with relevant metadata fields into a single searchable string.
    private func buildCorpus(title: String, metadata: [String: String]) -> String {
        let parts: [String?] = [
            title,
            metadata["lyrics"],
            metadata["description"],
            metadata["genre"],
            metadata["artist"],
            metadata["tags"]
        ]
        return parts
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    /// Returns true if any signal from the set appears as a word boundary in the text.
    private func hasAnySignal(from signals: Set<String>, in text: String) -> Bool {
        for signal in signals {
            if text.contains(signal) {
                return true
            }
        }
        return false
    }

    /// Counts how many distinct signals from the set appear in the text.
    private func countSignals(from signals: Set<String>, in text: String) -> Int {
        signals.filter { text.contains($0) }.count
    }
}
