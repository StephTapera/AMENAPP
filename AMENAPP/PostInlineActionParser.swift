import Foundation

final class PostInlineActionParser {
    static let shared = PostInlineActionParser()

    private struct ActionPattern {
        let regex: NSRegularExpression
        let actionType: PostInlineActionType
    }

    private let actionPatterns: [ActionPattern] = {
        let rawPatterns: [(String, PostInlineActionType)] = [
            (#"\bdm me\b"#, .openDMWithPostAuthor),
            (#"\bmessage me\b"#, .openDMWithPostAuthor)
        ]

        return rawPatterns.compactMap { pattern, actionType in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return ActionPattern(regex: regex, actionType: actionType)
        }
    }()

    private init() {}

    func tokenize(_ text: String) -> [PostInlineContentToken] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var matches: [(NSRange, PostInlineContentToken)] = []

        for pattern in actionPatterns {
            for result in pattern.regex.matches(in: text, options: [], range: fullRange) {
                let matchedText = nsText.substring(with: result.range)
                matches.append((
                    result.range,
                    PostInlineContentToken(
                        type: .action,
                        text: matchedText,
                        start: result.range.location,
                        end: result.range.location + result.range.length,
                        actionType: pattern.actionType
                    )
                ))
            }
        }

        guard !matches.isEmpty else { return [] }

        matches.sort { lhs, rhs in
            if lhs.0.location == rhs.0.location {
                return lhs.0.length > rhs.0.length
            }
            return lhs.0.location < rhs.0.location
        }

        var deduped: [(NSRange, PostInlineContentToken)] = []
        var coveredUpperBound = -1

        for match in matches where match.0.location >= coveredUpperBound {
            deduped.append(match)
            coveredUpperBound = match.0.location + match.0.length
        }

        var tokens: [PostInlineContentToken] = []
        var cursor = 0

        for (range, token) in deduped {
            if range.location > cursor {
                let textRange = NSRange(location: cursor, length: range.location - cursor)
                tokens.append(
                    PostInlineContentToken(
                        type: .text,
                        text: nsText.substring(with: textRange),
                        start: textRange.location,
                        end: textRange.location + textRange.length
                    )
                )
            }

            tokens.append(token)
            cursor = range.location + range.length
        }

        if cursor < nsText.length {
            let trailingRange = NSRange(location: cursor, length: nsText.length - cursor)
            tokens.append(
                PostInlineContentToken(
                    type: .text,
                    text: nsText.substring(with: trailingRange),
                    start: trailingRange.location,
                    end: trailingRange.location + trailingRange.length
                )
            )
        }

        return tokens
    }
}
