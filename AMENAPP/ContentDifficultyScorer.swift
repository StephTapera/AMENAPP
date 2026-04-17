// ContentDifficultyScorer.swift
// AMEN App — Accessibility Intelligence Layer (Phase 2)
//
// On-device content difficulty scoring using NLTokenizer + NLTagger.
// Measures: sentence length, uncommon vocabulary ratio, concept density,
// scripture density, and readability approximation.
//
// Zero API cost — fully on-device with NaturalLanguage framework.
// Returns ContentDifficultyScore with optional suggestedMode for UnderstandSheet.

import Foundation
import NaturalLanguage

@MainActor
final class ContentDifficultyScorer {

    static let shared = ContentDifficultyScorer()

    // MARK: - Configuration

    /// Threshold above which the "Understand" pill is shown
    static let displayThreshold: Double = 0.6

    /// Common English words (simplified stop-word list) — words below this level aren't "difficult"
    private let commonWords: Set<String> = {
        let words = [
            "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
            "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
            "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
            "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
            "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
            "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
            "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
            "than", "then", "now", "look", "only", "come", "its", "over", "think", "also",
            "back", "after", "use", "two", "how", "our", "work", "first", "well", "way",
            "even", "new", "want", "because", "any", "these", "give", "day", "most", "us",
            "is", "are", "was", "were", "been", "has", "had", "did", "does", "am",
            "god", "jesus", "lord", "christ", "church", "faith", "pray", "prayer", "love",
            "hope", "grace", "peace", "blessed", "amen", "bible", "holy", "spirit",
        ]
        return Set(words)
    }()

    private init() {}

    // MARK: - Public API

    /// Score content difficulty on a 0.0–1.0 scale.
    /// Designed to run synchronously on short-to-medium post content (~50–2000 chars).
    func score(text: String) -> ContentDifficultyScore {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 30 else {
            // Too short to meaningfully score
            return ContentDifficultyScore(
                score: 0.0,
                avgSentenceLength: 0.0,
                uncommonWordRatio: 0.0,
                conceptDensity: 0.0,
                scriptureDensity: 0.0,
                suggestedMode: nil
            )
        }

        let sentences = tokenizeSentences(trimmed)
        let words = tokenizeWords(trimmed)
        let sentenceScore = scoreSentenceComplexity(sentences: sentences, words: words)
        let vocabScore = scoreVocabularyDifficulty(words: words)
        let conceptScore = scoreConceptDensity(text: trimmed, words: words)
        let scriptureScore = scoreScriptureDensity(text: trimmed, words: words)

        // Weighted composite: sentence complexity and vocabulary matter most
        let overall = min(1.0, (
            sentenceScore * 0.30 +
            vocabScore * 0.35 +
            conceptScore * 0.20 +
            scriptureScore * 0.15
        ))

        let suggested = suggestMode(overall: overall, vocabScore: vocabScore, scriptureScore: scriptureScore)

        return ContentDifficultyScore(
            score: overall,
            avgSentenceLength: sentenceScore,
            uncommonWordRatio: vocabScore,
            conceptDensity: conceptScore,
            scriptureDensity: scriptureScore,
            suggestedMode: suggested
        )
    }

    // MARK: - Tokenization

    private func tokenizeSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }

    private func tokenizeWords(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if word.count >= 2 {
                words.append(word)
            }
            return true
        }
        return words
    }

    // MARK: - Scoring Components

    /// Sentence complexity: avg words per sentence, normalized.
    /// <10 words/sentence = easy (0.0), >25 = hard (1.0)
    private func scoreSentenceComplexity(sentences: [String], words: [String]) -> Double {
        guard !sentences.isEmpty else { return 0.0 }
        let avgWordsPerSentence = Double(words.count) / Double(sentences.count)
        // Normalize: 10 words = 0.0, 25 words = 1.0
        return min(1.0, max(0.0, (avgWordsPerSentence - 10.0) / 15.0))
    }

    /// Vocabulary difficulty: ratio of words NOT in the common-words list.
    /// Also factors in average word length (longer words = harder).
    private func scoreVocabularyDifficulty(words: [String]) -> Double {
        guard !words.isEmpty else { return 0.0 }

        let uncommonCount = words.filter { !commonWords.contains($0) }.count
        let uncommonRatio = Double(uncommonCount) / Double(words.count)

        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        // Normalize length: 4 chars = 0.0, 8+ chars = 1.0
        let lengthScore = min(1.0, max(0.0, (avgWordLength - 4.0) / 4.0))

        return min(1.0, uncommonRatio * 0.7 + lengthScore * 0.3)
    }

    /// Concept density: theological/abstract term frequency.
    /// Uses NLTagger to detect nouns, then checks for multi-syllable patterns.
    private func scoreConceptDensity(text: String, words: [String]) -> Double {
        guard !words.isEmpty else { return 0.0 }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var nounCount = 0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, _ in
            if tag == .noun {
                nounCount += 1
            }
            return true
        }

        let nounRatio = Double(nounCount) / Double(words.count)
        // High noun density (>40%) suggests conceptually dense text
        return min(1.0, max(0.0, (nounRatio - 0.2) / 0.3))
    }

    /// Scripture density: how many verse references appear relative to content length.
    /// High density can make text harder for newcomers to parse.
    private func scoreScriptureDensity(text: String, words: [String]) -> Double {
        guard !words.isEmpty else { return 0.0 }

        let versePattern = #"(?:\d\s+)?[A-Za-z]+\s+\d+:\d+(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: versePattern) else { return 0.0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        let refsPerHundredWords = Double(matches.count) / (Double(words.count) / 100.0)
        // Normalize: 0 refs = 0.0, 3+ refs per 100 words = 1.0
        return min(1.0, max(0.0, refsPerHundredWords / 3.0))
    }

    // MARK: - Mode Suggestion

    private func suggestMode(overall: Double, vocabScore: Double, scriptureScore: Double) -> ReadabilityMode? {
        guard overall >= Self.displayThreshold else { return nil }

        if vocabScore > 0.7 {
            return .simplify  // Complex vocabulary → simplify
        } else if scriptureScore > 0.6 {
            return .expandContext  // Scripture-heavy → explain context
        } else if overall > 0.8 {
            return .summarize  // Very complex overall → summarize
        } else {
            return .explain  // Default for moderately complex content
        }
    }
}
