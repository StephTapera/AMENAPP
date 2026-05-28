// BilingualReplyComposer.swift
// AMEN App — Language & Accessibility System (Phase 4)
//
// When replying to a post in a different language, shows a compact preview
// of how the reply will appear to the original author after translation.
// Uses on-device NLLanguageRecognizer + Apple Translation framework.

import SwiftUI
import NaturalLanguage

struct BilingualReplyComposer: View {

    let replyText: String
    let postAuthorLanguage: String   // BCP-47 code of the post's detected language

    @State private var translatedPreview: String?
    @State private var isTranslating = false
    @State private var isExpanded = false

    private var userLanguage: String {
        TranslationSettingsManager.shared.preferences.effectiveCreationLanguage
    }

    /// Only show when languages actually differ
    var shouldShow: Bool {
        guard !replyText.isEmpty, replyText.count >= 10 else { return false }
        let base = postAuthorLanguage.components(separatedBy: "-").first ?? postAuthorLanguage
        let userBase = userLanguage.components(separatedBy: "-").first ?? userLanguage
        return base != userBase
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .medium))
                        Text("Preview in \(SupportedLanguage.displayName(for: postAuthorLanguage))")
                            .font(AMENFont.semiBold(11))
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.blue.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                // Expanded preview
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .padding(.horizontal, 10)

                        if isTranslating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Translating…")
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        } else if let preview = translatedPreview {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your reply will appear as:")
                                    .font(AMENFont.regular(10))
                                    .foregroundStyle(.tertiary)
                                Text(preview)
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                        } else {
                            Text("Unable to preview translation")
                                .font(AMENFont.regular(11))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 8)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.1), lineWidth: 0.5)
            )
            .task(id: replyText) {
                await translatePreview()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bilingual reply preview")
        }
    }

    // MARK: - Translation

    private func translatePreview() async {
        let input = replyText
        guard input.count >= 10 else {
            translatedPreview = nil
            return
        }

        // Debounce
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }

        isTranslating = true
        defer { isTranslating = false }

        // Reverse translation: user's language → post author's language
        // Uses AppleTranslationBridge directly since TranslationService always
        // translates TO the user's language, but here we need the opposite direction.
        if #available(iOS 18, *) {
            do {
                let translated = try await AppleTranslationBridge.shared.translate(
                    text: input,
                    from: userLanguage,
                    to: postAuthorLanguage
                )
                translatedPreview = translated
            } catch {
                translatedPreview = nil
            }
        } else {
            translatedPreview = nil
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        BilingualReplyComposer(
            replyText: "God's grace is sufficient for all of us. Keep the faith!",
            postAuthorLanguage: "es"
        )
        BilingualReplyComposer(
            replyText: "Short",
            postAuthorLanguage: "es"
        )
    }
    .padding()
}
