// SideBySideTranslationView.swift
// AMEN App — Language & Accessibility System
//
// Stacked view showing original text (muted) + divider + translated text.
// Compact layout with language labels. Liquid Glass card styling.

import SwiftUI

struct SideBySideTranslationView: View {

    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Original text section
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 9, weight: .medium))
                    Text(SupportedLanguage.displayName(for: sourceLanguage))
                        .font(AMENFont.bold(10))
                }
                .foregroundStyle(.tertiary)

                Text(originalText)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)

            // Translated text section
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9, weight: .medium))
                    Text(SupportedLanguage.displayName(for: targetLanguage))
                        .font(AMENFont.bold(10))
                }
                .foregroundStyle(.blue.opacity(0.7))

                Text(translatedText)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Original text in \(SupportedLanguage.displayName(for: sourceLanguage)): \(originalText). Translation in \(SupportedLanguage.displayName(for: targetLanguage)): \(translatedText)")
    }
}

#Preview {
    SideBySideTranslationView(
        originalText: "La gracia de Dios siempre está presente en nuestras vidas.",
        translatedText: "God's grace is always present in our lives.",
        sourceLanguage: "es",
        targetLanguage: "en"
    )
    .padding()
}
