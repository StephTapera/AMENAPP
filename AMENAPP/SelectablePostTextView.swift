import SwiftUI
import UIKit

@MainActor
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
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.tintColor = UIColor(red: 0.97, green: 0.86, blue: 0.25, alpha: 1.0)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.label,
            .underlineStyle: 0
        ]
        // FIX #17: Capture coordinator weakly to prevent a retain cycle.
        // The HighlightSelectableTextView holds onSelectionChange strongly. Without
        // [weak coordinator], the UITextView → closure → Coordinator reference prevents
        // the Coordinator from being released when SwiftUI removes the representable.
        let coordinator = context.coordinator
        textView.onSelectionChange = { [weak coordinator] selection in
            coordinator?.handleSelectionChange(selection)
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HighlightSelectableTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
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
        // MEDIUM FIX: Haptic feedback on text selection change.
        // selectionFeedback is lazily prepared once and reused so that
        // UISelectionFeedbackGenerator does not have to warm up on every
        // delegate callback (which fires at ~60Hz during drag selection).
        private let selectionFeedback = UISelectionFeedbackGenerator()

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
            // Emit selection haptic only when the user has actually selected a range
            // (not on every cursor move or programmatic nil-clear). Checking for a
            // non-empty selectedTextRange avoids firing on simple taps.
            if let range = textView.selectedTextRange, !range.isEmpty {
                selectionFeedback.selectionChanged()
            }
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
            Task { @MainActor in
                parent.isSelecting = selection != nil
                parent.selection = selection
            }
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
        // CRITICAL FIX: Do NOT call addGestureRecognizer(tapGesture) here.
        // tapGesture is a lazy var — the same UITapGestureRecognizer instance is
        // already registered by override init(frame:textContainer:). Calling
        // addGestureRecognizer with the same recognizer a second time adds it
        // twice to gestureRecognizers, causing every tap to fire handleTap()
        // twice (double mention navigation, double onTextTap callbacks).
        // UIKit view restoration routes through init?(coder:) directly, so this
        // was a real double-fire path in production.
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
