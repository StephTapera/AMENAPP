import SwiftUI
import UIKit

enum ChurchNotesSelectionContextBuilder {
    static let selectedTextLimit = 6_000
    static let surroundingContextLimit = 1_200

    static func selectedText(from selection: String) -> String {
        String(selection.trimmingCharacters(in: .whitespacesAndNewlines).prefix(selectedTextLimit))
    }

    static func selectedText(in body: String, selectedRange: NSRange) -> String {
        let nsBody = body as NSString
        guard isValidRange(selectedRange, in: nsBody) else { return "" }
        return selectedText(from: nsBody.substring(with: selectedRange))
    }

    static func surroundingContext(
        title: String,
        sermonTitle: String,
        churchName: String,
        body: String,
        selectedRange: NSRange
    ) -> String? {
        let metadata = [title, sermonTitle, churchName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        let bodyContext = surroundingText(in: body, selectedRange: selectedRange)
        let context = [metadata, bodyContext]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return context.isEmpty ? nil : context
    }

    private static func surroundingText(in body: String, selectedRange: NSRange) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsBody = body as NSString
        guard isValidRange(selectedRange, in: nsBody) else {
            return String(trimmedBody.prefix(surroundingContextLimit))
        }

        let extraCharacters = max(0, surroundingContextLimit - selectedRange.length)
        let leadingCharacters = extraCharacters / 2
        let trailingCharacters = extraCharacters - leadingCharacters
        let start = max(0, selectedRange.location - leadingCharacters)
        let end = min(nsBody.length, NSMaxRange(selectedRange) + trailingCharacters)
        let range = NSRange(location: start, length: max(0, end - start))
        return nsBody.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidRange(_ range: NSRange, in text: NSString) -> Bool {
        range.length > 0 && range.location != NSNotFound && NSMaxRange(range) <= text.length
    }
}

struct ChurchNotesSelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    var isFocused: Bool
    var onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = false
        textView.adjustsFontForContentSizeCategory = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor.label
        textView.tintColor = UIColor.label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityLabel = "Church note body"
        textView.accessibilityHint = "Edit notes. Select text to use Berean actions."
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            let currentRange = textView.selectedRange
            textView.text = text
            if NSMaxRange(currentRange) <= (text as NSString).length {
                textView.selectedRange = currentRange
            }
        }

        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }

        updateSelection(from: textView)
    }

    private func updateSelection(from textView: UITextView) {
        let range = textView.selectedRange
        let selection = ChurchNotesSelectionContextBuilder.selectedText(
            in: textView.text ?? "",
            selectedRange: range
        )
        guard selection != selectedText || range != selectedRange else { return }

        DispatchQueue.main.async {
            selectedText = selection
            selectedRange = selection.isEmpty ? NSRange(location: NSNotFound, length: 0) : range
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChurchNotesSelectableTextEditor

        init(_ parent: ChurchNotesSelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.updateSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.updateSelection(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChanged(true)
            parent.updateSelection(from: textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChanged(false)
            parent.updateSelection(from: textView)
        }
    }
}
