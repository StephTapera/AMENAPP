//
//  ChurchNotesRichTextEngine.swift
//  AMENAPP
//
//  Feature 1: Rich Text Formatting Engine
//  Provides attributed string formatting for church notes with spiritual
//  highlight categories, heading styles, checklists, and quote blocks.
//  Content is stored as a JSON-encoded attributed format alongside raw text.
//

import Foundation
import UIKit
import SwiftUI

// MARK: - Highlight Category

enum HighlightCategory: String, Codable, CaseIterable {
    case conviction  = "conviction"   // warm butter — key takeaway
    case scripture   = "scripture"    // dusty sky — scripture insight
    case prayer      = "prayer"       // rose mist — prayer items
    case action      = "action"       // muted sage — action steps
    case quote       = "quote"        // stone lavender — pastor quote

    /// Soft, premium fill colors (approved palette).
    var uiColor: UIColor {
        switch self {
        case .conviction: return UIColor(red: 0.957, green: 0.906, blue: 0.631, alpha: 1.0) // #F4E7A1
        case .scripture:  return UIColor(red: 0.863, green: 0.906, blue: 0.969, alpha: 1.0) // #DCE7F7
        case .prayer:     return UIColor(red: 0.953, green: 0.855, blue: 0.875, alpha: 1.0) // #F3DADF
        case .action:     return UIColor(red: 0.867, green: 0.914, blue: 0.847, alpha: 1.0) // #DDE9D8
        case .quote:      return UIColor(red: 0.894, green: 0.890, blue: 0.918, alpha: 1.0) // #E4E3EA
        }
    }

    var swiftUIColor: Color {
        Color(uiColor: uiColor)
    }

    var label: String {
        switch self {
        case .conviction: return "Key Takeaway"
        case .scripture:  return "Scripture"
        case .prayer:     return "Prayer"
        case .action:     return "Action Step"
        case .quote:      return "Quote"
        }
    }
}

// MARK: - Rich Text Attribute Keys

enum RichTextAttributeType: String, Codable {
    case heading
    case subheading
    case bold
    case italic
    case underline
    case highlight
    case quoteBlock
    case checklistItem
    case body
}

// MARK: - Encoded Rich Text Span

/// A serialisable representation of a single attributed run.
struct RichTextSpan: Codable, Identifiable {
    var id: String
    var text: String
    var attributeType: RichTextAttributeType
    var highlightCategory: HighlightCategory?  // only used when attributeType == .highlight
    var isChecked: Bool?                        // only used when attributeType == .checklistItem

    init(
        id: String = UUID().uuidString,
        text: String,
        attributeType: RichTextAttributeType,
        highlightCategory: HighlightCategory? = nil,
        isChecked: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.attributeType = attributeType
        self.highlightCategory = highlightCategory
        self.isChecked = isChecked
    }
}

// MARK: - Rich Text Document

/// The full structured document stored alongside `note.content`.
/// Encode to JSON and store in `note.richContentJSON`.
struct RichTextDocument: Codable {
    var version: Int = 1
    var spans: [RichTextSpan]

    /// Reconstruct plain text from spans (for backward compat with notes.content).
    var plainText: String {
        spans.map { span in
            switch span.attributeType {
            case .checklistItem:
                let check = (span.isChecked == true) ? "[x] " : "[ ] "
                return check + span.text
            case .quoteBlock:
                return "\"" + span.text + "\""
            default:
                return span.text
            }
        }.joined(separator: "\n")
    }
}

// MARK: - AttributedStringFormatter

/// Applies rich text formatting to NSMutableAttributedString.
/// Call methods on a mutable attributed string representing selected or new ranges.
final class AttributedStringFormatter {

    // MARK: - Heading

    func applyHeading(to string: NSMutableAttributedString, range: NSRange) {
        string.addAttributes([
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.label
        ], range: range)
    }

    // MARK: - Subheading

    func applySubheading(to string: NSMutableAttributedString, range: NSRange) {
        string.addAttributes([
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor.label
        ], range: range)
    }

    // MARK: - Bold

