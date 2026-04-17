// ComposeLanguageDetector.swift
// AMEN App — Language & Accessibility System
//
// On-device NLLanguageRecognizer that runs on compose text.
// Shows a detected language chip and warns if writing in a different language
// from the user's creation language preference.

import SwiftUI
import NaturalLanguage

struct ComposeLanguageChip: View {

    let text: String
    @ObservedObject private var settings = TranslationSettingsManager.shared

    @State private var detectedLanguage: String?
    @State private var detectionConfidence: Double = 0

    private var creationLanguage: String {
        settings.preferences.effectiveCreationLanguage
    }

    private var isDifferentLanguage: Bool {
        guard let detected = detectedLanguage else { return false }
        return detected != creationLanguage
    }

    var body: some View {
        Group {
            if let detected = detectedLanguage, text.count >= 15 {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .medium))

                    if isDifferentLanguage {
                        Text("Writing in \(SupportedLanguage.displayName(for: detected))")
                            .font(AMENFont.semiBold(11))
                    } else {
                        Text(SupportedLanguage.displayName(for: detected))
                            .font(AMENFont.regular(11))
                    }
                }
                .foregroundStyle(isDifferentLanguage ? .orange : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isDifferentLanguage ? Color.orange.opacity(0.1) : Color.primary.opacity(0.04))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)), value: detectedLanguage)
        .task(id: text) {
            await detectLanguage()
        }
    }

    private func detectLanguage() async {
        let input = text
        guard input.count >= 10 else {
            detectedLanguage = nil
            return
        }

        // Debounce: only detect after text stops changing for 300ms
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(input)

        guard let language = recognizer.dominantLanguage else {
            detectedLanguage = nil
            return
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[language] ?? 0

        guard confidence >= 0.5 else {
            detectedLanguage = nil
            return
        }

        // Extract base language code (strip region)
        let code = language.rawValue.components(separatedBy: "-").first ?? language.rawValue

        detectedLanguage = code
        detectionConfidence = confidence
    }
}
