// ComposerRichTextEditor.swift
// AMENAPP — SocialLayer
//
// Self-contained rich-text composer backed by UITextView + a custom
// NSTextStorage subclass.  Spans are stored as [ComposerRichSpan] (never
// flattened) so round-trip fidelity is guaranteed when composing long-form
// posts (testimonies, church notes, open-table threads).
//
// INTEGRATION NOTE (Phase 4):
// ─────────────────────────────────────────────────────────────────────────
// Replace the plain TextEditor / TextField in CreatePostView with this
// component.  The minimal wiring is:
//
//   // In CreatePostView body, where the existing TextEditor lives:
//   @State private var richSpans: [ComposerRichSpan] = []
//
//   ComposerRichTextEditor(
//       text:       $postText,      // already exists in CreatePostView
//       richSpans:  $richSpans,
//       maxLength:  500             // matches the existing 500-char guard
//   )
//   .frame(minHeight: 140)
//
// When the user taps "Post", build the richText attachment if richSpans is
// non-empty:
//
//   if !richSpans.isEmpty {
//       let rt = ComposerRichTextAttachment(text: postText, richSpans: richSpans)
//       draft.attachments.append(.richText(rt))
//   }
//
// No other changes to CreatePostView are required in Phase 4.
// ─────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

// MARK: - Public entry point

/// Long-form post editor with inline bold / italic / underline / strikethrough /
/// highlight formatting.  Formatting state is persisted as [ComposerRichSpan]
/// on the provided binding — never flattened into the plain-text string.
struct ComposerRichTextEditor: View {
    @Binding var text: String
    @Binding var richSpans: [ComposerRichSpan]
    var placeholder: String = "Share what's on your heart…"
    var maxLength: Int = 500

    // Internal toolbar state — one active flag per style.
    @State private var activeStyles: Set<ComposerRichSpanStyle> = []
    @State private var toolbarVisible: Bool = false

    // Passed down to the representable so toolbar callbacks can reach it.
    @StateObject private var coordinator = RichEditorCoordinator()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ── Text area ──────────────────────────────────────────
                _RichTextViewRepresentable(
                    text:         $text,
                    richSpans:    $richSpans,
                    activeStyles: $activeStyles,
                    toolbarVisible: $toolbarVisible,
                    placeholder:  placeholder,
                    maxLength:    maxLength,
                    coordinator:  coordinator
                )
                .frame(minHeight: 140)
                .padding(.horizontal, 2) // hairline breathing room

                // ── Formatting toolbar ─────────────────────────────────
                if toolbarVisible {
                    _FormattingToolbar(
                        activeStyles: $activeStyles,
                        onToggle: { style in
                            coordinator.toggleStyle(style)
                        }
                    )
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                    )
                    .animation(
                        Motion.adaptive(
                            .spring(response: 0.30, dampingFraction: 0.74)
                        ),
                        value: toolbarVisible
                    )
                }
            }

            // ── Character counter badge ────────────────────────────────
            _CharacterCountBadge(count: text.count, max: maxLength)
                .padding(.trailing, 8)
                .padding(.bottom, toolbarVisible ? 52 : 8)
                .animation(
                    Motion.adaptive(Motion.appearEase),
                    value: toolbarVisible
                )
        }
    }
}

// MARK: - Character counter badge

private struct _CharacterCountBadge: View {
    let count: Int
    let max: Int

    private var isWarning: Bool { count >= max - 50 }
    private var remaining: Int { max - count }

    var body: some View {
        Text("\(count)/\(max)")
            .font(AMENFont.regular(12))
            .foregroundStyle(isWarning ? AmenTheme.Colors.statusError : AmenTheme.Colors.textTertiary)
            .monospacedDigit()
            .accessibilityLabel(
                isWarning
                    ? "\(remaining) characters remaining"
                    : "\(count) of \(max) characters used"
            )
            .animation(Motion.adaptive(Motion.appearEase), value: isWarning)
    }
}

// MARK: - Formatting toolbar

private struct _FormattingToolbar: View {
    @Binding var activeStyles: Set<ComposerRichSpanStyle>
    let onToggle: (ComposerRichSpanStyle) -> Void

