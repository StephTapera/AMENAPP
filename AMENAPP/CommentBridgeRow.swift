// CommentBridgeRow.swift
// AMEN App — Accessibility Intelligence Layer (Phase 6)
//
// Enhanced comment row wrapper that adds multilingual bridge features:
// - "Translated from X" chip when auto-translated
// - Foreign language indicator badge
// - Integrates with CommentTranslationBridge for thread-level awareness

import SwiftUI

struct CommentBridgeRow: View {

    let comment: Comment

    @ObservedObject private var bridge = CommentTranslationBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Foreign language indicator
            if let commentId = comment.id,
               bridge.isForeignLanguage(commentId: commentId),
               let langCode = bridge.detectedLanguage(for: commentId) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 9, weight: .medium))
                    Text(SupportedLanguage.displayName(for: langCode))
                        .font(AMENFont.regular(10))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
    }
}
