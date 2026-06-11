//
//  ComposerTextField.swift
//  AMENAPP
//
//  Self-sizing text input for BereanComposerBar.
//  Renders directly on the capsule glass — no inner card background.
//  Placeholder morphs between expanded and compact strings as the
//  composer collapses on scroll.
//

import SwiftUI

struct ComposerTextField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    let collapseProgress: CGFloat
    let expandedPlaceholder: String
    let compactPlaceholder: String

    /// Maximum allowed text height before the composer starts scrolling.
    var maxHeight: CGFloat = 120

    @State private var measuredHeight: CGFloat = 30

    private func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * min(max(collapseProgress, 0), 1)
    }

    // compacting goes 1→0 as collapse progress goes 0→1
    private var compacting: CGFloat { interpolate(1, 0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Cross-fading placeholder
            if text.isEmpty {
                ZStack(alignment: .leading) {
                    Text(expandedPlaceholder)
                        .font(AMENFont.medium(interpolate(15, 14)))
                        .foregroundStyle(BereanColor.textTertiary)
                        .opacity(Double(compacting))

                    Text(compactPlaceholder)
                        .font(AMENFont.medium(interpolate(15, 14)))
                        .foregroundStyle(BereanColor.textTertiary)
                        .opacity(Double(collapseProgress))
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 7)
                .allowsHitTesting(false)
            }

            // Invisible height-measuring twin
            Text(text.isEmpty ? " " : text)
                .font(AMENFont.regular(16))
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ComposerTextFieldHeightKey.self,
                            value: geo.size.height + 20
                        )
                    }
                )

            // Actual editor — no background, lives directly on capsule glass
            TextEditor(text: $text)
                .font(AMENFont.regular(15))
                .foregroundStyle(BereanColor.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(height: min(max(30, measuredHeight), maxHeight))
                .focused($isFocused)
                .accessibilityLabel("Message Berean")
                .accessibilityHint("Ask Berean about scripture, prayer, church notes, or related questions")
        }
        .onPreferenceChange(ComposerTextFieldHeightKey.self) { h in
            let clamped = min(max(30, h), maxHeight)
            if abs(clamped - measuredHeight) > 1 {
                withAnimation(.easeOut(duration: 0.16)) {
                    measuredHeight = clamped
                }
            }
        }
        .padding(.horizontal, interpolate(6, 3))
        .padding(.vertical, interpolate(4, 3))
    }
}

// MARK: - Height Preference Key

private struct ComposerTextFieldHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 40
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