    private let styles = ComposerRichSpanStyle.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(styles, id: \.self) { style in
                _ToolbarButton(
                    style:    style,
                    isActive: activeStyles.contains(style),
                    onTap:    { onToggle(style) }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    // Subtle amenBlue tint on the toolbar surface
                    .fill(AmenTheme.Colors.amenBlue.opacity(0.04))
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(height: 0.5)
        }
    }
}

private struct _ToolbarButton: View {
    let style: ComposerRichSpanStyle
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            Image(systemName: style.toolbarSymbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isActive ? .white : AmenTheme.Colors.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive
                              ? AmenTheme.Colors.amenBlue
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.accessibilityLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .animation(Motion.adaptive(Motion.springPress), value: isActive)
    }
}

// MARK: - UIViewRepresentable wrapper

private struct _RichTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var richSpans: [ComposerRichSpan]
    @Binding var activeStyles: Set<ComposerRichSpanStyle>
    @Binding var toolbarVisible: Bool
    let placeholder: String
    let maxLength: Int
    let coordinator: RichEditorCoordinator

    func makeUIView(context: Context) -> UITextView {
        let storage  = RichTextStorage()
        let manager  = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let tv = UITextView(frame: .zero, textContainer: container)
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        tv.keyboardDismissMode = .interactive

        // Dynamic Type body — 16pt nominal, scales with user preference
        let baseSize: CGFloat = 16
        let scaledSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: baseSize)
        tv.font = UIFont(name: "OpenSans-Regular", size: scaledSize)
                  ?? UIFont.systemFont(ofSize: scaledSize)
        tv.textColor = UIColor.label

        // Accessibility
        tv.isAccessibilityElement = true
        tv.accessibilityLabel = "Post text editor"
        tv.accessibilityHint = "Double-tap to edit"

        // Link the coordinator
        coordinator.textView = tv
        coordinator.storage  = storage
        tv.delegate = context.coordinator

        // Placeholder
        context.coordinator.updatePlaceholder(tv, placeholder: placeholder)

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Keep text in sync if changed externally (e.g. draft restore)
        if tv.text != text && !(text.isEmpty && tv.text == placeholder) {
            // Avoid overwriting while the user is typing
            if !tv.isFirstResponder {
                context.coordinator.setAttributedText(tv, text: text, spans: richSpans)
            }
        }
    }

    func makeCoordinator() -> _Coordinator {
        _Coordinator(
            text:         $text,
            richSpans:    $richSpans,
            activeStyles: $activeStyles,
            toolbarVisible: $toolbarVisible,
            placeholder:  placeholder,
            maxLength:    maxLength,
            sharedCoordinator: coordinator
        )
    }
}

// MARK: - UITextViewDelegate coordinator

final class _Coordinator: NSObject, UITextViewDelegate {

    @Binding private var text: String
    @Binding private var richSpans: [ComposerRichSpan]
    @Binding private var activeStyles: Set<ComposerRichSpanStyle>
    @Binding private var toolbarVisible: Bool

    private let placeholder: String
    private let maxLength: Int
    private let sharedCoordinator: RichEditorCoordinator

    init(
        text:         Binding<String>,
        richSpans:    Binding<[ComposerRichSpan]>,
        activeStyles: Binding<Set<ComposerRichSpanStyle>>,
        toolbarVisible: Binding<Bool>,
        placeholder:  String,
        maxLength:    Int,
        sharedCoordinator: RichEditorCoordinator
    ) {
        self._text         = text
        self._richSpans    = richSpans
        self._activeStyles = activeStyles
        self._toolbarVisible = toolbarVisible
        self.placeholder   = placeholder
        self.maxLength     = maxLength
        self.sharedCoordinator = sharedCoordinator
    }

