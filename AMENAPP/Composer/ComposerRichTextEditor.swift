// ComposerRichTextEditor.swift
// AMENAPP
//
// Agent D — Rich Text Editor for the AMEN composer.
// Provides: ComposerRichTextProvider, RichTextEditorUIView (UIViewRepresentable),
//           RichTextToolbarView, and ComposerRichTextEditorView (sheet presenter).
//
// Depends only on ComposerContract.swift for shared types.
// Do NOT import or reference any other agent files.

import SwiftUI
import UIKit

// MARK: - ComposerRichTextProvider

/// Observable state holder that implements ComposerAttachmentProvider.
/// The parent composer observes `pendingAttachment` and `isPresented`.
@MainActor
final class ComposerRichTextProvider: ObservableObject, ComposerAttachmentProvider {

    /// The finished attachment produced when the user taps "Done".
    /// Reset to nil by calling `reset()` after the parent has consumed the value.
    @Published var pendingAttachment: ComposerAttachment? = nil

    /// Controls sheet presentation from the parent composer.
    @Published var isPresented: Bool = false

    /// Clears state so the provider can be reused for a new attachment session.
    func reset() {
        pendingAttachment = nil
    }
}

// MARK: - RichTextEditorUIView

/// UIViewRepresentable wrapping UITextView.
/// Renders `spans` as visual NSAttributedString formatting while keeping `text` in sync.
struct RichTextEditorUIView: UIViewRepresentable {

    @Binding var text: String
    @Binding var spans: [ComposerRichSpan]

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditorUIView

        init(_ parent: RichTextEditorUIView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Keep plain-text binding in sync
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            // Re-extract spans from current attributed string
            parent.spans = parent.extractSpans(from: textView.attributedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Notify SwiftUI of selection changes so toolbar active states refresh
            // We post a notification that RichTextToolbarView observes via @State refresh
            NotificationCenter.default.post(name: .richTextSelectionDidChange, object: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.isScrollEnabled = true
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.allowsEditingTextAttributes = false
        textView.typingAttributes = defaultTypingAttributes()
        // Accessibility
        textView.accessibilityLabel = "Long-form text, 0 characters"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Rebuild attributed string when spans change externally
        let attributed = applySpans(spans, to: text)
        // Only replace if content actually changed to avoid cursor jump
        if textView.attributedText.string != attributed.string ||
           !textView.attributedText.isEqual(to: attributed) {
            let selectedRange = textView.selectedRange
            textView.attributedText = attributed
            // Restore cursor — clamp to valid range
            let length = textView.text.utf16.count
            let safeLoc = min(selectedRange.location, length)
            let safeLen = min(selectedRange.length, length - safeLoc)
            textView.selectedRange = NSRange(location: safeLoc, length: safeLen)
        }
        // Update accessibility label with current character count
        textView.accessibilityLabel = "Long-form text, \(text.count) characters"
        textView.typingAttributes = defaultTypingAttributes()
    }

    // MARK: - Span application

    /// Converts plain `text` + `spans` into a fully styled NSAttributedString.
    func applySpans(_ spans: [ComposerRichSpan], to text: String) -> NSAttributedString {
        guard !text.isEmpty else {
            return NSAttributedString(string: "")
        }
        let nsText = text as NSString
        let totalLength = nsText.length
        let result = NSMutableAttributedString(
            string: text,
            attributes: defaultTypingAttributes()
        )

        for span in spans {
            // Guard against out-of-range spans (defensive)
            guard span.location >= 0,
                  span.length > 0,
                  span.location + span.length <= totalLength else { continue }
            let range = NSRange(location: span.location, length: span.length)

            switch span.style {
            case .bold:
                result.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    let baseFont = (value as? UIFont) ?? .preferredFont(forTextStyle: .body)
                    if let boldFont = applyTrait(.traitBold, to: baseFont) {
                        result.addAttribute(.font, value: boldFont, range: subRange)
                    }
                }

            case .italic:
                result.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                    let baseFont = (value as? UIFont) ?? .preferredFont(forTextStyle: .body)
                    if let italicFont = applyTrait(.traitItalic, to: baseFont) {
                        result.addAttribute(.font, value: italicFont, range: subRange)
                    }
                }

            case .underline:
                result.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: range
                )

            case .strikethrough:
                result.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: range
                )

            case .highlight:
                result.addAttribute(
                    .backgroundColor,
                    value: UIColor(AmenTheme.Colors.amenGold).withAlphaComponent(0.30),
                    range: range
                )
            }
        }
        return result
    }

    /// Walks attributes of an NSAttributedString and reconstructs [ComposerRichSpan].
    func extractSpans(from attributedString: NSAttributedString) -> [ComposerRichSpan] {
        guard attributedString.length > 0 else { return [] }
        var result: [ComposerRichSpan] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        // Bold
        attributedString.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) {
                result.append(ComposerRichSpan(location: range.location, length: range.length, style: .bold))
            }
            if traits.contains(.traitItalic) {
                result.append(ComposerRichSpan(location: range.location, length: range.length, style: .italic))
            }
        }

        // Underline
        attributedString.enumerateAttribute(.underlineStyle, in: fullRange, options: []) { value, range, _ in
            guard let raw = value as? Int, raw != 0 else { return }
            result.append(ComposerRichSpan(location: range.location, length: range.length, style: .underline))
        }

        // Strikethrough
        attributedString.enumerateAttribute(.strikethroughStyle, in: fullRange, options: []) { value, range, _ in
            guard let raw = value as? Int, raw != 0 else { return }
            result.append(ComposerRichSpan(location: range.location, length: range.length, style: .strikethrough))
        }

        // Highlight (backgroundColor matching gold tint)
        attributedString.enumerateAttribute(.backgroundColor, in: fullRange, options: []) { value, range, _ in
            guard let color = value as? UIColor else { return }
            // Detect our gold highlight by hue proximity
            var h: CGFloat = 0; var s: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            // amenGold hue ≈ 0.13 (orange-gold), accept within ±0.08
            let goldHue: CGFloat = 0.13
            if abs(h - goldHue) < 0.08 && a > 0.05 {
                result.append(ComposerRichSpan(location: range.location, length: range.length, style: .highlight))
            }
        }

        return result
    }

    // MARK: - Private helpers

    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
    }

    private func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits, to font: UIFont) -> UIFont? {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return nil }
        return UIFont(descriptor: descriptor, size: 0) // 0 = preserve size
    }
}

