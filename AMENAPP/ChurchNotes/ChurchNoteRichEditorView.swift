//
//  ChurchNoteRichEditorView.swift
//  AMENAPP
//
//  UIViewRepresentable wrapping UITextView for production-grade rich text editing.
//  Supports bold, italic, underline, highlight, and block conversion through
//  NSAttributedString manipulation with stable cursor behavior.
//

import SwiftUI
import UIKit

// MARK: - Active Format State

/// Describes the formatting at the current cursor position.
struct ChurchNoteActiveFormats: Equatable {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var highlightType: ChurchNoteHighlightType? = nil
}

// MARK: - Rich Editor View

struct ChurchNoteRichEditorView: UIViewRepresentable {

    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var selectionRange: NSRange?
    @Binding var activeFormats: ChurchNoteActiveFormats
    @Binding var isFirstResponder: Bool

    /// Set by parent to trigger formatting commands.
    var formattingCommand: FormattingCommand?
    /// Callback when a formatting command has been executed.
    var onCommandExecuted: (() -> Void)?
    /// Callback to expose the coordinator to the parent for direct operations.
    var onCoordinatorReady: ((Coordinator) -> Void)?

    // MARK: Formatting Command

    enum FormattingCommand: Equatable {
        case bold
        case italic
        case underline
        case highlight(ChurchNoteHighlightType)
        case removeHighlight
    }

    // MARK: - Make / Update

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.allowsEditingTextAttributes = true
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .default
        tv.spellCheckingType = .default
        tv.showsVerticalScrollIndicator = false

        // Load initial content
        if attributedText.length > 0 {
            tv.attributedText = NSAttributedString(attributedString: attributedText)
        } else if !plainText.isEmpty {
            tv.attributedText = NSAttributedString(
                string: plainText,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.label
                ]
            )
        }

        context.coordinator.textView = tv
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Handle first responder
        if isFirstResponder && !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFirstResponder && tv.isFirstResponder {
            tv.resignFirstResponder()
        }

        // Execute formatting commands
        if let cmd = formattingCommand {
            context.coordinator.execute(cmd, in: tv)
            DispatchQueue.main.async {
                onCommandExecuted?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChurchNoteRichEditorView
        weak var textView: UITextView?

        private var isUpdating = false

        init(_ parent: ChurchNoteRichEditorView) {
            self.parent = parent
        }

        // MARK: Delegate

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true
            parent.attributedText = NSAttributedString(attributedString: textView.attributedText)
            parent.plainText = textView.text ?? ""
            isUpdating = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let sel = textView.selectedRange
            parent.selectionRange = (sel.length > 0) ? sel : nil
            detectActiveFormats(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFirstResponder = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFirstResponder = false
        }

        // MARK: Active Format Detection

        private func detectActiveFormats(in textView: UITextView) {
            let pos = textView.selectedRange.location
            guard pos > 0, textView.attributedText.length > 0 else {
                parent.activeFormats = ChurchNoteActiveFormats()
                return
            }

            let checkIndex = min(pos, textView.attributedText.length - 1)
            let attrs = textView.attributedText.attributes(
                at: checkIndex,
                effectiveRange: nil
            )

            var formats = ChurchNoteActiveFormats()

            if let font = attrs[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                formats.isBold = traits.contains(.traitBold)
                formats.isItalic = traits.contains(.traitItalic)
            }

            if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
                formats.isUnderline = true
            }

            if let bgColor = attrs[.backgroundColor] as? UIColor {
                for ht in ChurchNoteHighlightType.allCases {
                    if bgColor.isApproximatelyEqual(to: ht.uiFillColor) {
                        formats.highlightType = ht
                        break
                    }
                }
            }

            parent.activeFormats = formats
        }

        // MARK: Formatting Commands

        func execute(_ command: ChurchNoteRichEditorView.FormattingCommand, in textView: UITextView) {
            let sel = textView.selectedRange
            guard sel.length > 0 else { return }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let formatter = AttributedStringFormatter()

            switch command {
            case .bold:
                toggleBold(mutable: mutable, range: sel)
            case .italic:
                toggleItalic(mutable: mutable, range: sel)
            case .underline:
                toggleUnderline(mutable: mutable, range: sel)
            case .highlight(let type):
                formatter.applyHighlight(color: type.highlightCategory, to: mutable, range: sel)
            case .removeHighlight:
                mutable.removeAttribute(.backgroundColor, range: sel)
            }

            isUpdating = true
            textView.attributedText = mutable
            textView.selectedRange = sel
            parent.attributedText = NSAttributedString(attributedString: mutable)
            parent.plainText = mutable.string
            isUpdating = false
            detectActiveFormats(in: textView)
        }

        // MARK: Toggle helpers

        private func toggleBold(mutable: NSMutableAttributedString, range: NSRange) {
            // Check if already bold
            var allBold = true
            mutable.enumerateAttribute(.font, in: range, options: []) { val, _, stop in
                if let font = val as? UIFont,
                   !font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    allBold = false
                    stop.pointee = true
                }
            }

            mutable.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let base = (val as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                var newTraits = base.fontDescriptor.symbolicTraits
                if allBold {
                    newTraits.remove(.traitBold)
                } else {
                    newTraits.insert(.traitBold)
                }
                let desc = base.fontDescriptor.withSymbolicTraits(newTraits) ?? base.fontDescriptor
                mutable.addAttribute(.font, value: UIFont(descriptor: desc, size: base.pointSize), range: r)
            }
        }

        private func toggleItalic(mutable: NSMutableAttributedString, range: NSRange) {
            var allItalic = true
            mutable.enumerateAttribute(.font, in: range, options: []) { val, _, stop in
                if let font = val as? UIFont,
                   !font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                    allItalic = false
                    stop.pointee = true
                }
            }

            mutable.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let base = (val as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                var newTraits = base.fontDescriptor.symbolicTraits
                if allItalic {
                    newTraits.remove(.traitItalic)
                } else {
                    newTraits.insert(.traitItalic)
                }
                let desc = base.fontDescriptor.withSymbolicTraits(newTraits) ?? base.fontDescriptor
                mutable.addAttribute(.font, value: UIFont(descriptor: desc, size: base.pointSize), range: r)
            }
        }

        private func toggleUnderline(mutable: NSMutableAttributedString, range: NSRange) {
            var allUnderlined = true
            mutable.enumerateAttribute(.underlineStyle, in: range, options: []) { val, _, stop in
                if val == nil || (val as? Int) == 0 {
                    allUnderlined = false
                    stop.pointee = true
                }
            }

            if allUnderlined {
                mutable.removeAttribute(.underlineStyle, range: range)
            } else {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }

        // MARK: Public API for extracting selected text

        /// Extracts the selected text and removes it from the editor. Returns the extracted plain text.
        func extractSelectedText(from textView: UITextView) -> String? {
            let sel = textView.selectedRange
            guard sel.length > 0 else { return nil }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let extracted = (mutable.string as NSString).substring(with: sel)
            mutable.deleteCharacters(in: sel)

            isUpdating = true
            textView.attributedText = mutable
            textView.selectedRange = NSRange(location: sel.location, length: 0)
            parent.attributedText = NSAttributedString(attributedString: mutable)
            parent.plainText = mutable.string
            isUpdating = false

            return extracted
        }
    }
}

// MARK: - UIColor approximate equality (reuse pattern)

private extension UIColor {
    func isApproximatelyEqual(to other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let threshold: CGFloat = 0.1
        return abs(r1 - r2) < threshold && abs(g1 - g2) < threshold && abs(b1 - b2) < threshold
    }
}
