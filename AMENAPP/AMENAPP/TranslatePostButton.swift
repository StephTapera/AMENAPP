// TranslatePostButton.swift
// AMENAPP
//
// Inline "Translate" pill shown on feed posts that are not in the device language.
// Calls PostTranslationService (which wraps BereanContextualTranslationEngine).
// Invisible when the post is already in the device language.

import SwiftUI

// MARK: - TranslatePostButton

struct TranslatePostButton: View {

    let postId: String
    let originalText: String
    var onTranslated: ((String) -> Void)?

    // MARK: Internal state machine

    private enum TranslationState: Equatable {
        case hidden               // post is already in device language — show nothing
        case idle                 // show "Translate" pill
        case loading              // network in-flight
        case translated(String)  // translation succeeded
        case failed(String)      // error — show retry
    }

    @State private var state: TranslationState = .idle

    // MARK: - Init

    init(
        postId: String,
        originalText: String,
        onTranslated: ((String) -> Void)? = nil
    ) {
        self.postId = postId
        self.originalText = originalText
        self.onTranslated = onTranslated
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()

            case .idle:
                idleButton

            case .loading:
                loadingIndicator

            case .translated:
                showOriginalButton

            case .failed(let message):
                retryButton(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state)
        .task {
            // Evaluate on first appearance — hide if post is already in device language
            if !PostTranslationService.shared.shouldOfferTranslation(for: originalText) {
                state = .hidden
            }
        }
    }

    // MARK: - Sub-views

    private var idleButton: some View {
        Button(action: performTranslation) {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.caption)
                Text("Translate")
                    .font(.caption)
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Translate post")
    }

    private var loadingIndicator: some View {
        ProgressView()
            .scaleEffect(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var showOriginalButton: some View {
        Button {
            // Toggle back to idle so user can see the original
            state = .idle
        } label: {
            Text("Show original")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show original text")
    }

    private func retryButton(message: String) -> some View {
        Button(action: performTranslation) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                Text("Retry")
                    .font(.caption)
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry translation. Error: \(message)")
    }

    // MARK: - Action

    private func performTranslation() {
        state = .loading
        Task {
            do {
                let result = try await PostTranslationService.shared.translate(
                    postId: postId,
                    text: originalText,
                    to: PostTranslationService.shared.preferredLanguage
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    state = .translated(result.translatedText)
                }
                onTranslated?(result.translatedText)
            } catch PostTranslationError.unsupportedLanguagePair(let lang) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state = .failed("Translation to \(lang) is not yet supported.")
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TranslatePostButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Simulates a Spanish post
            TranslatePostButton(
                postId: "preview_1",
                originalText: "Dios es bueno todo el tiempo.",
                onTranslated: { _ in }
            )

            // English post — button should hide itself
            TranslatePostButton(
                postId: "preview_2",
                originalText: "God is good all the time.",
                onTranslated: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
