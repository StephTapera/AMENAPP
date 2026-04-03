// BereanMessageMenuView.swift
// AMENAPP
//
// Long-press floating action menu for Berean AI message bubbles.

import SwiftUI

struct BereanMessageMenuView: View {
    let message: String
    let onDismiss: () -> Void
    let onPostToAMEN: (String) -> Void
    /// Called when user taps "Dig In" — triggers a follow-up ask in the parent chat
    var onDigIn: (() -> Void)? = nil
    /// Called when user taps "Pray" — saves to prayer
    var onSaveToPrayer: (() -> Void)? = nil
    /// Called when user taps "Save" — saves to Church Notes
    var onSaveToNotes: (() -> Void)? = nil
    /// Inline contextual actions
    var onAsk: (() -> Void)? = nil
    var onExplain: (() -> Void)? = nil
    var onApply: (() -> Void)? = nil
    var onRelatedVerses: (() -> Void)? = nil
    var onSearch: (() -> Void)? = nil

    private struct ActionItem: Identifiable {
        let id: String
        let icon: String
        let label: String
    }

    private let actions: [ActionItem] = [
        ActionItem(id: "ask", icon: "sparkles", label: "Ask"),
        ActionItem(id: "explain", icon: "text.magnifyingglass", label: "Explain"),
        ActionItem(id: "apply", icon: "figure.walk", label: "Apply"),
        ActionItem(id: "related", icon: "book.pages", label: "Verses"),
        ActionItem(id: "search", icon: "magnifyingglass", label: "Search"),
        ActionItem(id: "digin", icon: "magnifyingglass.circle", label: "Dig In"),
        ActionItem(id: "copy", icon: "doc.on.doc", label: "Copy"),
        ActionItem(id: "notes", icon: "note.text", label: "Notes"),
        ActionItem(id: "pray", icon: "hands.sparkles", label: "Pray"),
        ActionItem(id: "post", icon: "square.and.arrow.up", label: "Post")
    ]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 8
        ) {
            ForEach(actions) { action in
                Button { handleAction(action.id) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(Color(white: 0.2))
                        Text(action.label)
                            .font(.systemScaled(9, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(white: 0.86).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private func handleAction(_ id: String) {
        switch id {
        case "ask":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAsk?()
        case "explain":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onExplain?()
        case "apply":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onApply?()
        case "related":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRelatedVerses?()
        case "search":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSearch?()
        case "copy":
            UIPasteboard.general.string = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "notes":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSaveToNotes?()
        case "post":
            onPostToAMEN(message)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "pray":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSaveToPrayer?()
        case "digin":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDigIn?()
        default: break
        }
        onDismiss()
    }
}
