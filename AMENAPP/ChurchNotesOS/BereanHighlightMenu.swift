// BereanHighlightMenu.swift
// AMENAPP — ChurchNotesOS
// Floating glass context menu shown when user selects text in a note.

import SwiftUI

// MARK: - Highlight Action

enum BereanHighlightAction: String, CaseIterable, Identifiable {
    case explain, crossReference, greekHebrew, historicalContext
    case discussionQuestions, turnIntoPrayer, createStudyGuide, saveHighlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .explain:             return "Explain"
        case .crossReference:      return "Cross-Reference"
        case .greekHebrew:         return "Greek / Hebrew"
        case .historicalContext:   return "Context"
        case .discussionQuestions: return "Questions"
        case .turnIntoPrayer:      return "→ Prayer"
        case .createStudyGuide:    return "Study Guide"
        case .saveHighlight:       return "Save"
        }
    }

    var icon: String {
        switch self {
        case .explain:             return "sparkles"
        case .crossReference:      return "link"
        case .greekHebrew:         return "character.book.closed.fill"
        case .historicalContext:   return "globe"
        case .discussionQuestions: return "questionmark.bubble.fill"
        case .turnIntoPrayer:      return "hands.sparkles.fill"
        case .createStudyGuide:    return "book.closed.fill"
        case .saveHighlight:       return "bookmark.fill"
        }
    }
}

// MARK: - Berean Highlight Menu

struct BereanHighlightMenu: View {
    let selectedText: String
    let onAction: (BereanHighlightAction, String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 32, height: 3)
                .padding(.top, 8)

            // Selected text preview
            if !selectedText.isEmpty {
                Text(selectedText)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            Divider().opacity(0.3)

            // Action pills row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BereanHighlightAction.allCases) { action in
                        actionPill(action)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background {
            if reduceTransparency {
                Color(.systemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                    }
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 4)
    }

    @ViewBuilder
    private func actionPill(_ action: BereanHighlightAction) -> some View {
        Button {
            onAction(action, selectedText)
            onDismiss()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(action.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.displayName)
    }
}

// MARK: - Preview

#Preview {
    Color.gray.opacity(0.3).ignoresSafeArea()
        .overlay(alignment: .bottom) {
            BereanHighlightMenu(
                selectedText: "The Lord is my shepherd; I shall not want.",
                onAction: { action, text in print(action.displayName, text) },
                onDismiss: {}
            )
            .padding(.bottom, 20)
        }
}
