//
//  BereanCitationVerifier.swift
//  AMENAPP
//
//  Post-generation citation verification pipeline.
//  Extracts all verse references from Berean's response, fetches each from
//  YouVersion API, and verifies the quoted text actually matches the real verse.
//  Strips or flags any hallucinated references before showing to user.
//
//  Principle: "Trust but verify" — the AI may cite correctly, but we confirm.
//

import Foundation

// MARK: - Verification Result

struct CitationVerificationResult {
    let originalResponse: String
    let verifiedResponse: String
    let verifiedCitations: [VerifiedCitation]
    let removedCitations: [RemovedCitation]
    let verificationScore: Double  // 0.0–1.0: ratio of verified citations

    var allCitationsVerified: Bool { removedCitations.isEmpty }
}

struct VerifiedCitation: Identifiable {
    let id: String
    let reference: String          // e.g., "John 3:16"
    let claimedText: String        // what the AI said the verse says
    let actualText: String         // what the verse actually says
    let similarityScore: Double    // 0.0–1.0 cosine-ish similarity
    let isAccurate: Bool           // similarity >= threshold
}

struct RemovedCitation: Identifiable {
    let id: String
    let reference: String
    let reason: RemovalReason

    enum RemovalReason: String {
        case verseNotFound = "verse_not_found"          // Reference doesn't exist
        case textMismatch = "text_mismatch"             // Quoted text doesn't match real verse
        case malformedReference = "malformed_reference"  // Can't parse the reference
    }
}

// MARK: - Citation Verifier

@MainActor
final class BereanCitationVerifier {
    static let shared = BereanCitationVerifier()

    private let youVersion = YouVersionBibleService.shared
    private let similarityThreshold: Double = 0.4  // Lenient — paraphrasing is OK

    private init() {}

    // MARK: - Main Verification

    /// Verify all citations in a Berean response.
    /// Returns the response with unverified citations flagged.
    func verify(response: String, scripture: [ScripturePassage]) async -> CitationVerificationResult {
        // 1. Extract all verse references from the response text
        let extractedRefs = extractAllReferences(from: response)

        // 2. Combine with structured scripture passages
        var allRefs = Set(extractedRefs)
        for passage in scripture {
            let ref = "\(passage.book) \(passage.chapter):\(passage.verses)"
            allRefs.insert(ref)
        }

        guard !allRefs.isEmpty else {
            return CitationVerificationResult(
                originalResponse: response,
                verifiedResponse: response,
                verifiedCitations: [],
                removedCitations: [],
                verificationScore: 1.0
            )
        }

        // 3. Verify each citation
        var verified: [VerifiedCitation] = []
        var removed: [RemovedCitation] = []

        await withTaskGroup(of: (String, VerifiedCitation?, RemovedCitation?).self) { group in
            for ref in allRefs {
                group.addTask {
                    await self.verifySingleCitation(reference: ref, responseText: response)
                }
            }

            for await (_, verifiedCitation, removedCitation) in group {
                if let v = verifiedCitation {
                    verified.append(v)
                }
                if let r = removedCitation {
                    removed.append(r)
                }
            }
        }

        // 4. Build verified response (annotate unverified citations)
        let verifiedResponse = annotateResponse(
            response: response,
            removed: removed
        )

        let total = verified.count + removed.count
        let score = total > 0 ? Double(verified.count) / Double(total) : 1.0

        return CitationVerificationResult(
            originalResponse: response,
            verifiedResponse: verifiedResponse,
            verifiedCitations: verified,
            removedCitations: removed,
            verificationScore: score
        )
    }

    // MARK: - Single Citation Verification

    private func verifySingleCitation(
        reference: String,
        responseText: String
    ) async -> (String, VerifiedCitation?, RemovedCitation?) {
        // Try to fetch the actual verse
        do {
            let passage = try await youVersion.fetchVerse(reference: reference)
            let actualText = passage.text
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract what the AI claimed this verse says (text near the reference)
            let claimedText = extractClaimedText(for: reference, from: responseText)

            // Calculate similarity
            let similarity = textSimilarity(claimedText, actualText)
            let isAccurate = similarity >= similarityThreshold || claimedText.isEmpty

            let verified = VerifiedCitation(
                id: UUID().uuidString,
                reference: reference,
                claimedText: claimedText,
                actualText: actualText,
                similarityScore: similarity,
                isAccurate: isAccurate
            )

            if isAccurate {
                return (reference, verified, nil)
            } else {
                let removed = RemovedCitation(
                    id: UUID().uuidString,
                    reference: reference,
                    reason: .textMismatch
                )
                return (reference, nil, removed)
            }
        } catch {
            // Verse not found — might be a hallucinated reference
            let removed = RemovedCitation(
                id: UUID().uuidString,
                reference: reference,
                reason: .verseNotFound
            )
            return (reference, nil, removed)
        }
    }

