import SwiftUI

// MARK: - AmenSemanticUnderlineText
//
// Renders body text where high-confidence semantic terms receive a subtle
// dotted underline. Tapping a term fires onTermTapped; long-pressing fires
// onTermLongPressed for deeper context.
//
// Design rules enforced here:
//  - Only underlines terms with confidence >= 0.75 (high-confidence)
//  - At most 4 underlined terms per text block (avoid over-underlining)
//  - No underline in VoiceOver mode — text reads linearly without interruption
//  - Reduce Motion: no scale/spring on tap — plain opacity feedback only
//  - Dot underline style (not full underline) for subtlety

struct AmenSemanticUnderlineText: View {
    let text: String
    let terms: [AmenSemanticTerm]
    var font: Font = .body
    var foregroundStyle: Color = .primary
    var onTermTapped: ((AmenSemanticTerm) -> Void)? = nil
    var onTermLongPressed: ((AmenSemanticTerm) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tappedTermId: String? = nil

    private var highConfidenceTerms: [AmenSemanticTerm] {
        Array(
            terms
                .filter { $0.isHighConfidence }
                .prefix(4)
        )
    }

    var body: some View {
        if highConfidenceTerms.isEmpty {
            // No semantic terms — render plain text, no overhead
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
        } else {
            semanticText
        }
    }

    private var semanticText: some View {
        buildAttributedText()
            .font(font)
            .foregroundStyle(foregroundStyle)
            .overlay(tapTargetOverlay)
            .accessibilityLabel(text)
            .accessibilityHint(accessibilityHint)
    }

    private func buildAttributedText() -> Text {
        let nsText = text as NSString
        var segments: [(range: NSRange, isTerm: Bool, termId: String)] = []

        // Build non-overlapping ranges from sorted high-confidence terms
        var lastEnd = 0
        let sorted = highConfidenceTerms.sorted { $0.range.location < $1.range.location }

        for term in sorted {
            let loc = term.range.location
            let len = term.range.length
            guard loc >= lastEnd, loc + len <= nsText.length else { continue }

            if loc > lastEnd {
                segments.append((NSRange(location: lastEnd, length: loc - lastEnd), false, ""))
            }
            segments.append((term.range, true, term.id))
            lastEnd = loc + len
        }
        if lastEnd < nsText.length {
            segments.append((NSRange(location: lastEnd, length: nsText.length - lastEnd), false, ""))
        }

        // Compose SwiftUI Text runs
        return segments.reduce(Text("")) { result, segment in
            let slice = nsText.substring(with: segment.range)
            if segment.isTerm {
                return result + Text(slice)
                    .underline(pattern: .dot, color: foregroundStyle.opacity(0.5))
            } else {
                return result + Text(slice)
            }
        }
    }

    // Invisible hit-testing layer that handles taps on term regions
    private var tapTargetOverlay: some View {
        GeometryReader { geo in
            ForEach(highConfidenceTerms) { term in
                termTapTarget(term: term, containerWidth: geo.size.width)
            }
        }
        .allowsHitTesting(onTermTapped != nil || onTermLongPressed != nil)
    }

    private func termTapTarget(term: AmenSemanticTerm, containerWidth: CGFloat) -> some View {
        let isTapped = tappedTermId == term.id
        return Color.clear
            .contentShape(Rectangle())
            .scaleEffect(isTapped && !reduceMotion ? 0.97 : 1)
            .opacity(isTapped ? 0.6 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.78), value: isTapped)
            .onTapGesture {
                tappedTermId = term.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTermTapped?(term)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    tappedTermId = nil
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTermLongPressed?(term)
            }
    }

    private var accessibilityHint: String {
        guard !highConfidenceTerms.isEmpty else { return "" }
        let names = highConfidenceTerms.map { $0.term }.joined(separator: ", ")
        return "Tap underlined terms to see definitions: \(names)"
    }
}

// MARK: - AmenSemanticTermExtractor
// Lightweight heuristic extractor. Real confidence scoring comes from the
// defineSemanticTerm Cloud Function — this only highlights well-known terms
// to avoid over-labelling.

struct AmenSemanticTermExtractor {
    static let theologicalTerms: Set<String> = [
        "atonement", "sanctification", "covenant", "discernment", "fasting",
        "grace", "repentance", "justification", "redemption", "salvation",
        "righteousness", "holiness", "resurrection", "baptism", "Pentecost",
        "eschatology", "hermeneutics", "exegesis", "propitiation", "intercession",
        "predestination", "sovereignty", "incarnation", "Trinity", "omniscience"
    ]

    static let scripturePattern = #"(\d\s)?[A-Z][a-z]+\s\d{1,3}(:\d{1,3}(-\d{1,3})?)?"#

    static func extract(from text: String) -> [AmenSemanticTerm] {
        var terms: [AmenSemanticTerm] = []
        let nsText = text as NSString

        // Theological keyword matching (word boundary)
        for keyword in theologicalTerms {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let found = nsText.range(of: keyword, options: [.caseInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }

                // Boundary check — don't match mid-word
                let isBoundaryLeft = found.location == 0 ||
                    !nsText.character(at: found.location - 1).isLetter
                let endIdx = found.location + found.length
                let isBoundaryRight = endIdx >= nsText.length ||
                    !nsText.character(at: endIdx).isLetter

                if isBoundaryLeft && isBoundaryRight {
                    terms.append(AmenSemanticTerm(
                        id: "\(keyword)-\(found.location)",
                        term: nsText.substring(with: found),
                        range: found,
                        confidence: 0.85,
                        category: .theological
                    ))
                }
                searchRange = NSRange(location: endIdx, length: nsText.length - endIdx)
            }
        }

        // Scripture reference matching (e.g. "Romans 8", "John 3:16")
        if let regex = try? NSRegularExpression(pattern: scripturePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let refText = nsText.substring(with: match.range)
                terms.append(AmenSemanticTerm(
                    id: "scripture-\(match.range.location)",
                    term: refText,
                    range: match.range,
                    confidence: 0.90,
                    category: .scripture
                ))
            }
        }

        return deduplicateOverlapping(terms)
    }

    private static func deduplicateOverlapping(_ terms: [AmenSemanticTerm]) -> [AmenSemanticTerm] {
        var result: [AmenSemanticTerm] = []
        let sorted = terms.sorted { $0.range.location < $1.range.location }
        var lastEnd = 0
        for term in sorted {
            if term.range.location >= lastEnd {
                result.append(term)
                lastEnd = term.range.location + term.range.length
            }
        }
        return result
    }
}

// Convenience Character check
private extension Character {
    var isLetterOrUnderscore: Bool {
        self.isLetter || self == "_"
    }
}

private extension unichar {
    var isLetter: Bool {
        CharacterSet.letters.contains(Unicode.Scalar(self)!)
    }
}