    func applyBold(to string: NSMutableAttributedString, range: NSRange) {
        string.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            let baseFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
            let boldFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            string.addAttribute(.font, value: boldFont, range: r)
        }
    }

    // MARK: - Italic

    func applyItalic(to string: NSMutableAttributedString, range: NSRange) {
        string.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            let baseFont = (value as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
            let italicFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            string.addAttribute(.font, value: italicFont, range: r)
        }
    }

    // MARK: - Underline

    func applyUnderline(to string: NSMutableAttributedString, range: NSRange) {
        string.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
    }

    // MARK: - Highlight

    func applyHighlight(color category: HighlightCategory, to string: NSMutableAttributedString, range: NSRange) {
        string.addAttribute(.backgroundColor, value: category.uiColor, range: range)
    }

    // MARK: - Quote Block

    func applyQuoteBlock(to string: NSMutableAttributedString, range: NSRange) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 20
        paragraphStyle.tailIndent = -20
        string.addAttributes([
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont(name: "Georgia", size: 16) ?? UIFont.preferredFont(forTextStyle: .body)
        ], range: range)
    }

    // MARK: - Checklist

    /// Prepends a checkbox marker to the text and sets a monospaced attribute
    /// so the checklist items line up visually.
    func applyChecklist(
        to string: NSMutableAttributedString,
        range: NSRange,
        isChecked: Bool = false
    ) {
        let checkmark = isChecked ? "✅ " : "☐ "
        let insertion = NSAttributedString(string: checkmark, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.label
        ])
        // Only prepend if not already a checklist item
        let existing = string.string as NSString
        let lineStart = existing.lineRange(for: NSRange(location: range.location, length: 0)).location
        let prefix = existing.substring(with: NSRange(location: lineStart, length: min(3, existing.length - lineStart)))
        if prefix != "✅ " && prefix != "☐ " {
            string.insert(insertion, at: lineStart)
        }
    }

    // MARK: - Export

    /// Returns the plain-text string of an attributed string.
    func exportPlainText(from attributed: NSAttributedString) -> String {
        attributed.string
    }

    /// Returns a copy of the attributed string (for rendering).
    func exportAttributedString(from attributed: NSAttributedString) -> NSAttributedString {
        NSAttributedString(attributedString: attributed)
    }

    // MARK: - Document Encoding

    /// Converts an NSAttributedString into a serialisable RichTextDocument.
    /// Only heading, bold, highlight, and body spans are captured — other attributes
    /// are preserved visually but not serialised in this version.
    func encode(attributedString: NSAttributedString) -> RichTextDocument {
        var spans: [RichTextSpan] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let text = (attributedString.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }

            let font = attrs[.font] as? UIFont
            let bgColor = attrs[.backgroundColor] as? UIColor
            let hasUnderline = (attrs[.underlineStyle] as? Int).map { $0 != 0 } ?? false

            let attributeType: RichTextAttributeType
            var highlightCategory: HighlightCategory?

            if let f = font, f.pointSize >= 20 {
                attributeType = .heading
            } else if let f = font, f.pointSize >= 16,
                      f.fontDescriptor.symbolicTraits.contains(.traitBold) {
                attributeType = .subheading
            } else if let f = font, f.fontDescriptor.symbolicTraits.contains(.traitBold) {
                attributeType = .bold
            } else if let f = font, f.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                attributeType = .italic
            } else if hasUnderline {
                attributeType = .underline
            } else if let bg = bgColor {
                attributeType = .highlight
                highlightCategory = HighlightCategory.allCases.first { cat in
                    bg.isApproximatelyEqual(to: cat.uiColor)
                }
            } else {
                attributeType = .body
            }

            spans.append(RichTextSpan(
                text: text,
                attributeType: attributeType,
                highlightCategory: highlightCategory
            ))
        }

        return RichTextDocument(spans: spans)
    }

    /// Reconstructs an NSMutableAttributedString from a RichTextDocument.
    func decode(document: RichTextDocument) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let formatter = AttributedStringFormatter()

        for span in document.spans {
            let part = NSMutableAttributedString(string: span.text, attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ])
            let r = NSRange(location: 0, length: part.length)

            switch span.attributeType {
            case .heading:
                formatter.applyHeading(to: part, range: r)
            case .subheading:
                formatter.applySubheading(to: part, range: r)
            case .bold:
                formatter.applyBold(to: part, range: r)
            case .italic:
                formatter.applyItalic(to: part, range: r)
            case .underline:
                formatter.applyUnderline(to: part, range: r)
            case .highlight:
                if let cat = span.highlightCategory {
                    formatter.applyHighlight(color: cat, to: part, range: r)
                }
            case .quoteBlock:
                formatter.applyQuoteBlock(to: part, range: r)
            case .checklistItem:
                formatter.applyChecklist(to: part, range: r, isChecked: span.isChecked ?? false)
            case .body:
                break
            }

            result.append(part)
        }

        return result
    }
}

// MARK: - UIColor approximate equality helper

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

// MARK: - ChurchNote Rich Content Integration

extension ChurchNote {
    /// JSON-encoded RichTextDocument for this note.
    /// Stored alongside `content` so older clients keep reading plain text.
    var richTextDocument: RichTextDocument? {
        guard let json = richContentJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RichTextDocument.self, from: data)
    }
}
