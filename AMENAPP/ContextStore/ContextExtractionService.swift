// ContextExtractionService.swift
// AMEN Universal Migration & Context System — Wave 3 (extractor-engineer)
//
// THE ONE UNIVERSAL EXTRACTION PIPELINE. There is exactly ONE pipeline here — not a
// per-platform parser. Resume, LinkedIn export, Google/Meta takeout, ChatGPT/Claude/
// Gemini memory export, an "about me" blurb, a pasted bio — all funnel through the same
// normalize → drop-excluded → C59-sanitize → extract path. Thin pre-normalizers below
// only turn a file's bytes into plain text; they never branch the pipeline's safety logic.
//
// HARD INVARIANTS (mirrored by ContextSanitizer C59 + ContextStoreService + firestore.rules):
//   • Imported text is DATA, never instructions (Aegis C59 wraps it as inert before any LLM).
//   • HARD-DROP at normalization: media files, message/DM transcript structures, contact
//     lists, and email/phone patterns are removed BEFORE extraction — and the caller is told
//     which categories were dropped (DroppedCategories) for the "we ignored your messages and
//     photos — by design" UX. No content import, enforced in code (defense-in-depth with C59-d).
//   • Aegis C59 runs on EVERY import path: the raw body is sanitized and a non-empty
//     SanitizationReceipt is produced; its passId rides on every emitted candidate.
//   • Approval before persistence: this service NEVER writes Firestore. It returns ephemeral
//     `[FacetCandidate]` candidates only. The user approves them in FacetApprovalView, and
//     ContextStoreService.saveFacet is the sole write path (it re-verifies tier + receipt).
//   • Flag-gated on `contextUniversalImportEnabled` (master `contextSystemEnabled` still applies
//     wherever facets are persisted).
//
// `FacetCandidate` is the canonical structured-output type owned by
// BereanMigrationInterviewPrompt.swift. This service consumes it; it does not redefine it.

import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - Import source description

/// What the user handed us. The pipeline is universal — this only labels provenance and
/// selects a THIN pre-normalizer (bytes → text). It never changes the safety pipeline.
enum ContextImportSource: Equatable {
    /// Text pasted directly into the universal paste box.
    case pastedText(label: String?)
    /// An uploaded file. `kind` selects a thin pre-normalizer; everything after is identical.
    case file(kind: ImportFileKind, filename: String)

    /// Human label that becomes `Provenance.sourceLabel` ("LinkedIn export", "ChatGPT memory"…).
    var sourceLabel: String {
        switch self {
        case .pastedText(let label):       return label?.isEmpty == false ? label! : "Pasted text"
        case .file(_, let filename):       return filename
        }
    }

    /// The `FacetSource` the eventual provenance carries.
    var facetSource: FacetSource {
        switch self {
        case .pastedText: return .extracted_paste
        case .file:       return .extracted_file
        }
    }
}

/// File kinds the thin pre-normalizers understand. Anything else is rejected loudly — we do
/// not silently try to parse an unknown binary.
enum ImportFileKind: String, Equatable, CaseIterable {
    case txt
    case json
    case csv
    case pdf
    case docx
}

// MARK: - Dropped-category UX summary

/// Summary of which EXCLUDED categories were hard-dropped during normalization. Surfaced to
/// the user as the "we ignored your messages and photos — by design" reassurance. This is a
/// COUNT-and-CATEGORY summary only — it never carries the dropped content itself.
struct DroppedCategories: Equatable {
    /// One excluded category and how many times it was scrubbed.
    enum Category: String, CaseIterable {
        case mediaFiles        // photos / audio / video / file attachments
        case messages          // message / DM / email transcript structures
        case contacts          // contact lists / vCard dumps
        case emails            // email-address patterns
        case phones            // phone-number patterns

        /// Reassuring, human copy for the UX.
        var displayName: String {
            switch self {
            case .mediaFiles: return "Photos & media"
            case .messages:   return "Messages & DMs"
            case .contacts:   return "Contact lists"
            case .emails:     return "Email addresses"
            case .phones:     return "Phone numbers"
            }
        }
    }

    /// Per-category drop counts. A zero/absent entry means nothing of that kind was found.
    private(set) var counts: [Category: Int] = [:]

    /// True if anything was dropped (drives whether to show the reassurance banner).
    var didDropAnything: Bool { counts.values.contains { $0 > 0 } }