    // MARK: Focus events

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == UIColor.placeholderText {
            textView.text = ""
            textView.textColor = UIColor.label
        }
        withAnimation(
            Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.74))
        ) {
            toolbarVisible = true
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        withAnimation(
            Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.74))
        ) {
            toolbarVisible = false
        }
        updatePlaceholder(textView, placeholder: placeholder)
    }

    // MARK: Input changes

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        let current   = textView.text ?? ""
        let proposed  = (current as NSString).replacingCharacters(in: range, with: text)
        return proposed.count <= maxLength
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView.textColor != UIColor.placeholderText else { return }

        // 1. Push plain text binding
        let newText = textView.text ?? ""
        if self.text != newText { self.text = newText }

        // 2. Re-extract spans from NSTextStorage attributes
        refreshSpans(from: textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView.textColor != UIColor.placeholderText else { return }
        updateActiveStylesFromSelection(textView)
    }

    // MARK: Helpers

    func updatePlaceholder(_ textView: UITextView, placeholder: String) {
        if (textView.text ?? "").isEmpty {
            textView.text = placeholder
            textView.textColor = UIColor.placeholderText
        }
    }

    func setAttributedText(_ textView: UITextView, text: String, spans: [ComposerRichSpan]) {
        guard let storage = textView.textStorage as? RichTextStorage else { return }
        let baseSize: CGFloat = 16
        let scaledSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: baseSize)
        let baseFont = UIFont(name: "OpenSans-Regular", size: scaledSize)
                       ?? UIFont.systemFont(ofSize: scaledSize)
        let attrStr = NSMutableAttributedString(
            string: text,
            attributes: [
                .font:            baseFont,
                .foregroundColor: UIColor.label
            ]
        )
        for span in spans {
            applySpanAttributes(to: attrStr, span: span, baseFont: baseFont)
        }
        storage.setAttributedStringDirectly(attrStr)
        textView.text = text       // keeps textView.text in sync
    }

    // MARK: Active styles from cursor position

    private func updateActiveStylesFromSelection(_ textView: UITextView) {
        let sel = textView.selectedRange
        guard sel.length > 0 || sel.location > 0 else {
            activeStyles = []
            return
        }
        let probeLocation = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        guard probeLocation < (textView.text?.count ?? 0) else {
            activeStyles = []
            return
        }
        let attrs = textView.textStorage.attributes(
            at: probeLocation,
            effectiveRange: nil
        )
        var found: Set<ComposerRichSpanStyle> = []
        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold)   { found.insert(.bold) }
            if traits.contains(.traitItalic) { found.insert(.italic) }
        }
        if attrs[.underlineStyle] != nil              { found.insert(.underline) }
        if attrs[.strikethroughStyle] != nil          { found.insert(.strikethrough) }
        if attrs[.backgroundColor] != nil             { found.insert(.highlight) }
        activeStyles = found
    }

    // MARK: Span extraction from storage → binding

    private func refreshSpans(from textView: UITextView) {
        let storage = textView.textStorage
        var spans: [ComposerRichSpan] = []
        let fullRange = NSRange(location: 0, length: storage.length)

        // Walk all attribute runs and convert back to ComposerRichSpan entries
        storage.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            for style in ComposerRichSpanStyle.allCases {
                if spanStylePresent(style, in: attrs) {
                    spans.append(ComposerRichSpan(
                        location: range.location,
                        length:   range.length,
                        style:    style
                    ))
                }
            }
        }
        // Merge contiguous runs of the same style
        richSpans = mergeSpans(spans)
    }

    private func spanStylePresent(
        _ style: ComposerRichSpanStyle,
        in attrs: [NSAttributedString.Key: Any]
    ) -> Bool {
        switch style {
        case .bold:
            guard let font = attrs[.font] as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        case .italic:
            guard let font = attrs[.font] as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        case .underline:
            return attrs[.underlineStyle] != nil
        case .strikethrough:
            return attrs[.strikethroughStyle] != nil
        case .highlight:
            return attrs[.backgroundColor] != nil
        }
    }

    /// Merges adjacent/overlapping spans of the same style into single entries.
    private func mergeSpans(_ spans: [ComposerRichSpan]) -> [ComposerRichSpan] {
        let sorted = spans.sorted {
            $0.style.rawValue == $1.style.rawValue
                ? $0.location < $1.location
                : $0.style.rawValue < $1.style.rawValue
        }
        var merged: [ComposerRichSpan] = []
        for span in sorted {
            if let last = merged.last,
               last.style == span.style,
               last.location + last.length >= span.location {
                let newLength = max(last.location + last.length, span.location + span.length) - last.location
                merged[merged.count - 1] = ComposerRichSpan(
                    location: last.location,
                    length:   newLength,
                    style:    last.style
                )
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    // MARK: Span attribute helpers

    private func applySpanAttributes(
        to attrStr: NSMutableAttributedString,
        span: ComposerRichSpan,
        baseFont: UIFont
    ) {
        let range = NSRange(location: span.location, length: span.length)
        guard range.location + range.length <= attrStr.length else { return }
        switch span.style {
        case .bold:
            attrStr.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? baseFont
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.union(.traitBold)
                ) {
                    attrStr.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .italic:
            attrStr.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? baseFont
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.union(.traitItalic)
                ) {
                    attrStr.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .underline:
            attrStr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            attrStr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            attrStr.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: range)
        }
    }
}

// MARK: - RichEditorCoordinator (ObservableObject bridge)

/// Observable bridge between the SwiftUI toolbar and the underlying UITextView.
/// Owned by ComposerRichTextEditor, passed down into the representable.
final class RichEditorCoordinator: ObservableObject {
    weak var textView: UITextView?
    weak var storage: RichTextStorage?

    // Called by the SwiftUI toolbar when a style button is tapped.
    func toggleStyle(_ style: ComposerRichSpanStyle) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange
        guard sel.length > 0 else {
            // No selection — typing attributes only (affects next typed character)
            toggleTypingAttribute(style, in: tv)
            return
        }
        toggleAttributeInRange(style, range: sel, in: tv)
    }

    // MARK: Typing attributes (cursor-only toggle)

    private func toggleTypingAttribute(_ style: ComposerRichSpanStyle, in tv: UITextView) {
        var attrs = tv.typingAttributes
        let alreadyActive = styleActiveInTypingAttributes(style, attrs: attrs)
        applyOrRemoveStyleInAttributes(style, to: &attrs, remove: alreadyActive)
        tv.typingAttributes = attrs
    }

    private func styleActiveInTypingAttributes(
        _ style: ComposerRichSpanStyle,
        attrs: [NSAttributedString.Key: Any]
    ) -> Bool {
        switch style {
        case .bold:
            guard let font = attrs[.font] as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        case .italic:
            guard let font = attrs[.font] as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        case .underline:
            return attrs[.underlineStyle] != nil
        case .strikethrough:
            return attrs[.strikethroughStyle] != nil
        case .highlight:
            return attrs[.backgroundColor] != nil
        }
    }

    private func applyOrRemoveStyleInAttributes(
        _ style: ComposerRichSpanStyle,
        to attrs: inout [NSAttributedString.Key: Any],
        remove: Bool
    ) {
        let baseSize: CGFloat = 16
        let scaledSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: baseSize)
        let baseFont = (attrs[.font] as? UIFont)
                       ?? UIFont(name: "OpenSans-Regular", size: scaledSize)
                       ?? UIFont.systemFont(ofSize: scaledSize)

        switch style {
        case .bold:
            let trait = UIFontDescriptor.SymbolicTraits.traitBold
            if remove {
                if let desc = baseFont.fontDescriptor.withSymbolicTraits(
                    baseFont.fontDescriptor.symbolicTraits.subtracting(trait)
                ) {
                    attrs[.font] = UIFont(descriptor: desc, size: baseFont.pointSize)
                }
            } else {
                if let desc = baseFont.fontDescriptor.withSymbolicTraits(
                    baseFont.fontDescriptor.symbolicTraits.union(trait)
                ) {
                    attrs[.font] = UIFont(descriptor: desc, size: baseFont.pointSize)
                }
            }
        case .italic:
            let trait = UIFontDescriptor.SymbolicTraits.traitItalic
            if remove {
                if let desc = baseFont.fontDescriptor.withSymbolicTraits(
                    baseFont.fontDescriptor.symbolicTraits.subtracting(trait)
                ) {
                    attrs[.font] = UIFont(descriptor: desc, size: baseFont.pointSize)
                }
            } else {
                if let desc = baseFont.fontDescriptor.withSymbolicTraits(
                    baseFont.fontDescriptor.symbolicTraits.union(trait)
                ) {
                    attrs[.font] = UIFont(descriptor: desc, size: baseFont.pointSize)
                }
            }
        case .underline:
            if remove { attrs.removeValue(forKey: .underlineStyle) }
            else      { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        case .strikethrough:
            if remove { attrs.removeValue(forKey: .strikethroughStyle) }
            else      { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        case .highlight:
            if remove { attrs.removeValue(forKey: .backgroundColor) }
            else      { attrs[.backgroundColor] = UIColor.systemYellow.withAlphaComponent(0.35) }
        }
    }

    // MARK: Range toggle

    private func toggleAttributeInRange(
        _ style: ComposerRichSpanStyle,
        range: NSRange,
        in tv: UITextView
    ) {
        guard let storage = tv.textStorage as? RichTextStorage else { return }

        // Check whether the style is FULLY present over the range
        let fullyActive = styleFullyCovered(style, range: range, in: storage)

        storage.beginEditing()
        if fullyActive {
            // Remove from entire range
            removeStyle(style, range: range, in: storage)
        } else {
            // Apply to entire range
            applyStyle(style, range: range, in: storage)
        }
        storage.endEditing()

        // Fire delegate so bindings update
        tv.delegate?.textViewDidChange?(tv)
        tv.delegate?.textViewDidChangeSelection?(tv)
    }

    private func styleFullyCovered(
        _ style: ComposerRichSpanStyle,
        range: NSRange,
        in storage: NSTextStorage
    ) -> Bool {
        var covered = true
        storage.enumerateAttributes(in: range, options: []) { attrs, _, stop in
            if !stylePresent(style, in: attrs) {
                covered = false
                stop.pointee = true
            }
        }
        return covered
    }

    private func stylePresent(
        _ style: ComposerRichSpanStyle,
        in attrs: [NSAttributedString.Key: Any]
    ) -> Bool {
        switch style {
        case .bold:
            guard let f = attrs[.font] as? UIFont else { return false }
            return f.fontDescriptor.symbolicTraits.contains(.traitBold)
        case .italic:
            guard let f = attrs[.font] as? UIFont else { return false }
            return f.fontDescriptor.symbolicTraits.contains(.traitItalic)
        case .underline:    return attrs[.underlineStyle] != nil
        case .strikethrough: return attrs[.strikethroughStyle] != nil
        case .highlight:    return attrs[.backgroundColor] != nil
        }
    }

    private func applyStyle(
        _ style: ComposerRichSpanStyle,
        range: NSRange,
        in storage: NSTextStorage
    ) {
        switch style {
        case .bold:
            storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.union(.traitBold)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .italic:
            storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.union(.traitItalic)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .underline:
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .highlight:
            storage.addAttribute(.backgroundColor,
                                 value: UIColor.systemYellow.withAlphaComponent(0.35),
                                 range: range)
        }
    }

    private func removeStyle(
        _ style: ComposerRichSpanStyle,
        range: NSRange,
        in storage: NSTextStorage
    ) {
        switch style {
        case .bold:
            storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.subtracting(.traitBold)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .italic:
            storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
                let f = (val as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                if let desc = f.fontDescriptor.withSymbolicTraits(
                    f.fontDescriptor.symbolicTraits.subtracting(.traitItalic)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: desc, size: f.pointSize), range: r)
                }
            }
        case .underline:
            storage.removeAttribute(.underlineStyle,    range: range)
        case .strikethrough:
            storage.removeAttribute(.strikethroughStyle, range: range)
        case .highlight:
            storage.removeAttribute(.backgroundColor,   range: range)
        }
    }
}

