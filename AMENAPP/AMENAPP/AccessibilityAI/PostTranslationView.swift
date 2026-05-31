// PostTranslationView.swift
// AMEN Universal Accessibility Engine — A2 Post-level Translation UI
// Phase 2: Inline translation with original preserved + AI attribution.

import SwiftUI

// MARK: - Translation State Machine

private enum TranslationState {
    case idle
    case loading
    case translated(text: String, contribution: C2PAAIContribution)
    case error(String)
}

// MARK: - AIContributionBadge

/// Small pill badge: "✦ AI Assisted" — appears after any AI-generated content.
struct AIContributionBadge: View {
    var label: String = "AI Assisted"

    var body: some View {
        HStack(spacing: 3) {
            Text("✦")
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(Color.purple)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
        )
        .accessibilityLabel(Text("AI Assisted content"))
    }
}

// MARK: - PostTranslationButton

/// Drop this view beneath any post body text.
/// It manages its own async translation lifecycle and always preserves the original.
struct PostTranslationButton: View {
    /// The original post text — never mutated, always accessible.
    let originalText: String

    /// Detected or known source language (BCP-47). Pass nil to auto-detect.
    var sourceLang: String? = nil

    @AppStorage("preferredLanguage") private var preferredLanguage: String = ""
    @State private var state: TranslationState = .idle
    @State private var showOriginal: Bool = false

    private var targetLanguage: String {
        if !preferredLanguage.isEmpty { return preferredLanguage }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }

    var body: some View {
        // Guard: only visible when flag is on
        if TrustAccessibilityFeatureFlags.shared.a11yTranslateEnabled {
            VStack(alignment: .leading, spacing: 8) {
                switch state {
                case .idle:
                    idleButton

                case .loading:
                    loadingView

                case .translated(let text, let contribution):
                    translatedView(text: text, contribution: contribution)

                case .error(let message):
                    errorView(message: message)
                }
            }
        }
    }

    // MARK: - Idle

    private var idleButton: some View {
        Button {
            Task { await performTranslation() }
        } label: {
            Label("Translate", systemImage: "globe")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Translate post"))
        .accessibilityHint(Text("Translates this post into your preferred language"))
    }

    // MARK: - Loading

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .accessibilityLabel(Text("Translating…"))
    }

    // MARK: - Translated

    private func translatedView(text: String, contribution: C2PAAIContribution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Always show translated by default; "Show original" toggle reveals source
            if showOriginal {
                Text(originalText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .transition(.opacity)
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                AIContributionBadge()

                Button {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) {
                        showOriginal.toggle()
                    }
                } label: {
                    Text(showOriginal ? "Show translation" : "Show original")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(showOriginal ? "Show translation" : "Show original text")
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showOriginal)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        Text("Translation unavailable")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Translation unavailable: \(message)"))
    }

    // MARK: - Action

    @MainActor
    private func performTranslation() async {
        state = .loading

        let source: String
        if let explicit = sourceLang {
            source = explicit
        } else {
            source = (try? await UniversalTranslationService.shared.autoDetectLanguage(text: originalText)) ?? "en"
        }

        do {
            let output = try await UniversalTranslationService.shared.translate(
                text: originalText,
                from: source,
                to: targetLanguage
            )
            state = .translated(text: output.translated, contribution: output.aiContribution)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