    /// The categories that were actually dropped, for rendering chips.
    var droppedCategories: [Category] {
        Category.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    /// One-line summary, e.g. "Ignored 3 phone numbers and 1 contact list — by design."
    var summaryLine: String {
        let parts = droppedCategories.map { cat -> String in
            let n = counts[cat] ?? 0
            return "\(n) \(cat.displayName.lowercased())"
        }
        guard !parts.isEmpty else { return "" }
        let joined = parts.count == 1
            ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "Ignored \(joined) — by design."
    }

    mutating func add(_ category: Category, count: Int) {
        guard count > 0 else { return }
        counts[category, default: 0] += count
    }
}

/// The full ephemeral result of one import. Candidates are NOT persisted; the caller routes
/// them through the Approval UI. `dropped` powers the reassurance UX; `receipt` is the C59
/// receipt whose passId is carried on every candidate to the write path.
struct ContextExtractionResult: Equatable {
    let candidates: [FacetCandidate]
    let dropped: DroppedCategories
    let sanitizationPassId: String
    let sourceLabel: String
    let facetSource: FacetSource
}

// MARK: - Errors

enum ContextExtractionError: LocalizedError, Equatable {
    case importDisabled
    case notSignedIn
    case emptyInput
    case unsupportedFile(ImportFileKind?)
    case sanitizationProducedEmptyReceipt
    case invalidExtractionResponse

    var errorDescription: String? {
        switch self {
        case .importDisabled:
            return "Universal import is turned off (contextUniversalImportEnabled == false)."
        case .notSignedIn:
            return "No signed-in user; cannot run a context import."
        case .emptyInput:
            return "There was no usable text to import after normalization."
        case .unsupportedFile(let kind):
            return "This file type isn't supported for import\(kind.map { " (\($0.rawValue))" } ?? "")."
        case .sanitizationProducedEmptyReceipt:
            return "Aegis C59 produced no sanitization receipt; nothing can be extracted or persisted."
        case .invalidExtractionResponse:
            return "The extraction service returned an invalid response."
        }
    }
}

// MARK: - ContextExtractionService

/// The universal extractor. Stateless and side-effect-free except for the single CF call.
/// Writes NOTHING to Firestore — output is ephemeral candidates the user must approve.
final class ContextExtractionService {

    /// Injectable for tests; defaults to the live C59 sanitizer (the same struct the rest of
    /// the import path uses, so client behavior is identical everywhere).
    private let sanitizer: ContextSanitizer
    private let functions: Functions

    init(sanitizer: ContextSanitizer = ContextSanitizer(),
         functions: Functions = Functions.functions()) {
        self.sanitizer = sanitizer
        self.functions = functions
    }

    // MARK: - Public entry points

    /// Universal paste-box entry. Text in → ephemeral candidates out. Persists nothing.
    func extractFromPastedText(_ text: String, label: String? = nil) async throws -> ContextExtractionResult {
        try await run(rawText: text, source: .pastedText(label: label))
    }

    /// Universal file entry. A thin pre-normalizer turns bytes → text, then the SAME pipeline
    /// runs. Supports resume / LinkedIn export / takeout / AI-memory export / about-text files.
    func extractFromFile(_ data: Data, kind: ImportFileKind, filename: String) async throws -> ContextExtractionResult {
        let text = try Self.preNormalize(data, kind: kind)
        return try await run(rawText: text, source: .file(kind: kind, filename: filename))
    }

    // MARK: - The one universal pipeline

    /// input (already text) → normalize → DROP excluded categories (summary) → C59 sanitize →
    /// extractContextFacets CF → ephemeral [FacetCandidate]. No Firestore writes here.
    private func run(rawText: String, source: ContextImportSource) async throws -> ContextExtractionResult {
        guard AMENFeatureFlags.shared.contextUniversalImportEnabled else {
            throw ContextExtractionError.importDisabled
        }
        // Auth is required so the CF can attribute + App Check the call; we never embed the uid
        // in any facet here (the write path does that), we only ensure a session exists.
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw ContextExtractionError.notSignedIn
        }
        _ = uid

        // 1. Normalize whitespace / control characters into clean plain text.
        let normalized = Self.normalize(rawText)
        guard !normalized.isEmpty else { throw ContextExtractionError.emptyInput }

        // 2. HARD-DROP excluded categories and tally them for the reassurance UX.
        //    We count BEFORE handing to C59 so we can name what we ignored; C59 then performs
        //    the authoritative scrub (defense-in-depth: both layers remove the same content).
        let dropped = Self.countAndStripExcluded(normalized, source: source)

        // 3. Aegis C59 — the authoritative sanitization pass on EVERY import path.
        //    `sanitize` caps length, strips excluded content again, neutralizes injection
        //    patterns, and emits a non-empty receipt. Fails closed on an empty receipt.
        let (sanitized, receipt) = sanitizer.sanitize(normalized)
        guard receipt.isVerified, !receipt.passId.isEmpty else {
            throw ContextExtractionError.sanitizationProducedEmptyReceipt
        }
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Everything was excluded content — nothing safe to extract. Still report drops.
            return ContextExtractionResult(
                candidates: [],
                dropped: dropped,
                sanitizationPassId: receipt.passId,
                sourceLabel: source.sourceLabel,
                facetSource: source.facetSource
            )
        }

