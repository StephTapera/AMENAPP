// ContextCardView.swift
// AMEN App — Accessibility Intelligence Layer (Phase 4)
//
// Compact glass card showing a faith term's definition, regional note,
// and related verse. Presented as a sheet when user taps an underlined term.

import SwiftUI

struct ContextCardView: View {

    let term: DetectedTerm
    let onDismiss: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(term.glossaryEntry.term)
                    .font(AMENFont.bold(18))
                    .foregroundStyle(Color(.label))

                if !term.glossaryEntry.category.isEmpty {
                    Text(term.glossaryEntry.category)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // Short definition
            Text(term.glossaryEntry.shortDefinition)
                .font(AMENFont.regular(15))
                .foregroundStyle(Color(.secondaryLabel))
                .lineSpacing(3)

            // Long definition (if different from short)
            if term.glossaryEntry.longDefinition != term.glossaryEntry.shortDefinition {
                Text(term.glossaryEntry.longDefinition)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineSpacing(2)
            }

            // Related verse
            if let verse = term.glossaryEntry.relatedVerse {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                    Text(verse)
                        .font(AMENFont.semiBold(13))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
            }

            Divider()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    onSave()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 12))
                        Text("Save Term")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Save this term for later")

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("Got it")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}
