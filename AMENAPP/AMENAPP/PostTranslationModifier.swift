// PostTranslationModifier.swift
// AMENAPP
//
// ViewModifier that attaches translation capability to any post text view.
// Usage:
//   Text(post.content)
//       .postTranslatable(postId: post.id, text: post.content)

import SwiftUI

// MARK: - PostTranslatable modifier

struct PostTranslatable: ViewModifier {

    let postId: String
    let text: String

    @State private var translatedText: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original content (or overlaid to allow a subtle translate-button anchor)
            content

            // Translated text fades in below the original content
            if let translated = translatedText {
                Text(translated)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Translate / Show Original pill
            TranslatePostButton(postId: postId, originalText: text) { translated in
                withAnimation(.easeInOut(duration: 0.3)) {
                    translatedText = translated
                }
            }
        }
    }
}

// MARK: - View extension

extension View {
    /// Attach inline translation capability to a post text view.
    /// The modifier shows nothing when the post is already in the device language.
    func postTranslatable(postId: String, text: String) -> some View {
        modifier(PostTranslatable(postId: postId, text: text))
    }
}
