// VerseTapLabel.swift
// AMENAPP — Media/Save
//
// Renders text with tappable scripture references underlined in Color.amenGold.
// Uses UIViewRepresentable + NSAttributedString for inline link styling.
// Falls back to a plain Text view when no references are detected.

import SwiftUI
import UIKit

// MARK: - VerseTapLabel

@MainActor
struct VerseTapLabel: View {
    var text: String
    var onVerseTapped: (String) -> Void

    @State private var tappedRef: String?
    @State private var showingActionSheet = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var detectedRefs: [DetectedScriptureRef] {
        ScriptureRefDetector.detect(in: text)
    }

    var body: some View {
        if detectedRefs.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        } else {
            ScriptureAttributedLabel(
                text: text,
                refs: detectedRefs,
                onTap: { ref in
                    tappedRef = ref
                    showingActionSheet = true
                }
            )
            .confirmationDialog(
                tappedRef ?? "",
                isPresented: $showingActionSheet,
                titleVisibility: .visible
            ) {
                if let ref = tappedRef {
                    Button("Copy") {
                        UIPasteboard.general.string = ref
                    }
                    Button("Open in Berean") {
                        onVerseTapped(ref)
                    }
                    Button("Attach to Reaction") {
                        onVerseTapped("attach:\(ref)")
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("Scripture Reference")
            }
        }
    }
}

// MARK: - ScriptureAttributedLabel (UIViewRepresentable)

/// UILabel-backed view that renders NSAttributedString with tappable scripture links.
@MainActor
private struct ScriptureAttributedLabel: UIViewRepresentable {
    let text: String
    let refs: [DetectedScriptureRef]
    let onTap: (String) -> Void

    func makeUIView(context: Context) -> UILinkableLabel {
        let label = UILinkableLabel()
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        label.onLinkTapped = onTap
        return label
    }

    func updateUIView(_ label: UILinkableLabel, context: Context) {
        label.attributedText = buildAttributedString()
        label.onLinkTapped = onTap
    }

    private func buildAttributedString() -> NSAttributedString {
        let base = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        // Base style
        base.addAttributes([
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label
        ], range: fullRange)

        // Highlight each detected ref
        let goldColor = UIColor(Color.amenGold)
        for ref in refs {
            guard let nsRange = rangeToNSRange(ref.range, in: text) else { continue }
            base.addAttributes([
                .foregroundColor: goldColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: goldColor,
                .link: ref.reference
            ], range: nsRange)
        }

        return base
    }

    private func rangeToNSRange(_ range: Range<String.Index>, in text: String) -> NSRange? {
        guard let lower = range.lowerBound.samePosition(in: text.utf16),
              let upper = range.upperBound.samePosition(in: text.utf16) else { return nil }
        let lowerOffset = text.utf16.distance(from: text.utf16.startIndex, to: lower)
        let upperOffset = text.utf16.distance(from: text.utf16.startIndex, to: upper)
        return NSRange(location: lowerOffset, length: upperOffset - lowerOffset)
    }
}

// MARK: - UILinkableLabel

/// UILabel subclass that intercepts taps on attributed-string link ranges.
final class UILinkableLabel: UILabel {
    var onLinkTapped: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = true
        lineBreakMode = .byWordWrapping
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let attrText = attributedText else { return }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: bounds.size)
        let textStorage = NSTextStorage(attributedString: attrText)

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let location = gesture.location(in: self)
        let charIndex = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        guard charIndex < attrText.length else { return }

        let attrs = attrText.attributes(at: charIndex, effectiveRange: nil)
        if let link = attrs[.link] as? String {
            onLinkTapped?(link)
        }
    }
}
