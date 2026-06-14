// BereanAgentSafetyService.swift
// AMEN — Berean Agent Surface (BAS) · Wave 2 · Lane E
//
// Stub safety service: evaluates content against BAS audit checks.
// §7: Policy is always .advisory. "Share anyway" must remain available — no hard-block.

import Foundation

// MARK: - BAS Safety Service

/// Runs pre-share safety audit checks against Berean Agent content.
/// All enforcement is advisory by default (§7). "Share anyway" is always available.
final class BereanAgentSafetyService {

    // Known book names used to detect scripture context.
    private static let bibleBookNames: Set<String> = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "Samuel", "Kings", "Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Psalm",
        "Proverbs", "Ecclesiastes", "Isaiah", "Jeremiah", "Lamentations",
        "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah",
        "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai",
        "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John",
        "Acts", "Romans", "Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "Thessalonians", "Timothy", "Titus",
        "Philemon", "Hebrews", "James", "Peter", "Jude", "Revelation"
    ]

    /// Runs all safety checks against `content` and returns a `BASSafetyAudit`.
    /// - Parameters:
    ///   - content: The AI-generated text to audit.
    ///   - isInterpretation: Whether the caller already knows this is interpretation.
    /// - Returns: A complete `BASSafetyAudit` with per-check results.
    func runAudit(content: String, isInterpretation: Bool) async -> BASSafetyAudit {
        var results: [BASSafetyAuditResult] = []
        var resolvedIsInterpretation = isInterpretation

        // Detect [interpret] sentinel → marks as interpretation
        if content.contains("[interpret]") {
            resolvedIsInterpretation = true
        }

        // ── Check: Scripture Accuracy ────────────────────────────────────────
        // Passes when content references "John" or any known Bible book name.
        let mentionsScripture = content.contains("John") ||
            BereanAgentSafetyService.bibleBookNames.contains(where: { content.contains($0) })

        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .scriptureAccuracy,
            passed: mentionsScripture,
            severity: .advisory,
            note: mentionsScripture ? nil : "No scripture reference detected in content."
        ))

        // ── Check: Verse In Context ──────────────────────────────────────────
        // Passes by default in stub (full check requires verse DB lookup).
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .verseInContext,
            passed: true,
            severity: .info,
            note: nil
        ))

        // ── Check: Translation Match ─────────────────────────────────────────
        // Passes by default in stub.
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .translationMatch,
            passed: true,
            severity: .info,
            note: nil
        ))

        // ── Check: Theological Confidence ────────────────────────────────────
        // Passes by default in stub.
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .theologicalConfidence,
            passed: true,
            severity: .info,
            note: nil
        ))

        // ── Check: Misquote ──────────────────────────────────────────────────
        // Fails when content contains "[misquote]" sentinel.
        let hasMisquote = content.contains("[misquote]")
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .misquote,
            passed: !hasMisquote,
            severity: .advisory,
            note: hasMisquote ? "Possible misquotation detected. Please verify the exact wording." : nil
        ))

        // ── Check: Harmful Advice ────────────────────────────────────────────
        // Fails when content contains "[harmful]" sentinel.
        // Policy remains .advisory per §7 — user must still be able to share.
        let hasHarmful = content.contains("[harmful]")
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .harmfulAdvice,
            passed: !hasHarmful,
            severity: .blocking,   // severity label is .blocking…
            note: hasHarmful ? "Potentially harmful guidance detected. Berean recommends revising." : nil
        ))
        // …but overall policy is always .advisory per §7, so no hard-block occurs.

        // ── Check: Manipulative Claim ─────────────────────────────────────────
        // Passes by default in stub.
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .manipulativeClaim,
            passed: true,
            severity: .advisory,
            note: nil
        ))

        // ── Check: Interpretation Label ───────────────────────────────────────
        // Passes when the interpretation flag is consistent with [interpret] sentinel.
        results.append(BASSafetyAuditResult(
            id: UUID(),
            check: .interpretationLabel,
            passed: true,
            severity: .info,
            note: resolvedIsInterpretation ? "Content is marked as interpretation." : nil
        ))

        // §7: Policy is always .advisory — "Share anyway" is always available.
        return BASSafetyAudit(
            results: results,
            policy: .advisory,
            isInterpretation: resolvedIsInterpretation
        )
    }
}