// MARK: - NSNotification name

extension Notification.Name {
    static let richTextSelectionDidChange = Notification.Name("amenRichTextSelectionDidChange")
}

// MARK: - RichTextToolbarView

/// Horizontal toolbar showing one button per ComposerRichSpanStyle.
/// Applies/removes each style on the current UITextView selection.
struct RichTextToolbarView: View {

    /// Weak reference to the managed UITextView. Bridged via a box so SwiftUI can hold it.
    @ObservedObject var textViewBox: UITextViewBox

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ComposerRichSpanStyle.allCases, id: \.self) { style in
                ToolbarButton(
                    style: style,
                    isActive: isActive(style),
                    reduceMotion: reduceMotion
                ) {
                    toggleStyle(style)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Active state detection

    private func isActive(_ style: ComposerRichSpanStyle) -> Bool {
        guard let tv = textViewBox.textView,
              tv.selectedRange.length > 0 else { return false }
        let range = tv.selectedRange
        guard range.location + range.length <= (tv.attributedText?.length ?? 0) else { return false }
        let attributed = tv.attributedText

        switch style {
        case .bold:
            var result = false
            attributed?.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                if let font = value as? UIFont,
                   font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    result = true
                    stop.pointee = true
                }
            }
            return result

        case .italic:
            var result = false
            attributed?.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
                if let font = value as? UIFont,
                   font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                    result = true
                    stop.pointee = true
                }
            }
            return result

        case .underline:
            var result = false
            attributed?.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
                if let raw = value as? Int, raw != 0 {
                    result = true
                    stop.pointee = true
                }
            }
            return result

        case .strikethrough:
            var result = false
            attributed?.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, stop in
                if let raw = value as? Int, raw != 0 {
                    result = true
                    stop.pointee = true
                }
            }
            return result

        case .highlight:
            var result = false
            attributed?.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, stop in
                if let color = value as? UIColor {
                    var h: CGFloat = 0; var s: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
                    color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                    if abs(h - 0.13) < 0.08 && a > 0.05 {
                        result = true
                        stop.pointee = true
                    }
                }
            }
            return result
        }
    }

    // MARK: - Toggle logic

    private func toggleStyle(_ style: ComposerRichSpanStyle) {
        guard let tv = textViewBox.textView else { return }
        let range = tv.selectedRange
        guard range.length > 0,
              let attributed = tv.attributedText?.mutableCopy() as? NSMutableAttributedString,
              range.location + range.length <= attributed.length else { return }

        let currently = isActive(style)

        switch style {
        case .bold:
            attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let base = (value as? UIFont) ?? .preferredFont(forTextStyle: .body)
                var traits = base.fontDescriptor.symbolicTraits
                if currently { traits.remove(.traitBold) } else { traits.insert(.traitBold) }
                if let desc = base.fontDescriptor.withSymbolicTraits(traits) {
                    attributed.addAttribute(.font, value: UIFont(descriptor: desc, size: 0), range: subRange)
                }
            }

        case .italic:
            attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let base = (value as? UIFont) ?? .preferredFont(forTextStyle: .body)
                var traits = base.fontDescriptor.symbolicTraits
                if currently { traits.remove(.traitItalic) } else { traits.insert(.traitItalic) }
                if let desc = base.fontDescriptor.withSymbolicTraits(traits) {
                    attributed.addAttribute(.font, value: UIFont(descriptor: desc, size: 0), range: subRange)
                }
            }

        case .underline:
            if currently {
                attributed.removeAttribute(.underlineStyle, range: range)
            } else {
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

        case .strikethrough:
            if currently {
                attributed.removeAttribute(.strikethroughStyle, range: range)
            } else {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

        case .highlight:
            if currently {
                attributed.removeAttribute(.backgroundColor, range: range)
            } else {
                let color = UIColor(AmenTheme.Colors.amenGold).withAlphaComponent(0.30)
                attributed.addAttribute(.backgroundColor, value: color, range: range)
            }
        }

        tv.attributedText = attributed
        tv.selectedRange = range
        // Force SwiftUI refresh so active states repaint
        textViewBox.refresh()
    }
}

