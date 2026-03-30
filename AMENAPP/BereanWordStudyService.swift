//
//  BereanWordStudyService.swift
//  AMENAPP
//
//  Deep word study: plain meaning → Greek/Hebrew → first biblical usage → cross-scripture usage
//

import Foundation
import Combine

// MARK: - Shared Scripture Reference Model

/// A single scripture reference with theme annotation. Defined here; used across Berean engines.
struct ScriptureRef: Identifiable, Codable {
    var id: String = UUID().uuidString
    let reference: String   // e.g. "John 3:16"
    let text: String        // verse text
    let theme: String       // brief thematic note
}

// MARK: - Word Study Models

struct WordStudyResult: Identifiable {
    let id = UUID()
    let word: String
    let plainMeaning: String
    let biblicalMeaning: String
    let originalLanguage: OriginalLanguage?
    let firstBiblicalUsage: String?
    let usageAcrossScripture: [String]
    let crossReferences: [ScriptureRef]
    let applicationPrompt: String

    struct OriginalLanguage {
        let language: String
        let originalWord: String
        let transliteration: String
        let definitions: [String]
        let distinctions: String?
    }
}

// MARK: - Quick-Lookup Dictionary Entry

private struct QuickLookupEntry {
    let plain: String
    let biblical: String
}

// MARK: - Service

@MainActor
final class BereanWordStudyService: ObservableObject {

    static let shared = BereanWordStudyService()

    @Published var isStudying = false
    @Published var currentResult: WordStudyResult?
    @Published var error: String?

    private init() {}

    // MARK: - Public API

    /// Perform a full, AI-powered deep word study on the given word or phrase.
    func studyWord(_ word: String, context: String? = nil) async {
        guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isStudying = true
        error = nil
        currentResult = nil

        dlog("BereanWordStudyService: studying word '\(word)'")

        let prompt = buildStudyPrompt(word: word, context: context)

        do {
            let response = try await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
            currentResult = parseStudyResponse(response, word: word)
            dlog("BereanWordStudyService: study complete for '\(word)'")
        } catch {
            self.error = error.localizedDescription
            dlog("BereanWordStudyService.studyWord error: \(error.localizedDescription)")
        }

        isStudying = false
    }