    // MARK: - Reference Extraction

    /// Extract all Bible references from text (e.g., "John 3:16", "1 Corinthians 13:4-7")
    private func extractAllReferences(from text: String) -> [String] {
        var references: [String] = []

        // Pattern: Book Chapter:Verse(-Verse)
        let pattern = "([1-3]?\\s?[A-Z][a-z]+(?:\\s[A-Z][a-z]+)?)\\s+(\\d+):(\\d+(?:-\\d+)?)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = text as NSString
        let matches = regex.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )

        for match in matches {
            let fullMatch = nsString.substring(with: match.range)
                .trimmingCharacters(in: .whitespaces)
            if !references.contains(fullMatch) {
                references.append(fullMatch)
            }
        }

        return references
    }

    // MARK: - Claimed Text Extraction

    /// Extract the text the AI claimed a verse says (usually quoted near the reference)
    private func extractClaimedText(for reference: String, from response: String) -> String {
        // Look for quoted text near the reference
        guard let refRange = response.range(of: reference) else { return "" }

        // Search within 500 characters around the reference
        let startIdx = response.index(
            refRange.lowerBound,
            offsetBy: -250,
            limitedBy: response.startIndex
        ) ?? response.startIndex
        let endIdx = response.index(
            refRange.upperBound,
            offsetBy: 250,
            limitedBy: response.endIndex
        ) ?? response.endIndex

        let context = String(response[startIdx..<endIdx])

        // Extract quoted text (between " " or " ")
        let quotePatterns = [
            "\"([^\"]+)\"",        // standard quotes
            "\u{201C}([^\u{201D}]+)\u{201D}",  // smart quotes
        ]

        for pattern in quotePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: context,
                   range: NSRange(context.startIndex..., in: context)
               ) {
                let nsContext = context as NSString
                if match.numberOfRanges >= 2 {
                    return nsContext.substring(with: match.range(at: 1))
                }
            }
        }

        return ""
    }

    // MARK: - Text Similarity

    /// Simple word-overlap similarity (Jaccard-like)
    private func textSimilarity(_ text1: String, _ text2: String) -> Double {
        guard !text1.isEmpty, !text2.isEmpty else { return 0.0 }

        let words1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) })
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) })

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return union > 0 ? Double(intersection) / Double(union) : 0.0
    }

    // MARK: - Response Annotation

    /// Annotate unverified citations in the response
    private func annotateResponse(response: String, removed: [RemovedCitation]) -> String {
        guard !removed.isEmpty else { return response }

        var annotated = response
        for citation in removed {
            // Add a note after unverified references
            let note: String
            switch citation.reason {
            case .verseNotFound:
                note = " [reference could not be verified]"
            case .textMismatch:
                note = " [quoted text may not match this verse exactly]"
            case .malformedReference:
                note = " [reference format unclear]"
            }
            annotated = annotated.replacingOccurrences(
                of: citation.reference,
                with: citation.reference + note
            )
        }

        return annotated
    }
}

// MARK: - BereanAnswerEngine Integration

extension BereanAnswerEngine {

    /// Verify and annotate an answer's citations post-generation
    func verifyAnswer(_ answer: BereanAnswer) async -> BereanAnswer {
        let verifier = BereanCitationVerifier.shared

        let result = await verifier.verify(
            response: answer.response,
            scripture: answer.scripture
        )

        // If all citations verified, return as-is
        if result.allCitationsVerified {
            return answer
        }

        // Return answer with annotated response
        print("⚠️ BereanEngine: \(result.removedCitations.count) citation(s) could not be verified")

        return BereanAnswer(
            id: answer.id,
            query: answer.query,
            response: result.verifiedResponse,
            scripture: answer.scripture,
            historicalContext: answer.historicalContext,
            interpretations: answer.interpretations,
            mode: answer.mode,
            timestamp: answer.timestamp,
            hasCitations: answer.hasCitations,
            responseType: answer.responseType
        )
    }
}