// MARK: - ToolbarButton (sub-view)

private struct ToolbarButton: View {
    let style: ComposerRichSpanStyle
    let isActive: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: style.toolbarSymbol)
                .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive
                        ? AmenTheme.Colors.amenPurple
                        : AmenTheme.Colors.textSecondary
                )
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isActive
                                ? AmenTheme.Colors.amenPurple.opacity(0.12)
                                : Color.clear
                        )
                )
                .animation(
                    Motion.adaptive(Motion.springPress),
                    value: isActive
                )
        }
        .amenPress()
        .accessibilityLabel(style.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - UITextViewBox (observable bridge)

/// Lightweight ObservableObject that holds a weak reference to a UITextView
/// so RichTextToolbarView can read selection state and re-render when notified.
final class UITextViewBox: ObservableObject {
    weak var textView: UITextView?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .richTextSelectionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let tv = notification.object as? UITextView {
                self?.textView = tv
            }
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Triggers a SwiftUI redraw (e.g. after toggling a style).
    func refresh() {
        objectWillChange.send()
    }
}

// MARK: - ComposerRichTextEditorView

/// Full-screen sheet: nav bar + rich text editor + pinned formatting toolbar.
struct ComposerRichTextEditorView: View {

    private let maxCharacters = 2000

    @ObservedObject var provider: ComposerRichTextProvider
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var spans: [ComposerRichSpan] = []
    @StateObject private var textViewBox = UITextViewBox()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                editorStack

                // Character counter — top-right overlay
                characterCounter
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
            .navigationTitle("Text attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveDraft()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AmenTheme.Colors.textTertiary
                            : AmenTheme.Colors.amenPurple
                    )
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var editorStack: some View {
        VStack(spacing: 0) {
            // Text editor area — fills available space
            ZStack(alignment: .topLeading) {
                RichTextEditorUIView(text: $text, spans: $spans)
                    .accessibilityLabel("Long-form text, \(text.count) characters")
                    .onChange(of: text) { _, _ in
                        // Cap at maxCharacters
                        if text.count > maxCharacters {
                            text = String(text.prefix(maxCharacters))
                        }
                    }

                // Placeholder
                if text.isEmpty {
                    Text("Say even more…")
                        .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                        .font(.preferredFont(forTextStyle: .body).toSwiftUIFont())
                        .padding(.top, 20)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Pinned formatting toolbar above keyboard / safe area
            RichTextToolbarView(textViewBox: textViewBox)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Empty inset — toolbar is already inside the VStack flush with bottom
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private var characterCounter: some View {
        let remaining = maxCharacters - text.count
        let isLow = remaining < 50
        Text("\(remaining)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(isLow ? AmenTheme.Colors.statusError : AmenTheme.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(uiColor: .systemBackground).opacity(0.85))
            )
    }

    // MARK: - Actions

    private func saveDraft() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }
        let attachment = ComposerRichTextAttachment(text: trimmed, richSpans: spans)
        provider.pendingAttachment = .richText(attachment)
        dismiss()
    }
}

// MARK: - UIFont → SwiftUI Font bridge

private extension UIFont {
    func toSwiftUIFont() -> Font {
        Font(self)
    }
}
