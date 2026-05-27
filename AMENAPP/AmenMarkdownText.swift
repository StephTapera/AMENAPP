import SwiftUI

public struct AmenMarkdownText: View {

    private let text: String
    private let font: Font

    public init(_ text: String, font: Font = .body) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        resolvedText
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resolvedText: Text {
        if let attributed = parseMarkdown() {
            return Text(attributed)
        }
        return Text(text)
    }

    private func parseMarkdown() -> AttributedString? {
        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let result = try? AttributedString(markdown: text, options: inlineOptions) {
            if result.characters.isEmpty {
                return parseFullMarkdown()
            }
            return result
        }
        return parseFullMarkdown()
    }

    private func parseFullMarkdown() -> AttributedString? {
        let fullOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full
        )
        return try? AttributedString(markdown: text, options: fullOptions)
    }
}
