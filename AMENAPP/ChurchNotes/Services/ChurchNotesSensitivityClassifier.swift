
//  ChurchNotesSensitivityClassifier.swift
//  AMENAPP
//
//  W1 — On-device sensitivity classifier. No network. No server proxy.
//  Classification runs BEFORE any extraction or surfacing decision.
//  Fail-closed: unclassified or ambiguous notes resolve to .confidential.
//

import Foundation

// MARK: - On-Device Classifier

/// Pure on-device implementation of SensitivityClassifier (defined in W0 contracts).
/// Uses keyword scoring only — no model inference, no network.
/// Word sets are conservative: false positives (over-classifying as confidential) preferred.
final class ChurchNotesSensitivityClassifierImpl: ChurchNotesSensitivityClassifier {

    private static let confidentialSignals: [String] = [
        "confess", "confession", "counseling", "counselling",
        "addiction", "recovery", "rehab",
        "marriage conflict", "separation", "divorce proceedings",
        "abuse", "domestic", "trauma",
        "suicid", "self-harm", "eating disorder",
        "pastoral care", "pastoral appointment",
        "private session", "confidential prayer",
        "mental breakdown", "psychiatric",
    ]

    private static let sensitiveSignals: [String] = [
        "pray for", "prayer request", "please pray",
        "struggling with", "battling", "dealing with",
        "sick", "cancer", "hospital", "surgery", "diagnosis",
        "grief", "lost her", "lost his", "passed away", "funeral",
        "job loss", "unemployed", "financial crisis",
        "brokenhearted", "heartbreak",
        "relationship problem", "family problem",
    ]

    private static let confidentialTagPrefixes: Set<String> = [
        "pastoral", "counseling", "counselling",
        "confidential", "private-prayer", "confidential-prayer",
        "recovery", "confession",
    ]

    func classify(_ note: NoteContent) -> NoteSensitivity {
        if hasConfidentialTag(note.tags) { return .confidential }
        if hasSensitiveTag(note.tags)    { return .sensitive }

        let lower = note.plainText.lowercased()

        if containsAny(of: Self.confidentialSignals, in: lower) { return .confidential }
        if containsAny(of: Self.sensitiveSignals, in: lower)    { return .sensitive }

        if containsNamedPersonWithSensitiveContext(note.plainText) { return .sensitive }

        return .general
    }

    private func hasConfidentialTag(_ tags: [String]) -> Bool {
        let normalized = tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return normalized.contains { tag in
            Self.confidentialTagPrefixes.contains { tag.hasPrefix($0) }
        }
    }

    private func hasSensitiveTag(_ tags: [String]) -> Bool {
        let normalized = tags.map { $0.lowercased() }
        return normalized.contains { $0.hasPrefix("sensitive") || $0 == "prayer" }
    }

    private func containsAny(of signals: [String], in text: String) -> Bool {
        signals.contains { text.contains($0) }
    }

    private func containsNamedPersonWithSensitiveContext(_ text: String) -> Bool {
        let sensitiveContextWords = ["pray", "sick", "hospital", "struggling", "battle",
                                     "grief", "loss", "crisis", "problem", "difficult"]
        guard sensitiveContextWords.contains(where: { text.lowercased().contains($0) }) else {
            return false
        }
        let pattern = #"[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Locus Enforcer (W1 gate service)

/// Wraps the SensitivityClassifier and enforces compute-locus rules at every call site.
/// Not MainActor — pure logic with no UI state; safe to call from any context.
final class DiscipleshipLocusEnforcer {

    private let classifier: ChurchNotesSensitivityClassifier

    init(classifier: ChurchNotesSensitivityClassifier = ChurchNotesSensitivityClassifierImpl()) {
        self.classifier = classifier
    }

    /// Classify a note and return its compute locus. All downstream callers must consult this.
    func computeLocus(for note: NoteContent) -> ComputeLocus {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.classificationEnabled else {
            return .onDeviceOnly  // safe default when flags are off
        }
        let sensitivity = classifier.classify(note)
        return locus(for: sensitivity)
    }

    /// True when the note is safe to proactively surface (card, notification, widget). (S1)
    func canProactivelySurface(sensitivity: NoteSensitivity) -> Bool {
        sensitivity != .confidential
    }

    /// True when the server proxy may be called for this note. (S2)
    func serverProxyAllowed(for note: NoteContent) -> Bool {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.classificationEnabled else {
            return false
        }
        return locus(for: classifier.classify(note)) == .serverProxyAllowed
    }

    /// Returns the sensitivity class. Fails closed to .confidential when flags are off.
    func sensitivity(for note: NoteContent) -> NoteSensitivity {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.classificationEnabled else {
            return .confidential
        }
        return classifier.classify(note)
    }
}
