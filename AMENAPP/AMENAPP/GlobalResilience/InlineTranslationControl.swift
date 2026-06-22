// InlineTranslationControl.swift
// AMEN — Global Resilience System
// Inline pill-button translation control with iOS 18+ TranslationSession support
// and a server-side fallback via NotificationCenter for older OS versions.
//
// Only renders when GlobalResilienceFeatureFlags.shared.autoTranslateEnabled is true.
// Respects LanguageProfile.autoTranslate to trigger on .onAppear without user tap.

import SwiftUI
import Translation

// MARK: - InlineTranslationControl

struct InlineTranslationControl: View {

    // MARK: Inputs

    let originalText: String
    let detectedLanguage: String?
    let confidence: Double?

    /// When true the view auto-triggers translation on appear (no tap required).
    /// Populated from LanguageProfile.autoTranslate at the call site.
    var autoTranslate: Bool = false

    // MARK: State

    @State private var translatedText: String? = nil
    @State private var isTranslating: Bool = false
    @State private var showingOriginal: Bool = false

    // MARK: Environment / Observed

    @ObservedObject private var featureFlags = GlobalResilienceFeatureFlags.shared

    // MARK: Body

    var body: some View {
        if featureFlags.autoTranslateEnabled {
            content
                .onAppear {
                    if autoTranslate && translatedText == nil {
                        Task { await performTranslation() }
                    }
                }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Translated text or original toggle
            if let translated = translatedText {
                if showingOriginal {
                    Text(originalText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .transition(.opacity)
                } else {
                    Text(translated)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    // Show original / Show translation toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingOriginal.toggle()
                        }
                    } label: {
                        Text(showingOriginal ? "Show translation" : "Show original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingOriginal ? "Show translated text" : "Show original text")

                    // Disclaimer
                    Text("Translation may be imperfect")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Translate pill button
                Button {
                    Task { await performTranslation() }
                } label: {
                    HStack(spacing: 5) {
                        if isTranslating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.secondary)
                        } else {
                            Image(systemName: "character.bubble")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(isTranslating ? "Translating…" : translationButtonLabel)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .disabled(isTranslating)
                .accessibilityLabel(translationButtonLabel)
                .accessibilityHint("Translates this message inline")
            }
        }
        // iOS 18+: attach TranslationSession configuration modifier.
        // Wrapped in a @ViewBuilder extension to satisfy the availability constraint.
        .applyTranslationSessionIfAvailable(
            originalText: originalText,
            detectedLanguage: detectedLanguage,
            onTranslated: { result in
                withAnimation(.easeInOut(duration: 0.2)) {
                    translatedText = result
                }
                isTranslating = false
            }
        )
    }

    // MARK: - Helpers

    private var translationButtonLabel: String {
        if let lang = detectedLanguage, !lang.isEmpty {
            return "Translate from \(lang)"
        }
        return "Translate"
    }

    private func performTranslation() async {
        guard !isTranslating, translatedText == nil else { return }
        isTranslating = true

        if #available(iOS 18.0, *) {
            // Translation is handled by TranslationSessionModifier via a trigger.
            // Post a notification to the modifier to initiate the session.
            NotificationCenter.default.post(
                name: .inlineTranslationRequested,
                object: nil,
                userInfo: ["text": originalText]
            )
        } else {
            // Fallback: request server-side translation.
            NotificationCenter.default.post(
                name: .requestServerTranslation,
                object: nil,
                userInfo: [
                    "text": originalText,
                    "language": detectedLanguage ?? ""
                ]
            )
            isTranslating = false
        }
    }
}

// MARK: - TranslationSessionModifier

/// Wraps the iOS 18+ TranslationSession machinery in a ViewModifier so that
/// InlineTranslationControl compiles cleanly on older OS targets.
@available(iOS 18.0, *)
private struct TranslationSessionModifier: ViewModifier {

    let originalText: String
    let detectedLanguage: String?
    let onTranslated: (String) -> Void

    @State private var translationConfig: TranslationSession.Configuration? = nil
    @State private var sessionActive: Bool = false

    func body(content: Content) -> some View {
        content
            .translationTask(translationConfig) { session in
                do {
                    let response = try await session.translate(originalText)
                    onTranslated(response.targetText)
                } catch {
                    print("[InlineTranslationControl] TranslationSession error: \(error)")
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .inlineTranslationRequested)
            ) { notification in
                guard let text = notification.userInfo?["text"] as? String,
                      text == originalText else { return }

                // Build the configuration; source language is optional (auto-detect).
                let sourceLanguage: Locale.Language? = detectedLanguage.flatMap {
                    guard !$0.isEmpty else { return nil }
                    return Locale.Language(identifier: $0)
                }
                translationConfig = TranslationSession.Configuration(
                    source: sourceLanguage,
                    target: Locale.current.language
                )
            }
    }
}

// MARK: - Notification.Name extension

extension Notification.Name {
    /// Internal: fired by InlineTranslationControl to trigger a TranslationSession.
    static let inlineTranslationRequested = Notification.Name("gr_inlineTranslationRequested")
}

// MARK: - iOS < 18 stub modifier

/// No-op modifier used when Translation is unavailable so the call site compiles.
private struct NoOpTranslationModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

// MARK: - View helper for conditional Translation modifier

private extension View {
    /// Applies `TranslationSessionModifier` on iOS 18+ and is a no-op on older OS.
    @ViewBuilder
    func applyTranslationSessionIfAvailable(
        originalText: String,
        detectedLanguage: String?,
        onTranslated: @escaping (String) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.modifier(TranslationSessionModifier(
                originalText: originalText,
                detectedLanguage: detectedLanguage,
                onTranslated: onTranslated
            ))
        } else {
            self.modifier(NoOpTranslationModifier())
        }
    }
}

// MARK: - Preview

#Preview("Inline Translation — idle") {
    VStack(alignment: .leading, spacing: 16) {
        InlineTranslationControl(
            originalText: "Que Dios te bendiga hoy y siempre.",
            detectedLanguage: "es",
            confidence: 0.97
        )

        InlineTranslationControl(
            originalText: "Merci pour votre prière.",
            detectedLanguage: "fr",
            confidence: 0.91,
            autoTranslate: false
        )
    }
    .padding()
    .onAppear {
        GlobalResilienceFeatureFlags.shared.autoTranslateEnabled = true
    }
}
