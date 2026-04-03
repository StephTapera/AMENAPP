import SwiftUI
import UIKit

struct SelectablePostTextView: UIViewRepresentable {
    let text: String
    let mentions: [MentionedUser]?
    let font: UIFont
    let lineSpacing: CGFloat
    let lineLimit: Int?
    let onMentionTap: (MentionedUser) -> Void
    let onTextTap: () -> Void
    @Binding var selection: PostTextSelection?
    @Binding var isSelecting: Bool

    func makeUIView(context: Context) -> HighlightSelectableTextView {
        let textView = HighlightSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.dataDetectorTypes = []
        textView.tintColor = UIColor(red: 0.97, green: 0.86, blue: 0.25, alpha: 1.0)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.label,
            .underlineStyle: 0
        ]
        textView.onSelectionChange = { selection in
            context.coordinator.handleSelectionChange(selection)
        }
        textView.onMentionTap = onMentionTap
        textView.onTextTap = onTextTap
        context.coordinator.updateText(in: textView)
        applyLineLimit(to: textView)
        return textView
    }

    func updateUIView(_ uiView: HighlightSelectableTextView, context: Context) {
        context.coordinator.updateText(in: uiView)
        applyLineLimit(to: uiView)

        if selection == nil, uiView.selectedTextRange != nil {
            uiView.selectedTextRange = nil
        }
    }

    private func applyLineLimit(to textView: UITextView) {
        if let lineLimit {
            textView.textContainer.maximumNumberOfLines = lineLimit
            textView.textContainer.lineBreakMode = .byTruncatingTail
        } else {
            textView.textContainer.maximumNumberOfLines = 0
            textView.textContainer.lineBreakMode = .byWordWrapping
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectablePostTextView
        private var lastText: String = ""

        init(_ parent: SelectablePostTextView) {
            self.parent = parent
        }

        func updateText(in textView: HighlightSelectableTextView) {
            guard parent.text != lastText else { return }
            lastText = parent.text

            let attributed = NSMutableAttributedString(string: parent.text)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = parent.lineSpacing
            paragraph.alignment = .natural

            attributed.addAttributes([
                .font: parent.font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ], range: NSRange(location: 0, length: attributed.length))

            if let mentions = parent.mentions {
                for mention in mentions {
                    let token = "@\(mention.username)"
                    let ranges = attributed.string.ranges(of: token)
                    for range in ranges {
                        let nsRange = NSRange(range, in: attributed.string)
                        attributed.addAttributes([
                            .font: UIFont.boldSystemFont(ofSize: parent.font.pointSize),
                            .foregroundColor: UIColor.label,
                            .backgroundColor: UIColor(red: 1.0, green: 0.93, blue: 0.66, alpha: 0.9),
                            .link: URL(string: "amen-mention://\(mention.userId.isEmpty ? mention.username : mention.userId)") as Any
                        ], range: nsRange)
                    }
                }
            }

            textView.attributedText = attributed
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let textView = textView as? HighlightSelectableTextView else { return }
            textView.reportSelection()
        }

        @available(iOS, deprecated: 17.0)
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "amen-mention" {
                if let mentions = parent.mentions {
                    let id = URL.host ?? URL.absoluteString.replacingOccurrences(of: "amen-mention://", with: "")
                    if let match = mentions.first(where: { $0.userId == id || $0.username == id }) {
                        parent.onMentionTap(match)
                        return false
                    }
                }
            }
            return false
        }

        func handleSelectionChange(_ selection: PostTextSelection?) {
            parent.isSelecting = selection != nil
            parent.selection = selection
        }
    }
}

final class HighlightSelectableTextView: UITextView {
    var onSelectionChange: ((PostTextSelection?) -> Void)?
    var onMentionTap: ((MentionedUser) -> Void)?
    var onTextTap: (() -> Void)?

    private lazy var tapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        return tap
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(tapGesture)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }

    @objc private func handleTap() {
        if selectedTextRange == nil || selectedTextRange?.isEmpty == true {
            onTextTap?()
        }
    }

    func reportSelection() {
        guard let range = selectedTextRange, let text = text else {
            onSelectionChange?(nil)
            return
        }

        let selectionText = (text as NSString).substring(with: nsRange(from: range))
        if selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onSelectionChange?(nil)
            return
        }

        let rects = selectionRects(for: range)
            .map { $0.rect }
            .filter { !$0.isNull && !$0.isEmpty }

        let union = rects.reduce(CGRect.null) { $0.union($1) }
        let suggestedType = SelectionHeuristics.suggestedQuoteType(for: selectionText)

        let selection = PostTextSelection(
            text: selectionText,
            range: nsRange(from: range),
            rect: union,
            suggestedQuoteType: suggestedType
        )
        onSelectionChange?(selection)
    }

    private func nsRange(from range: UITextRange) -> NSRange {
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        return NSRange(location: location, length: length)
    }
}

private enum SelectionHeuristics {
    static func suggestedQuoteType(for text: String) -> PostQuoteMetadata.QuoteType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVersePattern = trimmed.range(of: "\\b\\w+\\s*\\d+:\\d+", options: .regularExpression) != nil
        if hasVersePattern {
            return .verse
        }
        if trimmed.contains(".") || trimmed.contains("?") || trimmed.contains("!") {
            return .sentence
        }
        return .fragment
    }
}

private extension String {
    func ranges(of substring: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex,
              let range = range(of: substring, range: start..<endIndex) {
            result.append(range)
            start = range.upperBound
        }
        return result
    }
}
