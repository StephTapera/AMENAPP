// AmenTranslationMessageView.swift
// AMENAPP
//
// Phase 5: Inline translation shown below a message bubble.
// Security: always uses surface: .messages which forces isPublicContent: false.
// DM plaintext is NEVER written to the shared Firestore translation cache.

import SwiftUI

struct AmenTranslationMessageView: View {
    let messageId: String
    let state: TranslationUIState
    let isShowingOriginal: Bool
    let onToggle: () -> Void
    let isFromCurrentUser: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .notNeeded, .disabled:
            EmptyView()

        case .available:
            translateButton

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Translating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .transition(.opacity)

        case .translated(let variant):
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isShowingOriginal {
                    Text(variant.translatedText)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                }
                Button(action: onToggle) {
                    Text(isShowingOriginal ? "Show Translation" : "Show Original")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                .padding(.horizontal, 8)
            }
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.20), value: isShowingOriginal)

        case .error:
            Text("Translation unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }

    private var translateButton: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption)
                Text("Translate")
                    .font(.caption)
            }
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: isFromCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .transition(.opacity)
    }
}
