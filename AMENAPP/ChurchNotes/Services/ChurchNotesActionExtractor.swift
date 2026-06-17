
//  ChurchNotesActionExtractor.swift
//  AMENAPP
//
//  W2 — Action extraction. On-device for sensitive/confidential; server proxy for general.
//  Locus is enforced by DiscipleshipLocusEnforcer before this is invoked.
//

import Foundation
import FirebaseFunctions

// MARK: - On-Device Extractor

/// Keyword + structured-block extractor for sensitive and confidential notes.
/// No network calls — ever.
final class OnDeviceActionExtractor: ActionExtractor {

    private static let prayKeywords    = ["pray", "prayer", "intercede", "petition", "lift up"]
    private static let readKeywords    = ["read", "study", "meditate on", "reflect on"]
    private static let reachOutKeywords = ["call", "text", "check in", "reach out", "visit",
                                           "meet with", "connect with"]
    private static let fastKeywords    = ["fast", "fasting"]
    private static let memorizeKeywords = ["memorize", "memorise", "commit to memory"]
    private static let applyKeywords   = ["apply", "practice", "act on", "implement", "commit to"]
    private static let attendKeywords  = ["attend", "go to", "join", "show up"]

    func extract(from note: NoteContent, locus: ComputeLocus) async -> [SpiritualAction] {
        let lower = note.plainText.lowercased()
        var actions: [SpiritualAction] = []
        // Sensitivity is conservative: on-device locus covers both .sensitive and .confidential.
        // .confidential notes never reach the affordance proactively (enforced by the surface layer);
        // when extraction runs on-device for a confidential note it must be user-initiated.
        let sensitivity: NoteSensitivity = .sensitive

        // 1. Structured block extraction (higher signal)
        for block in note.blocks {
            switch block.type {
            case .prayer:
                actions.append(make(.pray, text: block.text, note: note, sensitivity: sensitivity))
            case .action:
                let kind = infer(from: block.text.lowercased()) ?? .apply
                actions.append(make(kind, text: block.text, note: note, sensitivity: sensitivity))
            default:
                break
            }
        }

        // 2. Plain-text extraction (lower signal, runs only when no blocks)
        if note.blocks.isEmpty {
            if contains(Self.prayKeywords, in: lower) {
                actions.append(make(.pray, text: "Take time to pray", note: note, sensitivity: sensitivity))
            }
            if contains(Self.readKeywords, in: lower) {
                actions.append(make(.read, text: "Continue the reading plan", note: note, sensitivity: sensitivity))
            }
            if contains(Self.reachOutKeywords, in: lower) {
                actions.append(make(.reachOut, text: "Reach out to someone", note: note, sensitivity: sensitivity))
            }
            if contains(Self.fastKeywords, in: lower) {
                actions.append(make(.fast, text: "Consider a time of fasting", note: note, sensitivity: sensitivity))
            }
            if contains(Self.memorizeKeywords, in: lower) {
                actions.append(make(.memorize, text: "Memorize this scripture", note: note, sensitivity: sensitivity))
            }
            if contains(Self.applyKeywords, in: lower) {
                actions.append(make(.apply, text: "Apply what you heard", note: note, sensitivity: sensitivity))
            }
            if contains(Self.attendKeywords, in: lower) {
                actions.append(make(.attend, text: "Attend the upcoming gathering", note: note, sensitivity: sensitivity))
            }
        }

        return Array(actions.prefix(5))
    }

    // MARK: Helpers

    private func make(_ kind: ActionKind, text: String, note: NoteContent,
                      sensitivity: NoteSensitivity) -> SpiritualAction {
        let summary = trimmed(text).isEmpty ? kind.defaultSummary : trimmed(text)
        return SpiritualAction(id: UUID(), kind: kind, summary: summary,
                               namedPeople: extractNames(from: text),
                               sourceNoteID: note.noteID, sensitivity: sensitivity)
    }

    private func infer(from text: String) -> ActionKind? {
        if contains(Self.prayKeywords, in: text)     { return .pray }
        if contains(Self.readKeywords, in: text)     { return .read }
        if contains(Self.reachOutKeywords, in: text) { return .reachOut }
        if contains(Self.fastKeywords, in: text)     { return .fast }
        if contains(Self.memorizeKeywords, in: text) { return .memorize }
        if contains(Self.attendKeywords, in: text)   { return .attend }
        return nil
    }

    private func contains(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func trimmed(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 80 ? String(t.prefix(80)) + "…" : t
    }

    private func extractNames(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }.filter { $0.split(separator: " ").count >= 2 }
    }
}

// MARK: - Server Proxy Extractor (general notes only)

/// Calls `extractSpiritualActions` Firebase callable for `.general` notes.
/// MUST NOT be called for sensitive or confidential notes (S2).
final class ServerProxyActionExtractor: ActionExtractor {

    private let functions = Functions.functions()

    func extract(from note: NoteContent, locus: ComputeLocus) async -> [SpiritualAction] {
        guard locus == .serverProxyAllowed else {
            assertionFailure("S2 violation: ServerProxyActionExtractor called with onDeviceOnly locus")
            return []
        }
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.extractionEnabled else { return [] }

        do {
            let result = try await functions
                .httpsCallable("extractSpiritualActions")
                .call(["text": note.plainText, "tags": note.tags])
            guard let data = result.data as? [String: Any],
                  let rawItems = data["actions"] as? [[String: Any]] else { return [] }
            return rawItems.compactMap { decode($0, sourceNoteID: note.noteID) }
        } catch {
            return []
        }
    }

    private func decode(_ raw: [String: Any], sourceNoteID: UUID) -> SpiritualAction? {
        guard let kindRaw = raw["kind"] as? String,
              let kind = ActionKind(rawValue: kindRaw),
              let summary = raw["summary"] as? String else { return nil }
        return SpiritualAction(id: UUID(), kind: kind, summary: summary,
                               namedPeople: raw["namedPeople"] as? [String] ?? [],
                               sourceNoteID: sourceNoteID, sensitivity: .general)
    }
}

// MARK: - Routing Extractor

/// Dispatches to the correct extractor based on compute locus. Single call site for W2+.
final class RoutingActionExtractor {

    private let onDevice = OnDeviceActionExtractor()
    private let serverProxy = ServerProxyActionExtractor()

    func extract(from note: NoteContent, locus: ComputeLocus) async -> [SpiritualAction] {
        switch locus {
        case .onDeviceOnly:      return await onDevice.extract(from: note, locus: locus)
        case .serverProxyAllowed: return await serverProxy.extract(from: note, locus: locus)
        }
    }
}

// MARK: - ActionKind UI helpers

extension ActionKind {
    var defaultSummary: String {
        switch self {
        case .pray:     return "Take time to pray"
        case .read:     return "Continue the reading plan"
        case .reachOut: return "Reach out to someone"
        case .fast:     return "Consider a time of fasting"
        case .memorize: return "Memorize this scripture"
        case .apply:    return "Apply what you heard"
        case .attend:   return "Attend the upcoming gathering"
        }
    }

    var sfSymbol: String {
        switch self {
        case .pray:     return "hands.sparkles.fill"
        case .read:     return "book.fill"
        case .reachOut: return "person.wave.2.fill"
        case .fast:     return "fork.knife.circle.fill"
        case .memorize: return "brain.fill"
        case .apply:    return "checkmark.circle.fill"
        case .attend:   return "building.columns.fill"
        }
    }
}