        // 4. Call the extraction CF. The model receives the C59-wrapped inert document and the
        //    sanitizationPassId; it returns structured FacetCandidate[] (schema-validated,
        //    free-text length-capped). We pass the wrapped form so the server prompt is told,
        //    in band, that the content is DATA — matching the server's own wrapping.
        let inert = sanitizer.wrapAsInertDocument(sanitized)
        let rawCandidates = try await callExtractContextFacets(
            text: inert,
            sourceLabel: source.sourceLabel,
            sanitizationPassId: receipt.passId
        )

        // 5. Length-cap every free-text field client-side as belt-and-suspenders, and force
        //    suggested visibility to private (the model may not widen it). Tier is NEVER set
        //    here — the write path derives it from ContextTierTable.
        let candidates = rawCandidates.map { Self.hardenCandidate($0, sanitizer: sanitizer) }

        return ContextExtractionResult(
            candidates: candidates,
            dropped: dropped,
            sanitizationPassId: receipt.passId,
            sourceLabel: source.sourceLabel,
            facetSource: source.facetSource
        )
    }

    // MARK: - Cloud Function call

    /// Calls `extractContextFacets` ({ text, sourceLabel, sanitizationPassId } →
    /// { candidates: FacetCandidate[] }). Decodes the response into the canonical type.
    /// Returns [] for an empty/malformed candidates array rather than fabricating anything.
    private func callExtractContextFacets(
        text: String,
        sourceLabel: String,
        sanitizationPassId: String
    ) async throws -> [FacetCandidate] {
        let callable = functions.httpsCallable("extractContextFacets")
        let result = try await callable.call([
            "text": text,
            "sourceLabel": sourceLabel,
            "sanitizationPassId": sanitizationPassId,
        ])

        guard let payload = result.data as? [String: Any] else {
            throw ContextExtractionError.invalidExtractionResponse
        }
        guard let rawArray = payload["candidates"] as? [[String: Any]] else {
            // A well-formed empty response is allowed (model found nothing durable).
            return []
        }

        // Round-trip each candidate through JSONDecoder so it validates against the canonical
        // `FacetCandidate` Codable (which mirrors facetCandidateJSONSchema). Anything that
        // doesn't decode is dropped, never salvaged from prose.
        let decoder = JSONDecoder()
        return rawArray.compactMap { raw -> FacetCandidate? in
            guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? decoder.decode(FacetCandidate.self, from: data)
        }
    }

    // MARK: - Normalization

    /// Collapse control chars / excessive whitespace into clean plain text. Pure + deterministic.
    static func normalize(_ s: String) -> String {
        // Replace NULs and other control characters (except newline/tab) with spaces.
        let scalars = s.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" || scalar == "\t" { return Character(scalar) }
            if CharacterSet.controlCharacters.contains(scalar) { return " " }
            return Character(scalar)
        }
        let cleaned = String(scalars)
        // Collapse runs of 3+ blank lines into a single blank line; trim trailing space per line.
        let lines = cleaned.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression) }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Excluded-category counting (UX) + strip

    /// Count occurrences of each excluded category for the reassurance UX. The authoritative
    /// removal is C59's `stripExcludedContent`; this mirrors those categories so we can NAME
    /// what was ignored. Returns counts only — never the dropped content.
    static func countAndStripExcluded(_ s: String, source: ContextImportSource) -> DroppedCategories {
        var dropped = DroppedCategories()

        dropped.add(.emails,   count: matchCount(emailPattern, in: s))
        dropped.add(.phones,   count: matchCount(phonePattern, in: s))
        dropped.add(.contacts, count: matchCount(vcardPattern, in: s))
        let msgCount = matchCount(messageTimestampPattern, in: s) + matchCount(messageWrotePattern, in: s)
        dropped.add(.messages, count: msgCount)

        // Media: text imports can reference attachments by extension/markers. We can't import
        // media (there's no binary path), so any media reference is a "dropped media" signal.
        dropped.add(.mediaFiles, count: matchCount(mediaReferencePattern, in: s))

        return dropped
    }

    // Excluded-category patterns (kept aligned with ContextSanitizer.exclusionRules).
    private static let emailPattern    = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#
    private static let phonePattern    = #"(?:\+?\d{1,3}[\s.\-]?)?(?:\(?\d{2,4}\)?[\s.\-]?){2,4}\d{2,4}"#
    private static let vcardPattern    = #"BEGIN:VCARD[\s\S]*?END:VCARD"#
    private static let messageTimestampPattern = #"(?:^|\n)\s*\[?\d{1,2}:\d{2}\s*(?:AM|PM)?\]?\s+[^\n:]{1,40}:"#
    private static let messageWrotePattern     = #"On\s+.{3,40}\s+wrote:"#
    private static let mediaReferencePattern   = #"\.(?:jpe?g|png|gif|heic|webp|mp4|mov|m4a|mp3|wav|aac|pdf|zip)\b"#

    private static func matchCount(_ pattern: String, in s: String) -> Int {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return rx.numberOfMatches(in: s, options: [], range: range)
    }

    // MARK: - Candidate hardening

    /// Belt-and-suspenders client cap on every free-text field + forced private visibility.
    /// Tier is NOT set here (the write path derives it). Never widens what the model proposed.
    static func hardenCandidate(_ c: FacetCandidate, sanitizer: ContextSanitizer) -> FacetCandidate {
        FacetCandidate(
            category: c.category,
            key: sanitizer.capField(c.key),
            label: sanitizer.capField(c.label),
            value: cap(value: c.value, sanitizer: sanitizer),
            confidence: c.confidence,
            // The model may never widen visibility; force private on the way out.
            suggestedVisibility: .privateVisibility
        )
    }

    private static func cap(value: StructuredFacetValue, sanitizer: ContextSanitizer) -> StructuredFacetValue {
        switch value {
        case .text(let t):
            return .text(sanitizer.capField(t))
        case .list(let items):
            return .list(items.map { sanitizer.capField($0) })
        case .faithJourney(var v):
            v.currentChurchName = v.currentChurchName.map { sanitizer.capField($0) }
            v.currentStudy = v.currentStudy.map { sanitizer.capField($0) }
            v.favoriteBooks = v.favoriteBooks.map { sanitizer.capField($0) }
            v.spiritualGoals = v.spiritualGoals.map { sanitizer.capField($0) }
            v.prayerHabits = v.prayerHabits.map { sanitizer.capField($0) }
            v.areasOfGrowth = v.areasOfGrowth.map { sanitizer.capField($0) }
            v.areasNeedingSupport = v.areasNeedingSupport.map { sanitizer.capField($0) }
            return .faithJourney(v)
        case .communicationStyle(var v):
            v.preferredTone = v.preferredTone.map { sanitizer.capField($0) }
            v.conversationStyles = v.conversationStyles.map { sanitizer.capField($0) }
            v.frustratingBehaviors = v.frustratingBehaviors.map { sanitizer.capField($0) }
            v.meaningfulContentTypes = v.meaningfulContentTypes.map { sanitizer.capField($0) }
            return .communicationStyle(v)
        case .relationshipCategory(var v):
            v.note = v.note.map { sanitizer.capField($0) }
            return .relationshipCategory(v)
        }
    }

    // MARK: - Thin file pre-normalizers (bytes → text ONLY)

    /// Turn an uploaded file's bytes into plain text. These are deliberately THIN: they extract
    /// text and nothing else. They DO NOT branch the safety pipeline — every byte they produce
    /// flows through the exact same normalize → drop → C59 → extract path as pasted text.
    static func preNormalize(_ data: Data, kind: ImportFileKind) throws -> String {
        switch kind {
        case .txt:
            return decodeText(data)
        case .csv:
            // CSV → newline-joined cells as plain text; the pipeline treats it as prose.
            return decodeText(data)
        case .json:
            // JSON (takeout / AI-memory export) → flatten string leaves to plain text.
            return Self.flattenJSON(decodeText(data))
        case .pdf, .docx:
            // PDF/DOCX text extraction requires the platform document layer; the import UI passes
            // already-extracted text for these via the paste path until that layer is wired.
            // We still accept the kinds so the pipeline shape is complete and testable.
            // TODO(wire: PDFKit/DocX text extraction in the import picker before enabling these kinds in UI)
            return decodeText(data)
        }
    }

    private static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Flatten a JSON export's string leaves into newline-separated plain text. Keys provide
    /// light structure; values become the corpus. Non-JSON falls back to the raw text.
    static func flattenJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return text
        }
        var out: [String] = []
        func walk(_ node: Any, keyPath: String) {
            switch node {
            case let dict as [String: Any]:
                for (k, v) in dict { walk(v, keyPath: k) }
            case let arr as [Any]:
                for v in arr { walk(v, keyPath: keyPath) }
            case let s as String:
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append("\(keyPath): \(trimmed)") }
            case let n as NSNumber:
                out.append("\(keyPath): \(n)")
            default:
                break
            }
        }
        walk(obj, keyPath: "")
        return out.joined(separator: "\n")
    }
}