    /// Quick lookup from local dictionary — no AI call, instant.
    func quickLookup(_ word: String) -> (plain: String, biblical: String)? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let entry = quickLookupDictionary[key] else { return nil }
        return (entry.plain, entry.biblical)
    }

    // MARK: - Prompt Construction

    private func buildStudyPrompt(word: String, context: String?) -> String {
        var prompt = """
        Perform a deep biblical word study on the word or phrase: "\(word)"
        """

        if let context, !context.isEmpty {
            prompt += "\n\nContext (surrounding verse or passage): \(context)"
        }

        prompt += """


        Provide a structured response using these exact section labels (one per line):

        PLAIN_MEANING: (a clear, plain-English definition of the word)
        BIBLICAL_MEANING: (what this word means specifically in a biblical/theological context)
        ORIGINAL_LANGUAGE: (Greek or Hebrew; write "none" if not applicable)
        ORIGINAL_WORD: (the actual Greek or Hebrew word; write "none" if not applicable)
        TRANSLITERATION: (phonetic spelling; write "none" if not applicable)
        DEFINITIONS: (2-4 shades of meaning, separated by semicolons)
        DISTINCTIONS: (any important distinctions from similar words, e.g. agape vs phileo; write "none" if not applicable)
        FIRST_USAGE: (the first or most significant biblical occurrence, format: "Book chapter:verse — quote")
        USAGE_1: (a key scriptural usage, format: "Book chapter:verse — brief note")
        USAGE_2: (another key scriptural usage)
        USAGE_3: (another key scriptural usage)
        CROSS_REF_1: (format: "REFERENCE | verse text | thematic note")
        CROSS_REF_2: (format: "REFERENCE | verse text | thematic note")
        CROSS_REF_3: (format: "REFERENCE | verse text | thematic note")
        APPLICATION: (a practical prompt for how the user can apply this word's meaning to their life today)

        Be precise and scholarly, but write the APPLICATION in plain, accessible language.
        Do not invent Bible quotes — use accurate references only.
        """

        return prompt
    }

    // MARK: - Response Parsing

    private func parseStudyResponse(_ response: String, word: String) -> WordStudyResult {
        func extract(_ label: String) -> String {
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(label):") {
                    return trimmed
                        .dropFirst("\(label):".count)
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            return ""
        }

        let plainMeaning      = extract("PLAIN_MEANING")
        let biblicalMeaning   = extract("BIBLICAL_MEANING")
        let originalLangStr   = extract("ORIGINAL_LANGUAGE").lowercased()
        let originalWordStr   = extract("ORIGINAL_WORD")
        let transliteration   = extract("TRANSLITERATION")
        let definitionsStr    = extract("DEFINITIONS")
        let distinctionsStr   = extract("DISTINCTIONS")
        let firstUsage        = extract("FIRST_USAGE")
        let applicationPrompt = extract("APPLICATION")

        // Usage lines
        var usages: [String] = []
        for i in 1...3 {
            let u = extract("USAGE_\(i)")
            if !u.isEmpty && u != "none" { usages.append(u) }
        }

        // Cross-references
        var crossRefs: [ScriptureRef] = []
        for i in 1...3 {
            let raw = extract("CROSS_REF_\(i)")
            let parts = raw.components(separatedBy: " | ")
            if parts.count >= 3 {
                crossRefs.append(ScriptureRef(
                    reference: parts[0].trimmingCharacters(in: .whitespaces),
                    text: parts[1].trimmingCharacters(in: .whitespaces),
                    theme: parts[2].trimmingCharacters(in: .whitespaces)
                ))
            }
        }

        // Original language block
        var originalLanguage: WordStudyResult.OriginalLanguage? = nil
        let langNormalized = originalLangStr.trimmingCharacters(in: .whitespaces)
        if langNormalized != "none" && !langNormalized.isEmpty
            && originalWordStr != "none" && !originalWordStr.isEmpty {
            let definitions = definitionsStr
                .components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let distinctions = (distinctionsStr == "none" || distinctionsStr.isEmpty) ? nil : distinctionsStr

            originalLanguage = WordStudyResult.OriginalLanguage(
                language: originalLangStr.capitalized,
                originalWord: originalWordStr,
                transliteration: transliteration == "none" ? "" : transliteration,
                definitions: definitions,
                distinctions: distinctions
            )
        }

        return WordStudyResult(
            word: word,
            plainMeaning: plainMeaning.isEmpty ? "See full study below." : plainMeaning,
            biblicalMeaning: biblicalMeaning.isEmpty ? "See full study below." : biblicalMeaning,
            originalLanguage: originalLanguage,
            firstBiblicalUsage: (firstUsage.isEmpty || firstUsage == "none") ? nil : firstUsage,
            usageAcrossScripture: usages,
            crossReferences: crossRefs,
            applicationPrompt: applicationPrompt.isEmpty ? "Reflect on how this word applies to your walk today." : applicationPrompt
        )
    }

    // MARK: - Quick Lookup Dictionary (20 common biblical terms)

    private let quickLookupDictionary: [String: QuickLookupEntry] = [
        "grace": QuickLookupEntry(
            plain: "Unearned favor or goodwill given freely to someone.",
            biblical: "God's unmerited favor toward humanity, the basis of salvation and daily sustenance in the Christian life."
        ),
        "faith": QuickLookupEntry(
            plain: "Firm belief or trust in someone or something without requiring proof.",
            biblical: "Confident trust in God and His promises; the assurance of things hoped for and conviction of things unseen (Hebrews 11:1)."
        ),
        "love": QuickLookupEntry(
            plain: "Deep affection or care for another person.",
            biblical: "In Scripture, love (agape) is self-sacrificial, covenantal commitment — not merely feeling. God is love (1 John 4:8)."
        ),
        "hope": QuickLookupEntry(
            plain: "A desire for something accompanied by expectation of its fulfillment.",
            biblical: "Confident expectation rooted in God's character and promises — not wishful thinking but assured anticipation (Romans 5:5)."
        ),
        "peace": QuickLookupEntry(
            plain: "Freedom from disturbance; quietness and calm.",
            biblical: "Shalom — wholeness, completeness, and right relationship with God. The peace of Christ surpasses understanding (Philippians 4:7)."
        ),
        "righteousness": QuickLookupEntry(
            plain: "Morally right behavior; the quality of being just or virtuous.",
            biblical: "Right standing before God — both imputed (credited through Christ) and imparted (lived out by the Spirit)."
        ),
        "sanctification": QuickLookupEntry(
            plain: "The process of making something holy or set apart.",
            biblical: "The ongoing work of the Holy Spirit conforming believers to Christ's image after justification; being set apart for God's purposes."
        ),
        "covenant": QuickLookupEntry(
            plain: "A binding agreement or contract between two parties.",
            biblical: "A solemn, binding commitment God initiates with His people — carrying deeper obligation than a contract, involving loyalty and faithfulness."
        ),
        "mercy": QuickLookupEntry(
            plain: "Compassion or forgiveness shown toward someone you have power over.",
            biblical: "God's steadfast lovingkindness (hesed) — withholding deserved punishment and showing active compassion to the undeserving."
        ),
        "glory": QuickLookupEntry(
            plain: "High renown, honor, or praise.",
            biblical: "The manifest presence and weighty splendor of God (kavod/doxa) — everything that reveals who He truly is."
        ),
        "truth": QuickLookupEntry(
            plain: "That which is in accordance with fact or reality.",
            biblical: "In Scripture, truth is relational and personal — Jesus is 'the Truth' (John 14:6). It is faithfulness, reliability, and conformity to God's nature."
        ),
        "spirit": QuickLookupEntry(
            plain: "The non-physical part of a person; also breath or wind.",
            biblical: "Ruach/Pneuma — breath, wind, spirit. The Holy Spirit is the third person of the Trinity, the indwelling presence of God in believers."
        ),
        "wisdom": QuickLookupEntry(
            plain: "The ability to make sound judgments and decisions based on knowledge and experience.",
            biblical: "Skill in living rightly before God; begins with the fear of the Lord (Proverbs 9:10). Personified in Proverbs and embodied in Christ (1 Corinthians 1:24)."
        ),
        "prayer": QuickLookupEntry(
            plain: "A solemn request or expression of thanks addressed to God.",
            biblical: "Communion and dialogue with God — including adoration, confession, thanksgiving, and supplication. The believer's lifeline of dependence on God."
        ),
        "worship": QuickLookupEntry(
            plain: "Reverence or devotion expressed to a deity or something of great worth.",
            biblical: "Ascribing worth to God with all of life — not merely singing. True worship is in spirit and truth (John 4:24)."
        ),
        "redemption": QuickLookupEntry(
            plain: "The action of regaining or gaining possession of something in exchange for payment.",
            biblical: "God's rescue of humanity from sin's bondage through the blood of Christ — a purchase price paid on our behalf (Ephesians 1:7)."
        ),
        "forgiveness": QuickLookupEntry(
            plain: "The act of pardoning someone for a wrong they have done.",
            biblical: "The releasing of a debt or offense — God's complete cancellation of sin's record through Christ's atoning sacrifice."
        ),
        "sin": QuickLookupEntry(
            plain: "An immoral act considered to be a transgression against divine law.",
            biblical: "Missing the mark (hamartia); rebellion against God's nature and law. Both individual acts and a power that enslaves humanity apart from Christ."
        ),
        "salvation": QuickLookupEntry(
            plain: "Preservation or deliverance from harm, ruin, or loss.",
            biblical: "God's complete rescue of humanity — past (justification), present (sanctification), and future (glorification) — from sin, death, and God's wrath."
        ),
        "obedience": QuickLookupEntry(
            plain: "Compliance with someone's authority, commands, or wishes.",
            biblical: "Faithful, loving response to God's revealed will — not mere rule-following, but the fruit of genuine faith and a transformed heart (John 14:15)."
        )
    ]
}