// MARK: - RichTextStorage (NSTextStorage subclass)

/// Custom NSTextStorage that re-applies span attributes from the binding
/// after every edit, keeping visual state and data model in sync.
final class RichTextStorage: NSTextStorage {

    private var _backing = NSMutableAttributedString()

    // ── NSTextStorage primitive overrides ──────────────────────────────

    override var string: String { _backing.string }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        guard location < _backing.length else {
            range?.pointee = NSRange(location: location, length: 0)
            return [:]
        }
        return _backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        _backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(
        _ attrs: [NSAttributedString.Key: Any]?,
        range: NSRange
    ) {
        guard range.location + range.length <= _backing.length else { return }
        beginEditing()
        _backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // ── Direct setter (used when restoring from draft) ─────────────────

    /// Replaces the entire backing store without triggering
    /// the normal UITextView delegate chain.
    func setAttributedStringDirectly(_ attrStr: NSAttributedString) {
        beginEditing()
        let full = NSRange(location: 0, length: _backing.length)
        _backing.replaceCharacters(in: full, with: "")
        edited(.editedCharacters, range: full, changeInLength: -full.length)

        _backing.setAttributedString(attrStr)
        let newFull = NSRange(location: 0, length: _backing.length)
        edited([.editedCharacters, .editedAttributes], range: newFull, changeInLength: newFull.length)
        endEditing()
    }
}
